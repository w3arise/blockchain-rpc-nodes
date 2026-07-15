#!/usr/bin/env bash
#
# Initialize Bitlayer mainnet geth datadir from embedded genesis (dumpgenesis + init).
#
# Skip when restoring snapshot data into $HOME/bitlayer-data.
#
# Usage: ./init-database.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

EXPECTED_CHAIN_ID="200901"
GENESIS_FILE="${SCRIPT_DIR}/config/genesis.json"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/bitlayer-data}"

if [[ -d "${DATA_DIR}/geth" ]]; then
  echo "WARNING: ${DATA_DIR} already contains a geth database."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}" "${SCRIPT_DIR}/config"

for tool in docker; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

echo "==> Building Bitlayer image (if needed)"
docker compose build bitlayer-node

echo "==> Dumping mainnet genesis to ${GENESIS_FILE}"
docker compose run --rm -T \
  --entrypoint /usr/local/bin/geth \
  bitlayer-node --mainnet dumpgenesis 2>/dev/null > "${GENESIS_FILE}"

if command -v jq >/dev/null 2>&1; then
  CID="$(jq -r '.config.chainId // .chainId' "${GENESIS_FILE}" 2>/dev/null || echo "")"
  if [[ -n "${CID}" && "${CID}" != "${EXPECTED_CHAIN_ID}" ]]; then
    echo "ERROR: genesis chainId ${CID} != expected ${EXPECTED_CHAIN_ID}" >&2
    exit 1
  fi
fi

echo "==> Initializing Bitlayer mainnet into ${DATA_DIR}"
docker compose run --rm \
  --entrypoint /usr/local/bin/geth \
  -v "${DATA_DIR}:/data" \
  -v "${GENESIS_FILE}:/config/genesis.json:ro" \
  bitlayer-node init --datadir /data /config/genesis.json

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "    genesis: ${GENESIS_FILE}"
echo "Next: docker compose up -d"
