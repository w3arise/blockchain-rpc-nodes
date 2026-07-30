#!/usr/bin/env bash
#
# Initialize Sei mainnet home dir (seid init — genesis auto-written for pacific-1).
#
# After ./restore-snapshot.sh (preferred — Polkachu), run ./patch-config.sh before first start.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/sei-data}"
CHAIN_ID="${CHAIN_ID:-pacific-1}"
MONIKER="${MONIKER:-sei-rpc}"

CONFIG_TOML="${DATA_DIR}/config/config.toml"

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required." >&2
  exit 1
}

if [[ -f "${CONFIG_TOML}" ]]; then
  echo "WARNING: ${DATA_DIR} already contains seid config."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"

echo "==> Pulling seid image (if needed)"
docker compose pull seid

echo "==> Initializing seid (${CHAIN_ID}) into ${DATA_DIR}"
export HOST_DATADIR="${DATA_DIR}"
docker compose run --rm --no-deps \
  --entrypoint seid \
  seid init "${MONIKER}" --chain-id "${CHAIN_ID}" --home /data

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: ./restore-snapshot.sh   # preferred — latest Polkachu snapshot"
echo "      ./patch-config.sh"
echo "      docker compose up -d"
