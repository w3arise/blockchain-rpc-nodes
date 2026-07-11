#!/usr/bin/env bash
#
# Prepare config-<network>/ for the X Layer OP Stack (op-geth + op-node)
# without running okx's full interactive one-click-setup.sh.
#
# It creates the config + log dirs, generates the shared Engine API JWT, and
# downloads the two upstream config files that docker-compose.yml mounts:
#   - op-geth-config-<network>.toml  -> /config.toml
#   - rollup-<network>.json          -> /rollup.json
#
# Default assumes you bootstrap op-geth data from a snapshot, so it only fetches
# config and does NOT touch chain data. The chain genesis (huge) + one-time
# `geth init` are only for a from-scratch sync; pass --with-genesis for that.
#
# Usage:
#   ./setup-config.sh                 # mainnet config only (default; snapshot flow)
#   ./setup-config.sh testnet         # testnet config
#   ./setup-config.sh mainnet --with-genesis   # from-scratch: genesis + geth init
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NETWORK="mainnet"
WITH_GENESIS=0
for arg in "$@"; do
  case "$arg" in
    mainnet|testnet) NETWORK="$arg" ;;
    --with-genesis)  WITH_GENESIS=1 ;;
    *) echo "ERROR: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

CONFIG_DIR="config-${NETWORK}"
LOGS_DIR="logs-${NETWORK}"
JWT_FILE="${CONFIG_DIR}/jwt.txt"

# okx/xlayer-toolkit raw config files (same source as one-click-setup.sh)
REPO_URL="https://raw.githubusercontent.com/okx/xlayer-toolkit/main/scripts/rpc-setup"
GETH_CONFIG="op-geth-config-${NETWORK}.toml"
ROLLUP_CONFIG="rollup-${NETWORK}.json"

if [ "${NETWORK}" = "mainnet" ]; then
  GENESIS_URL="https://okg-pub-hk.oss-cn-hongkong.aliyuncs.com/cdn/chain/xlayer/snapshot/merged.genesis.json.mainnet.tar.gz"
  EXPECTED_CHAIN_ID="196"
else
  GENESIS_URL="https://okg-pub-hk.oss-cn-hongkong.aliyuncs.com/cdn/chain/xlayer/snapshot/merged.genesis.json.tar.gz"
  EXPECTED_CHAIN_ID="1952"
fi

for tool in openssl curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is required but not found in PATH." >&2
    exit 1
  fi
done

echo "==> Preparing X Layer ${NETWORK} config in ${SCRIPT_DIR}"
mkdir -p "${CONFIG_DIR}" "${LOGS_DIR}/op-geth" "${LOGS_DIR}/op-node"

# --- JWT (shared Engine API secret; 64 hex chars, no trailing newline) --------
if [ -s "${JWT_FILE}" ] && [ "$(tr -d '\n\r ' < "${JWT_FILE}" | wc -c)" -eq 64 ]; then
  echo "==> Reusing existing JWT at ${JWT_FILE}"
else
  echo "==> Generating Engine API JWT at ${JWT_FILE}"
  openssl rand -hex 32 | tr -d '\n' > "${JWT_FILE}"
  chmod 600 "${JWT_FILE}"
fi

# --- Upstream config files ----------------------------------------------------
download() {
  local name="$1"
  echo "==> Downloading ${name}"
  if ! curl -fsSL "${REPO_URL}/config/${name}" -o "${CONFIG_DIR}/${name}"; then
    echo "ERROR: failed to download ${name} from ${REPO_URL}/config/${name}" >&2
    exit 1
  fi
}
download "${GETH_CONFIG}"
download "${ROLLUP_CONFIG}"

echo "==> Config ready:"
echo "    ${CONFIG_DIR}/jwt.txt"
echo "    ${CONFIG_DIR}/${GETH_CONFIG}"
echo "    ${CONFIG_DIR}/${ROLLUP_CONFIG}"

# --- Optional: genesis download + one-time geth init --------------------------
if [ "${WITH_GENESIS}" -eq 1 ]; then
  [ -f .env ] && set -a && . ./.env && set +a
  if [ -z "${OP_GETH_IMAGE_TAG:-}" ]; then
    echo "ERROR: OP_GETH_IMAGE_TAG is not set (copy env.template to .env first)." >&2
    exit 1
  fi

  DATA_DIR="${HOME}/data-mainnet"   # matches op-geth volume in docker-compose.yml
  GENESIS_FILE="${CONFIG_DIR}/genesis-${NETWORK}.json"

  echo "==> Downloading genesis (large) from ${GENESIS_URL}"
  curl -fL "${GENESIS_URL}" -o genesis.tar.gz
  tar -xzf genesis.tar.gz -C "${CONFIG_DIR}/"
  rm -f genesis.tar.gz
  if [ -f "${CONFIG_DIR}/merged.genesis.json" ]; then
    mv "${CONFIG_DIR}/merged.genesis.json" "${GENESIS_FILE}"
  elif [ -f "${CONFIG_DIR}/genesis.json" ]; then
    mv "${CONFIG_DIR}/genesis.json" "${GENESIS_FILE}"
  fi
  [ -f "${GENESIS_FILE}" ] || { echo "ERROR: genesis.json not found in archive" >&2; exit 1; }

  if command -v jq >/dev/null 2>&1; then
    CID="$(jq -r '.config.chainId // .chainId' "${GENESIS_FILE}" 2>/dev/null || echo "")"
    if [ -n "${CID}" ] && [ "${CID}" != "${EXPECTED_CHAIN_ID}" ]; then
      echo "ERROR: genesis chainId ${CID} != expected ${EXPECTED_CHAIN_ID}" >&2
      exit 1
    fi
  fi

  echo "==> Initializing op-geth (archive) — this can take a while"
  docker run --rm \
    -v "${DATA_DIR}:/data" \
    -v "${SCRIPT_DIR}/${GENESIS_FILE}:/genesis.json" \
    "${OP_GETH_IMAGE_TAG}" \
    --datadir /data --gcmode=archive --db.engine=pebble --log.format json \
    init --state.scheme=hash /genesis.json
  echo "==> op-geth initialized at ${DATA_DIR}"
fi

echo ""
echo "Done. Next:"
echo "  1. cp env.template .env  &&  edit L1_RPC_URL / L1_BEACON_URL"
if [ "${WITH_GENESIS}" -ne 1 ]; then
  echo "  2. Restore op-geth data from your snapshot into \$HOME/data-mainnet"
  echo "     (from-scratch instead? ./setup-config.sh ${NETWORK} --with-genesis)"
  echo "  3. docker compose up -d"
else
  echo "  2. docker compose up -d"
fi
