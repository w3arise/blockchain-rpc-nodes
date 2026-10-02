#!/usr/bin/env bash
#
# Initialize Mova mainnet home dir.
# movad init writes config.toml and app.toml. Do not replace those files.
#
# Sync from genesis. Do not restore a snapshot over this datadir.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/mova-data}"
CHAIN_ID="${CHAIN_ID:-61901}"
MONIKER="${MONIKER:-mova-rpc}"

GENESIS_URL="https://raw.githubusercontent.com/CryptoManufaktur-io/mova-docker/main/mainnet-config/config/genesis.json"
GENESIS_SHA256="e4d747ac592c4c5e959df1e9fac40fe8ac94540b0660e5f710f3c566e0725c9c"

CONFIG_TOML="${DATA_DIR}/config/config.toml"
GENESIS_FILE="${DATA_DIR}/config/genesis.json"

for tool in docker curl; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

if [[ -f "${CONFIG_TOML}" ]]; then
  echo "WARNING: ${DATA_DIR} already contains movad config."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"

echo "==> Initializing movad (${CHAIN_ID}) into ${DATA_DIR}"
echo "    image movachain/movan-syncnode:${MOVA_VERSION:-v0.0.1} (genesis binary, linux/amd64)"
echo "    config.toml and app.toml are left as movad init writes them"
export HOST_DATADIR="${DATA_DIR}"
docker compose run --rm --no-deps \
  --entrypoint movad \
  movad init "${MONIKER}" --chain-id "${CHAIN_ID}" --home /data

# movad init does not write noderpc.toml. The gas and log caps are patched there.
if [[ ! -f "${DATA_DIR}/config/noderpc.toml" ]]; then
  cp "${SCRIPT_DIR}/config/noderpc.toml" "${DATA_DIR}/config/noderpc.toml"
fi
mkdir -p "${DATA_DIR}/clicfg"

echo "==> Replacing init genesis with chain ${CHAIN_ID} (operator copy, checksum-checked)"
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
if ! grep -q "\"chain_id\": \"${CHAIN_ID}\"" "${GENESIS_FILE}"; then
  echo "ERROR: genesis chain_id is not ${CHAIN_ID}" >&2
  exit 1
fi
echo "genesis checksum OK (chain_id ${CHAIN_ID})"

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: ./patch-config.sh"
echo "      docker compose up -d"
