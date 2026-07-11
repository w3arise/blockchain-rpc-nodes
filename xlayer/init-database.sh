#!/usr/bin/env bash
#
# Initialize the op-geth chain database from genesis (FROM-SCRATCH only).
#
# You do NOT need this when bootstrapping from a snapshot. For the snapshot
# flow just run:
#   ./create-jwt.sh
#   restore the snapshot into $HOME/xlayer-op-geth-data
#   docker compose up -d
#
# Use this script only to build the op-geth datadir from scratch: it downloads
# the (large) genesis and runs a one-time `geth init`. Config files (rollup +
# op-geth toml) are already committed under config/.
#
# Usage:
#   ./init-database.sh            # mainnet (default)
#   ./init-database.sh testnet    # testnet
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NETWORK="${1:-mainnet}"
case "${NETWORK}" in
  mainnet)
    GENESIS_URL="https://okg-pub-hk.oss-cn-hongkong.aliyuncs.com/cdn/chain/xlayer/snapshot/merged.genesis.json.mainnet.tar.gz"
    EXPECTED_CHAIN_ID="196"
    DATA_DIR="${HOME}/xlayer-op-geth-data"
    ;;
  testnet)
    GENESIS_URL="https://okg-pub-hk.oss-cn-hongkong.aliyuncs.com/cdn/chain/xlayer/snapshot/merged.genesis.json.tar.gz"
    EXPECTED_CHAIN_ID="1952"
    DATA_DIR="${HOME}/xlayer-op-geth-data-testnet"
    ;;
  *) echo "ERROR: unknown network: ${NETWORK} (use mainnet|testnet)" >&2; exit 1 ;;
esac

for tool in curl tar docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: '$tool' is required." >&2; exit 1; }
done

# op-geth image tag comes from .env
[ -f .env ] && { set -a; . ./.env; set +a; }
if [ -z "${OP_GETH_IMAGE_TAG:-}" ]; then
  echo "ERROR: OP_GETH_IMAGE_TAG is not set (cp env.template .env first)." >&2
  exit 1
fi

if [ -d "${DATA_DIR}/geth" ]; then
  echo "WARNING: ${DATA_DIR} already contains a geth database."
  read -r -p "Wipe and re-initialize? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}"; echo "Removed ${DATA_DIR}" ;;
    *)   echo "Aborted."; exit 0 ;;
  esac
fi
mkdir -p "${DATA_DIR}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> Downloading genesis (large) from ${GENESIS_URL}"
curl -fL "${GENESIS_URL}" -o "${TMP}/genesis.tar.gz"
tar -xzf "${TMP}/genesis.tar.gz" -C "${TMP}"

if   [ -f "${TMP}/merged.genesis.json" ]; then GENESIS_FILE="${TMP}/merged.genesis.json"
elif [ -f "${TMP}/genesis.json" ];        then GENESIS_FILE="${TMP}/genesis.json"
else echo "ERROR: genesis.json not found in archive" >&2; exit 1
fi

if command -v jq >/dev/null 2>&1; then
  CID="$(jq -r '.config.chainId // .chainId' "${GENESIS_FILE}" 2>/dev/null || echo "")"
  if [ -n "${CID}" ] && [ "${CID}" != "${EXPECTED_CHAIN_ID}" ]; then
    echo "ERROR: genesis chainId ${CID} != expected ${EXPECTED_CHAIN_ID}" >&2
    exit 1
  fi
fi

echo "==> Initializing op-geth (archive) into ${DATA_DIR} — this can take a while"
docker run --rm \
  -v "${DATA_DIR}:/data" \
  -v "${GENESIS_FILE}:/genesis.json" \
  "${OP_GETH_IMAGE_TAG}" \
  --datadir /data --gcmode=archive --db.engine=pebble --log.format json \
  init --state.scheme=hash /genesis.json

echo ""
echo "==> Database initialized at ${DATA_DIR}"
echo "Next:  ./create-jwt.sh (if not done)  &&  docker compose up -d"
