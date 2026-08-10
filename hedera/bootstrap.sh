#!/usr/bin/env bash
#
# Download and import the official Hedera Mirror Node database export.
#
# Usage:
#   ./bootstrap.sh list
#   ./bootstrap.sh download [version]       # full history (large, see README sizing)
#   ./bootstrap.sh download-schema          # schema only: skip history, sync forward from ~now
#   ./bootstrap.sh init
#   ./bootstrap.sh import                   # not used after download-schema
#   ./bootstrap.sh status
#   ./bootstrap.sh watch
#   ./bootstrap.sh start-mirror
#   ./bootstrap.sh start-relay

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
BOOTSTRAP_ENV="${SCRIPT_DIR}/bootstrap.env"

if [[ ! -f "${ENV_FILE}" || ! -f "${BOOTSTRAP_ENV}" ]]; then
  echo "ERROR: run ./configure.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${ENV_FILE}"

EXPORT_DIR="${HOST_BOOTSTRAP_DATADIR}/export"
TRACKING_FILE="${HOST_BOOTSTRAP_DATADIR}/bootstrap-logs/tracking.json"
SKIP_DB_INIT_FILE="${HOST_BOOTSTRAP_DATADIR}/bootstrap-logs/SKIP_DB_INIT"
SCHEMA_ONLY_MARKER="${HOST_BOOTSTRAP_DATADIR}/.schema-only"
BOOTSTRAP_IMAGE="hedera-mirror-bootstrap:${MIRROR_NODE_VERSION}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME:-hedera}-network"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" ]]; then
    echo "ERROR: ${name} is empty in .env" >&2
    exit 1
  fi
}

verify_export_version() {
  local version_file="${EXPORT_DIR}/MIRRORNODE_VERSION.gz"
  local export_version
  if [[ ! -f "${version_file}" ]]; then
    echo "ERROR: missing ${version_file}; run ./bootstrap.sh download" >&2
    exit 1
  fi
  export_version="$(gzip -dc "${version_file}" | tr -d '[:space:]')"
  if [[ "${export_version}" != "${MIRROR_NODE_VERSION}" ]]; then
    echo "ERROR: export version ${export_version} does not match MIRROR_NODE_VERSION=${MIRROR_NODE_VERSION}" >&2
    echo "Set MIRROR_NODE_VERSION to the export version and rerun ./configure.sh." >&2
    exit 1
  fi
  echo "export version matches Mirror Node ${MIRROR_NODE_VERSION}"
}

build_bootstrap_image() {
  docker build \
    --build-arg "MIRROR_NODE_VERSION=${MIRROR_NODE_VERSION}" \
    --tag "${BOOTSTRAP_IMAGE}" \
    --file "${SCRIPT_DIR}/Dockerfile.bootstrap" \
    "${SCRIPT_DIR}"
}

ensure_bootstrap_image() {
  if ! docker image inspect "${BOOTSTRAP_IMAGE}" >/dev/null 2>&1; then
    build_bootstrap_image
  fi
}

start_database() {
  docker compose up -d db
  for _ in $(seq 1 60); do
    if docker compose exec -T db pg_isready -U postgres -d postgres >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  echo "ERROR: PostgreSQL did not become ready" >&2
  exit 1
}

run_bootstrap() {
  docker run --rm \
    --network "${DOCKER_NETWORK}" \
    --user "$(id -u):$(id -g)" \
    --volume "${HOST_BOOTSTRAP_DATADIR}:/work" \
    --volume "${BOOTSTRAP_ENV}:/config/bootstrap.env:ro" \
    "${BOOTSTRAP_IMAGE}" "$@"
}

check_import_complete() {
  if [[ -f "${SCHEMA_ONLY_MARKER}" ]]; then
    if [[ ! -f "${SKIP_DB_INIT_FILE}" ]]; then
      echo "ERROR: schema-only mode selected but ./bootstrap.sh init has not completed" >&2
      exit 1
    fi
    echo "schema-only mode: no historical data was imported; the importer will start from ~now"
    return
  fi
  require_command jq
  if [[ ! -f "${TRACKING_FILE}" ]]; then
    echo "ERROR: no bootstrap tracking file; complete the import first (or use ./bootstrap.sh download-schema for a fresh, no-history start)" >&2
    exit 1
  fi
  if ! jq -e 'length > 0 and all(.[]; .status == "IMPORTED")' "${TRACKING_FILE}" >/dev/null; then
    echo "ERROR: bootstrap has unfinished or failed files" >&2
    jq -r 'to_entries[] | select(.value.status != "IMPORTED") | "\(.value.status) \(.key)"' "${TRACKING_FILE}" >&2
    exit 1
  fi
}

command_name="${1:-help}"
case "${command_name}" in
  list)
    require_command gcloud
    require_value GCP_PROJECT_ID
    gcloud storage ls \
      --billing-project="${GCP_PROJECT_ID}" \
      gs://mirrornode-db-export/MAINNET/
    ;;

  download)
    require_command gcloud
    require_value GCP_PROJECT_ID
    requested_version="${2:-${MIRROR_NODE_VERSION}}"
    if [[ "${requested_version}" != "${MIRROR_NODE_VERSION}" ]]; then
      echo "ERROR: requested ${requested_version}, but MIRROR_NODE_VERSION=${MIRROR_NODE_VERSION}" >&2
      echo "Update .env and rerun ./configure.sh before downloading another version." >&2
      exit 1
    fi
    mkdir -p "${EXPORT_DIR}"
    export CLOUDSDK_STORAGE_SLICED_OBJECT_DOWNLOAD_MAX_COMPONENTS=1
    gcloud storage rsync -r \
      -x ".*_atma\\.csv\\.gz$" \
      --billing-project="${GCP_PROJECT_ID}" \
      "gs://mirrornode-db-export/MAINNET/${MIRROR_NODE_VERSION}/" \
      "${EXPORT_DIR}/"
    verify_export_version
    ;;

  download-schema)
    require_command gcloud
    require_value GCP_PROJECT_ID
    mkdir -p "${EXPORT_DIR}"
    gcloud storage cp \
      --billing-project="${GCP_PROJECT_ID}" \
      "gs://mirrornode-db-export/MAINNET/${MIRROR_NODE_VERSION}/MIRRORNODE_VERSION.gz" \
      "gs://mirrornode-db-export/MAINNET/${MIRROR_NODE_VERSION}/schema.sql.gz" \
      "${EXPORT_DIR}/"
    verify_export_version
    touch "${SCHEMA_ONLY_MARKER}"
    echo "downloaded schema only (no historical CSV data)"
    echo "next: ./bootstrap.sh init, then ./bootstrap.sh start-mirror (skips the import step)"
    ;;

  build)
    require_command docker
    verify_export_version
    build_bootstrap_image
    ;;

  init)
    require_command docker
    verify_export_version
    start_database
    ensure_bootstrap_image
    run_bootstrap init \
      --config /config/bootstrap.env \
      --data-dir /work/export
    ;;

  import)
    require_command docker
    if [[ -f "${SCHEMA_ONLY_MARKER}" ]]; then
      echo "ERROR: schema-only mode selected (no CSV data was downloaded); there is nothing to import" >&2
      echo "Run ./bootstrap.sh start-mirror directly to start syncing forward from ~now." >&2
      exit 1
    fi
    verify_export_version
    start_database
    ensure_bootstrap_image
    run_bootstrap import \
      --config /config/bootstrap.env \
      --data-dir /work/export \
      --manifest /work/export/manifest.csv \
      --jobs "${BOOTSTRAP_JOBS}"
    ;;

  status)
    require_command docker
    ensure_bootstrap_image
    run_bootstrap status --config /config/bootstrap.env
    ;;

  watch)
    require_command docker
    ensure_bootstrap_image
    run_bootstrap watch \
      --config /config/bootstrap.env \
      --manifest /work/export/manifest.csv \
      --data-dir /work/export
    ;;

  start-mirror)
    check_import_complete
    require_value GCP_PROJECT_ID
    require_value GCP_ACCESS_KEY
    require_value GCP_SECRET_KEY
    docker compose --profile mirror up -d
    ;;

  start-relay)
    check_import_complete
    if [[ "${READ_ONLY}" != "true" ]]; then
      require_value OPERATOR_ID_MAIN
      require_value OPERATOR_KEY_MAIN
    fi
    docker compose --profile mirror --profile relay up -d
    ;;

  help|--help|-h)
    echo "Usage: $0 {list|download [version]|download-schema|build|init|import|status|watch|start-mirror|start-relay}"
    ;;

  *)
    echo "ERROR: unknown command: ${command_name}" >&2
    exit 1
    ;;
esac
