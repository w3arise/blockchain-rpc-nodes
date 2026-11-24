#!/bin/sh

RETH_BIN=${RETH_BINARY:-morph-reth}
RETH_DATADIR=${RETH_DATADIR:-/db}
JWT_PATH=${JWT_SECRET_PATH:-/config/jwt.hex}
RETH_CHAIN=${RETH_CHAIN:-mainnet}
GAS_CAP=${GAS_CAP:-600000000}
LOG_DIR=${LOG_DIR:-${RETH_DATADIR}/logs}
# JSON array of enode URLs; passed to --trusted-peers (discovery is disabled).
STATIC_NODES_FILE=${STATIC_NODES_FILE:-${RETH_DATADIR}/static-nodes.json}

if [ ! -f "${JWT_PATH}" ]; then
  echo "Error: JWT secret not found at ${JWT_PATH}."
  echo "Run ./create-jwt.sh before starting the node."
  exit 1
fi

mkdir -p "${LOG_DIR}"

# No jq in the image: keep only the enode URLs, join them with commas.
TRUSTED_PEERS=""
if [ -f "${STATIC_NODES_FILE}" ]; then
  TRUSTED_PEERS=$(grep -o 'enode://[^"]*' "${STATIC_NODES_FILE}" | paste -sd, -)
fi

# Archive mode on purpose: no --full / --prune.* (see AGENTS.md, Reth state pruning).
set -- "${RETH_BIN}" node \
  --chain "${RETH_CHAIN}" \
  --datadir "${RETH_DATADIR}" \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.corsdomain '*' \
  --http.api web3,eth,txpool,net,morph \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port 8546 \
  --ws.origins '*' \
  --ws.api web3,eth,txpool,net,morph \
  --authrpc.addr 0.0.0.0 \
  --authrpc.port 8551 \
  --authrpc.jwtsecret "${JWT_PATH}" \
  --rpc.gascap "${GAS_CAP}" \
  --disable-discovery \
  --metrics 0.0.0.0:6060 \
  --log.file.directory "${LOG_DIR}" \
  --log.file.filter info

if [ -n "${TRUSTED_PEERS}" ]; then
  set -- "$@" --trusted-peers "${TRUSTED_PEERS}"
else
  echo "Warning: no trusted peers found in ${STATIC_NODES_FILE}; run ./init-database.sh"
fi

if [ -n "${RETH_P2P_PORT:-}" ]; then
  set -- "$@" --port "${RETH_P2P_PORT}"
fi

if [ -n "${EXT_IP:-}" ]; then
  set -- "$@" --nat "extip:${EXT_IP}"
else
  set -- "$@" --nat none
fi

exec "$@"
