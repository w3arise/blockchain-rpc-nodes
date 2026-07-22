#!/usr/bin/env bash
#
# Initialize Cronos mainnet home dir (cronosd init + genesis download).
#
# Skip when restoring a snapshot into $HOME/cronos-data; run ./patch-config.sh
# if config files need updating after restore.
#
# Usage: ./init-database.sh
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

DATA_DIR="${HOST_DATADIR:-${HOME}/cronos-data}"
CHAIN_ID="${CHAIN_ID:-cronosmainnet_25-1}"
MONIKER="${MONIKER:-cronos-rpc}"

GENESIS_URL="https://raw.githubusercontent.com/crypto-org-chain/cronos-mainnet/master/cronosmainnet_25-1/genesis.json"
GENESIS_SHA256="58f17545056267f57a2d95f4c9c00ac1d689a580e220c5d4de96570fbbc832e1"

CONFIG_TOML="${DATA_DIR}/config/config.toml"
GENESIS_FILE="${DATA_DIR}/config/genesis.json"

for tool in docker curl; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

if [[ -f "${CONFIG_TOML}" ]]; then
  echo "WARNING: ${DATA_DIR} already contains cronosd config."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"

echo "==> Building cronosd image (if needed)"
docker compose build cronosd

echo "==> Initializing cronosd (${CHAIN_ID}) into ${DATA_DIR}"
export HOST_DATADIR="${DATA_DIR}"
docker compose run --rm --no-deps \
  --entrypoint cronosd \
  cronosd init "${MONIKER}" --chain-id "${CHAIN_ID}" --home /data

echo "==> Downloading mainnet genesis"
curl -fsSL "${GENESIS_URL}" -o "${GENESIS_FILE}"
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "${GENESIS_FILE}" | awk '{print $1}')"
else
  ACTUAL_SHA="$(shasum -a 256 "${GENESIS_FILE}" | awk '{print $1}')"
fi
if [[ "${ACTUAL_SHA}" != "${GENESIS_SHA256}" ]]; then
  echo "ERROR: genesis sha256 mismatch (got ${ACTUAL_SHA}, expected ${GENESIS_SHA256})" >&2
  exit 1
fi
echo "genesis checksum OK"

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: ./patch-config.sh"
echo "      docker compose up -d"
