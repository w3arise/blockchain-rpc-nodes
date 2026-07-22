#!/usr/bin/env bash
#
# Initialize Cronos mainnet home dir (cronosd init + genesis + config patches).
#
# Skip when restoring a snapshot into $HOME/cronos-data (still apply app.toml
# patches from README / re-run the patch section if configs were wiped).
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
P2P_PORT="${P2P_PORT:-26656}"
SEEDS="${SEEDS:-}"
PRUNING="${PRUNING:-default}"
MINIMUM_GAS_PRICES="${MINIMUM_GAS_PRICES:-1basecro}"
LOGS_CAP="${LOGS_CAP:-100000}"
BLOCK_RANGE_CAP="${BLOCK_RANGE_CAP:-100000}"
GAS_CAP="${GAS_CAP:-600000000}"
DOCKER_UID="$(id -u)"
DOCKER_GID="$(id -g)"

GENESIS_URL="https://raw.githubusercontent.com/crypto-org-chain/cronos-mainnet/master/cronosmainnet_25-1/genesis.json"
GENESIS_SHA256="58f17545056267f57a2d95f4c9c00ac1d689a580e220c5d4de96570fbbc832e1"

CONFIG_TOML="${DATA_DIR}/config/config.toml"
APP_TOML="${DATA_DIR}/config/app.toml"
GENESIS_FILE="${DATA_DIR}/config/genesis.json"

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -E -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

# cronosd init runs in Docker; without --user it creates root-owned files and
# host-side curl/sed cannot write genesis or patch app.toml.
fix_ownership() {
  local dir="$1"
  if [[ -w "${dir}" ]] && { [[ ! -d "${dir}/config" ]] || [[ -w "${dir}/config" ]]; }; then
    return 0
  fi
  echo "==> Fixing ownership on ${dir} -> ${DOCKER_UID}:${DOCKER_GID}"
  docker run --rm -v "${dir}:/d" alpine \
    chown -R "${DOCKER_UID}:${DOCKER_GID}" /d
}

wipe_datadir() {
  local dir="$1"
  if rm -rf "${dir}" 2>/dev/null; then
    return 0
  fi
  echo "==> Removing root-owned ${dir} via Docker"
  docker run --rm -v "$(dirname "${dir}"):/parent" alpine \
    rm -rf "/parent/$(basename "${dir}")"
}

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
    y|Y) wipe_datadir "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"
fix_ownership "${DATA_DIR}"

echo "==> Building cronosd image (if needed)"
docker compose build cronosd

echo "==> Initializing cronosd (${CHAIN_ID}) into ${DATA_DIR}"
# Ensure compose mounts the same host path we patch below
export HOST_DATADIR="${DATA_DIR}"
export DOCKER_UID DOCKER_GID
docker compose run --rm --no-deps \
  --user "${DOCKER_UID}:${DOCKER_GID}" \
  --entrypoint cronosd \
  cronosd init "${MONIKER}" --chain-id "${CHAIN_ID}" --home /data

fix_ownership "${DATA_DIR}"

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

echo "==> Patching config.toml"
sed_inplace "s|^(seeds[[:space:]]+=[[:space:]]+).*\$|\1\"${SEEDS}\"|" "${CONFIG_TOML}"
sed_inplace "s|^(create_empty_blocks_interval[[:space:]]+=[[:space:]]+).*\$|\1\"5s\"|" "${CONFIG_TOML}"
sed_inplace "s|^(timeout_commit[[:space:]]+=[[:space:]]+).*\$|\1\"5s\"|" "${CONFIG_TOML}"

# P2P listen on all interfaces at host/container P2P_PORT (mapped 1:1)
# Match the first laddr under [p2p] by replacing the default 26656 listen line.
sed_inplace "s|^(laddr[[:space:]]+=[[:space:]]+)\"tcp://0\.0\.0\.0:26656\"|\1\"tcp://0.0.0.0:${P2P_PORT}\"|" "${CONFIG_TOML}"
sed_inplace "s|^(laddr[[:space:]]+=[[:space:]]+)\"tcp://127\.0\.0\.1:26656\"|\1\"tcp://0.0.0.0:${P2P_PORT}\"|" "${CONFIG_TOML}"

# Tendermint RPC listen inside container (host maps TM_RPC_PORT -> 26657)
sed_inplace "s|^(laddr[[:space:]]+=[[:space:]]+)\"tcp://127\.0\.0\.1:26657\"|\1\"tcp://0.0.0.0:26657\"|" "${CONFIG_TOML}"

if [[ -n "${EXT_IP:-}" ]]; then
  sed_inplace "s|^(external_address[[:space:]]+=[[:space:]]+).*\$|\1\"${EXT_IP}:${P2P_PORT}\"|" "${CONFIG_TOML}"
fi

echo "==> Patching app.toml (pruning / gas / eth_getLogs caps)"
sed_inplace "s|^(pruning[[:space:]]+=[[:space:]]+).*\$|\1\"${PRUNING}\"|" "${APP_TOML}"
sed_inplace "s|^(minimum-gas-prices[[:space:]]+=[[:space:]]+).*\$|\1\"${MINIMUM_GAS_PRICES}\"|" "${APP_TOML}"
sed_inplace "s|^(logs-cap[[:space:]]+=[[:space:]]+).*\$|\1${LOGS_CAP}|" "${APP_TOML}"
sed_inplace "s|^(block-range-cap[[:space:]]+=[[:space:]]+).*\$|\1${BLOCK_RANGE_CAP}|" "${APP_TOML}"
sed_inplace "s|^(gas-cap[[:space:]]+=[[:space:]]+).*\$|\1${GAS_CAP}|" "${APP_TOML}"

# JSON-RPC bind for Docker port publishing (defaults are usually already 0.0.0.0)
sed_inplace "s|^(address[[:space:]]+=[[:space:]]+)\"127\.0\.0\.1:8545\"|\1\"0.0.0.0:8545\"|" "${APP_TOML}"
sed_inplace "s|^(ws-address[[:space:]]+=[[:space:]]+)\"127\.0\.0\.1:8546\"|\1\"0.0.0.0:8546\"|" "${APP_TOML}"

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "    pruning=${PRUNING} minimum-gas-prices=${MINIMUM_GAS_PRICES}"
echo "    logs-cap=${LOGS_CAP} block-range-cap=${BLOCK_RANGE_CAP} gas-cap=${GAS_CAP}"
echo "Next: docker compose up -d"
echo "Note: peer discovery often takes 1–2 minutes after each restart."
