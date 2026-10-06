#!/usr/bin/env bash
#
# Initialize Heimdall home (heimdalld init), then replace the local genesis
# with the public chain file (sha512 + chain_id).
#
# Usage: ./init-database.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh <mainnet|amoy> first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

CHAIN="${CHAIN:-}"
CHAIN_ID="${CHAIN_ID:-}"
MONIKER="${MONIKER:-heimdall-sentry}"
DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-heimdall-data}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/polygon-heimdall-snapshot-tmp}"
CONFIG_TOML="${DATA_DIR}/config/config.toml"
GENESIS_FILE="${DATA_DIR}/config/genesis.json"

case "${CHAIN}" in
  mainnet)
    GENESIS_URL="https://storage.googleapis.com/mainnet-heimdallv2-genesis/migrated_dump-genesis.json"
    # Official sidecar migrated_dump-genesis.json.sha512
    GENESIS_SHA512="38003386814a1cf6194f7e29e9b27d6e8711760cef357c500b94dda3e366899b6577a912e97a0527c96bc17174b186d269697cae3e8525022074bc83e36b4ed3"
    EXPECT_CHAIN_ID="heimdallv2-137"
    ;;
  amoy)
    GENESIS_URL="https://storage.googleapis.com/amoy-heimdallv2-genesis/migrated_dump-genesis.json"
    GENESIS_SHA512="70bb9b754781f0ec77ace3132079420b26da602b606e514b71c969d29ab9a0c4ec757d44b5597d2889342708fdbfb48d9029caddd48ef1584d484977a17bd24d"
    EXPECT_CHAIN_ID="heimdallv2-80002"
    ;;
  *)
    echo "ERROR: CHAIN must be mainnet or amoy (got: ${CHAIN:-empty})" >&2
    exit 1
    ;;
esac

if [[ "${CHAIN_ID}" != "${EXPECT_CHAIN_ID}" ]]; then
  echo "ERROR: CHAIN_ID=${CHAIN_ID} does not match ${CHAIN} (${EXPECT_CHAIN_ID})" >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required." >&2
  exit 1
}

sha512_of() {
  local file="$1"
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "${file}" | awk '{print $1}'
  else
    shasum -a 512 "${file}" | awk '{print $1}'
  fi
}

chain_id_of() {
  local file="$1"
  tail -c 65536 "${file}" | grep -o '"chain_id":"[^"]*"' | tail -1 | sed -E 's/.*"chain_id":"([^"]+)".*/\1/'
}

download() {
  local url="$1"
  local out="$2"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c --max-tries=0 -x 16 -s 16 -k 100M -c \
      --dir="$(dirname "${out}")" \
      --out="$(basename "${out}")" \
      "${url}"
  else
    echo "aria2c not found; falling back to curl (install aria2 for faster downloads)" >&2
    command -v curl >/dev/null 2>&1 || {
      echo "ERROR: neither aria2c nor curl is available." >&2
      exit 1
    }
    curl -fL --retry 5 -C - -o "${out}" "${url}"
  fi
}

alert_kept() {
  local path="$1"
  echo "WARNING: downloaded genesis is left on disk. This script does not delete it." >&2
  echo "         path: ${path}" >&2
  if [[ -e "${path}" ]]; then
    echo "         size: $(du -sh "${path}" | awk '{print $1}')" >&2
  fi
  echo "         Remove it yourself when you no longer need the file." >&2
}

if [[ -f "${CONFIG_TOML}" ]]; then
  echo "WARNING: ${DATA_DIR} already contains heimdall config."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}" "${TMP_BASE}"

echo "==> Pulling heimdall image"
docker compose pull heimdalld

echo "==> Initializing heimdalld (${CHAIN_ID}) into ${DATA_DIR}"
export HOST_DATADIR="${DATA_DIR}"
docker compose run --rm --no-deps --entrypoint heimdalld \
  heimdalld init "${MONIKER}" --chain-id "${CHAIN_ID}" --home=/data

STAGED="${TMP_BASE}/$(basename "${GENESIS_URL}")"
NEED_DOWNLOAD=1
if [[ -e "${STAGED}" ]]; then
  echo "WARNING: existing genesis download found; checking sha512 before reuse." >&2
  alert_kept "${STAGED}"
  if [[ "$(sha512_of "${STAGED}")" == "${GENESIS_SHA512}" ]]; then
    NEED_DOWNLOAD=0
    echo "reusing verified genesis ${STAGED}"
  fi
fi
if [[ "${NEED_DOWNLOAD}" -eq 1 ]]; then
  echo "==> Downloading ${CHAIN} genesis (multi-GB on mainnet)"
  echo "    ${GENESIS_URL}"
  download "${GENESIS_URL}" "${STAGED}"
  alert_kept "${STAGED}"
fi

ACTUAL_SHA="$(sha512_of "${STAGED}")"
if [[ "${ACTUAL_SHA}" != "${GENESIS_SHA512}" ]]; then
  echo "ERROR: genesis sha512 mismatch" >&2
  echo "       got      ${ACTUAL_SHA}" >&2
  echo "       expected ${GENESIS_SHA512}" >&2
  echo "       staged: ${STAGED}" >&2
  echo "       If that file is already complete, delete it and re-run." >&2
  echo "       ${GENESIS_FILE} is still the local init file. Do not start the node." >&2
  exit 1
fi

ACTUAL_CHAIN_ID="$(chain_id_of "${STAGED}")"
if [[ "${ACTUAL_CHAIN_ID}" != "${EXPECT_CHAIN_ID}" ]]; then
  echo "ERROR: genesis chain_id is ${ACTUAL_CHAIN_ID:-empty}, expected ${EXPECT_CHAIN_ID}" >&2
  echo "       ${GENESIS_FILE} is still the local init file. Do not start the node." >&2
  exit 1
fi

cp -f "${STAGED}" "${GENESIS_FILE}"
chmod 644 "${GENESIS_FILE}"
echo "genesis checksum OK (chain_id ${ACTUAL_CHAIN_ID})"

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: ./restore-snapshot.sh"
echo "      ./patch-config.sh"
echo "      docker compose up -d"
