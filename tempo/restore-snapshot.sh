#!/usr/bin/env bash
#
# Download an official Tempo snapshot into HOST_DATADIR via the pinned Docker image.
#
# Usage: ./restore-snapshot.sh
#        ./restore-snapshot.sh --force   # overwrite existing snapshot data
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/tempo-data}"
CHAIN="${CHAIN:-mainnet}"
PROFILE="${SNAPSHOT_PROFILE:-archive}"
IMAGE="${TEMPO_IMAGE:?TEMPO_IMAGE must be set in .env}"

mkdir -p "${DATA_DIR}"

EXTRA_ARGS=()
if [[ "${1:-}" == "--force" ]]; then
  EXTRA_ARGS+=(--force)
fi

case "${PROFILE}" in
  archive|full|minimal) ;;
  *)
    echo "ERROR: SNAPSHOT_PROFILE must be archive, full, or minimal (got: ${PROFILE})" >&2
    exit 1
    ;;
esac

echo "==> Downloading Tempo ${CHAIN} snapshot (${PROFILE}) into ${DATA_DIR}"
echo "    Browse snapshots: https://snapshots.tempoxyz.dev/"
echo "    This can take a while; resumable downloads are enabled by default."

docker run --rm \
  --entrypoint tempo \
  -v "${DATA_DIR}:/data" \
  "${IMAGE}" \
  download \
  --chain "${CHAIN}" \
  --datadir /data \
  "--${PROFILE}" \
  "${EXTRA_ARGS[@]}"

echo ""
echo "Snapshot restore finished. Start the node with:"
echo "  docker compose up -d"
