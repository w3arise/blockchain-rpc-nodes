#!/usr/bin/env bash
#
# Initialize Core mainnet geth datadir from genesis (from-scratch sync).
#
# Prefer ./restore-snapshot.sh for mainnet. Skip this when restoring a snapshot.
#
# Usage: ./init-database.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

EXPECTED_CHAIN_ID="1116"
GENESIS_FILE="${SCRIPT_DIR}/config/genesis.json"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/core-data}"

if [[ ! -f "${GENESIS_FILE}" ]]; then
  echo "ERROR: missing ${GENESIS_FILE}" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  CID="$(jq -r '.config.chainId // .chainId' "${GENESIS_FILE}" 2>/dev/null || echo "")"
  if [[ -n "${CID}" && "${CID}" != "${EXPECTED_CHAIN_ID}" ]]; then
    echo "ERROR: genesis chainId ${CID} != expected ${EXPECTED_CHAIN_ID}" >&2
    exit 1
  fi
fi

if [[ -d "${DATA_DIR}/geth" ]]; then
  echo "WARNING: ${DATA_DIR} already contains a geth database."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: 'docker' is required." >&2
  exit 1
}

echo "==> Building Core image (if needed)"
docker compose build core-node

echo "==> Initializing Core mainnet (hash scheme) into ${DATA_DIR}"
docker compose run --rm \
  --entrypoint geth \
  -v "${DATA_DIR}:/data" \
  -v "${GENESIS_FILE}:/config/genesis.json:ro" \
  core-node init --datadir /data --state.scheme=hash /config/genesis.json

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
