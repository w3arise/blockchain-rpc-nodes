#!/usr/bin/env bash
#
# Initialize Neo X geth datadir from genesis (from-scratch sync).
#
# Skip when restoring a mainnet archival snapshot into $HOME/neox-data.
#
# Usage:
#   ./init-database.sh            # mainnet (default)
#   ./init-database.sh testnet    # testnet T4
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NETWORK="${1:-mainnet}"
case "${NETWORK}" in
  mainnet)
    GENESIS_FILE="${SCRIPT_DIR}/config/genesis_mainnet.json"
    EXPECTED_CHAIN_ID="47763"
    ;;
  testnet)
    GENESIS_FILE="${SCRIPT_DIR}/config/genesis_testnet.json"
    EXPECTED_CHAIN_ID="12227332"
    ;;
  *)
    echo "ERROR: unknown network: ${NETWORK} (use mainnet|testnet)" >&2
    exit 1
    ;;
esac

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/neox-data}"

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

for tool in docker; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

echo "==> Building Neo X image (if needed)"
docker compose build neox-node

echo "==> Initializing Neo X ${NETWORK} into ${DATA_DIR}"
docker compose run --rm \
  --entrypoint geth \
  -v "${DATA_DIR}:/data" \
  -v "${GENESIS_FILE}:/config/genesis.json:ro" \
  neox-node init --datadir /data /config/genesis.json

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
