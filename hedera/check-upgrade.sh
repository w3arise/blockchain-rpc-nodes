#!/usr/bin/env bash
#
# Compare pinned (and running) Hedera Mirror Node / JSON-RPC Relay versions
# against upstream GitHub releases and print upgrade guidance.
#
# Usage: ./check-upgrade.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

MIRROR_REPO="hiero-ledger/hiero-mirror-node"
RELAY_REPO="hiero-ledger/hiero-json-rpc-relay"
BLOCK_STREAM_MIN_MIRROR="0.160.0"

UPGRADES_AVAILABLE=0

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

normalize_version() {
  local version="${1#v}"
  version="${version#V}"
  printf '%s' "${version}"
}

# True when $1 is strictly less than $2.
version_lt() {
  local left right
  left="$(normalize_version "$1")"
  right="$(normalize_version "$2")"
  [[ "${left}" != "${right}" && "${left}" == "$(printf '%s\n' "${left}" "${right}" | sort -V | head -n1)" ]]
}

read_env_value() {
  local name="$1"
  local file value
  for file in "${ENV_FILE}" "${ENV_TEMPLATE}"; do
    if [[ -f "${file}" ]]; then
      value="$(grep -E "^${name}=" "${file}" | tail -n1 | cut -d= -f2- || true)"
      if [[ -n "${value}" ]]; then
        printf '%s' "${value}"
        return 0
      fi
    fi
  done
  return 1
}

fetch_latest_release() {
  local repo="$1"
  curl -fsSL --connect-timeout 15 --max-time 30 \
    "https://api.github.com/repos/${repo}/releases/latest"
}

release_field() {
  local json="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".${field} // empty" <<< "${json}"
  else
    case "${field}" in
      tag_name) sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "${json}" | head -n1 ;;
      html_url) sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "${json}" | head -n1 ;;
      published_at) sed -n 's/.*"published_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "${json}" | head -n1 ;;
    esac
  fi
}

print_version_row() {
  local label="$1"
  local current="$2"
  local latest="$3"
  local url="$4"
  local status="ok"

  if version_lt "${current}" "${latest}"; then
    status="upgrade available"
    UPGRADES_AVAILABLE=1
  fi
  printf '  %-22s %-10s  latest %-10s  (%s)\n' "${label}:" "${current}" "${latest}" "${status}"
  printf '    %s\n' "${url}"
}

running_mirror_version() {
  local cid version
  cid="$(docker ps --filter 'name=hedera-mirror-importer' --format '{{.ID}}' 2>/dev/null | head -n1 || true)"
  if [[ -z "${cid}" ]]; then
    return 1
  fi
  version="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "${cid}" 2>/dev/null || true)"
  if [[ -z "${version}" || "${version}" == "<no value>" ]]; then
    version="$(docker inspect --format '{{.Config.Image}}' "${cid}" 2>/dev/null | sed -n 's/.*:\([0-9][0-9.]*\)$/\1/p')"
  fi
  [[ -n "${version}" ]] || return 1
  normalize_version "${version}"
}

running_relay_version() {
  local cid version
  cid="$(docker ps --filter 'name=hedera-json-rpc-relay' --filter 'status=running' --format '{{.ID}}' 2>/dev/null | head -n1 || true)"
  if [[ -z "${cid}" ]]; then
    return 1
  fi
  version="$(docker inspect --format '{{.Config.Image}}' "${cid}" 2>/dev/null | sed -n 's/.*:\([0-9][0-9.]*\)$/\1/p')"
  [[ -n "${version}" ]] || return 1
  normalize_version "${version}"
}

bootstrap_export_version() {
  local export_file host_dir
  host_dir="$(read_env_value HOST_BOOTSTRAP_DATADIR 2>/dev/null || true)"
  host_dir="${host_dir:-$HOME/hedera-bootstrap-data}"
  export_file="${host_dir}/export/MIRRORNODE_VERSION.gz"
  if [[ ! -f "${export_file}" ]]; then
    return 1
  fi
  gzip -dc "${export_file}" 2>/dev/null | tr -d '[:space:]'
}

list_gcs_exports() {
  local project_id
  project_id="$(read_env_value GCP_PROJECT_ID 2>/dev/null || true)"
  if [[ -z "${project_id}" ]] || ! command -v gcloud >/dev/null 2>&1; then
    return 1
  fi
  gcloud storage ls --billing-project="${project_id}" gs://mirrornode-db-export/MAINNET/ 2>/dev/null \
    | sed -n 's|.*/MAINNET/\([0-9][0-9.]*\)/|\1|p' \
    | sort -V
}

require_command curl

PINNED_MIRROR="$(read_env_value MIRROR_NODE_VERSION || true)"
PINNED_RELAY="$(read_env_value RELAY_VERSION || true)"

if [[ -z "${PINNED_MIRROR}" || -z "${PINNED_RELAY}" ]]; then
  echo "ERROR: could not read MIRROR_NODE_VERSION / RELAY_VERSION from .env or env.template" >&2
  exit 1
fi

PINNED_MIRROR="$(normalize_version "${PINNED_MIRROR}")"
PINNED_RELAY="$(normalize_version "${PINNED_RELAY}")"

echo "Hedera upgrade check"
echo

MIRROR_JSON="$(fetch_latest_release "${MIRROR_REPO}")"
RELAY_JSON="$(fetch_latest_release "${RELAY_REPO}")"

LATEST_MIRROR="$(normalize_version "$(release_field "${MIRROR_JSON}" tag_name)")"
LATEST_RELAY="$(normalize_version "$(release_field "${RELAY_JSON}" tag_name)")"
MIRROR_URL="$(release_field "${MIRROR_JSON}" html_url)"
RELAY_URL="$(release_field "${RELAY_JSON}" html_url)"
MIRROR_PUBLISHED="$(release_field "${MIRROR_JSON}" published_at)"
RELAY_PUBLISHED="$(release_field "${RELAY_JSON}" published_at)"

echo "Pinned (.env / env.template):"
print_version_row "Mirror Node" "${PINNED_MIRROR}" "${LATEST_MIRROR}" "${MIRROR_URL}"
print_version_row "JSON-RPC Relay" "${PINNED_RELAY}" "${LATEST_RELAY}" "${RELAY_URL}"
echo

if command -v docker >/dev/null 2>&1; then
  RUNNING_MIRROR="$(running_mirror_version || true)"
  RUNNING_RELAY="$(running_relay_version || true)"
  if [[ -n "${RUNNING_MIRROR:-}" || -n "${RUNNING_RELAY:-}" ]]; then
    echo "Running containers:"
    if [[ -n "${RUNNING_MIRROR:-}" ]]; then
      print_version_row "importer image" "${RUNNING_MIRROR}" "${LATEST_MIRROR}" "${MIRROR_URL}"
    fi
    if [[ -n "${RUNNING_RELAY:-}" ]]; then
      print_version_row "relay image" "${RUNNING_RELAY}" "${LATEST_RELAY}" "${RELAY_URL}"
    fi
    echo
  fi
fi

BOOTSTRAP_VERSION="$(bootstrap_export_version || true)"
if [[ -n "${BOOTSTRAP_VERSION:-}" ]]; then
  echo "Bootstrap export (local): ${BOOTSTRAP_VERSION}"
  if [[ "${BOOTSTRAP_VERSION}" != "${PINNED_MIRROR}" ]]; then
    echo "  note: export version differs from pinned MIRROR_NODE_VERSION"
  fi
  echo
fi

GCS_VERSIONS="$(list_gcs_exports || true)"
if [[ -n "${GCS_VERSIONS:-}" ]]; then
  echo "GCS bootstrap exports (MAINNET):"
  while IFS= read -r version; do
    [[ -n "${version}" ]] && echo "  ${version}"
  done <<< "${GCS_VERSIONS}"
  echo "  (new exports are for fresh bootstrap only; in-place upgrades do not require re-download)"
  echo
fi

echo "Release notes:"
echo "  Mirror: https://github.com/${MIRROR_REPO}/releases"
echo "  Relay:  https://github.com/${RELAY_REPO}/releases"
if [[ -n "${MIRROR_PUBLISHED}" ]]; then
  echo "  Latest mirror published: ${MIRROR_PUBLISHED}"
fi
if [[ -n "${RELAY_PUBLISHED}" ]]; then
  echo "  Latest relay published:  ${RELAY_PUBLISHED}"
fi
echo

if version_lt "${PINNED_MIRROR}" "${BLOCK_STREAM_MIN_MIRROR}"; then
  UPGRADES_AVAILABLE=1
  echo "WARNING: pinned Mirror Node ${PINNED_MIRROR} is below ${BLOCK_STREAM_MIN_MIRROR}."
  echo "  Mainnet block-stream cutover requires >= ${BLOCK_STREAM_MIN_MIRROR} or ingestion stops."
  echo "  https://hedera.com/blog/block-streams-replace-the-record-stream-by-default-starting-september-2026-action-required-by-mirror-node-operators/"
  echo
fi

if [[ "${UPGRADES_AVAILABLE}" -eq 1 ]]; then
  echo "Suggested upgrade (after importer is healthy on the current schema):"
  echo "  1. Edit .env: MIRROR_NODE_VERSION=${LATEST_MIRROR}, RELAY_VERSION=${LATEST_RELAY}"
  echo "  2. ./configure.sh"
  echo "  3. docker compose --profile mirror --profile relay up -d"
  echo "  4. docker compose logs -f importer   # watch Flyway migrations"
  echo
  echo "Compare releases since your pin:"
  echo "  https://github.com/${MIRROR_REPO}/compare/v${PINNED_MIRROR}...v${LATEST_MIRROR}"
  echo "  https://github.com/${RELAY_REPO}/compare/v${PINNED_RELAY}...v${LATEST_RELAY}"
  exit 1
fi

echo "Pinned versions match upstream latest."
exit 0
