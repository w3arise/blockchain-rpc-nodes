#!/bin/sh
# Thin entrypoint: snapshot bootstrap (optional) + celo-reth node.
# Adapted from celo-org/celo-l2-node-docker-compose scripts/start-op-reth.sh
set -e

DATADIR=/data
CHAIN="${OP_RETH_CHAIN:-celo}"
NODE_TYPE="${NODE_TYPE:-full}"
RETH_PORT="${RETH_PORT:-10401}"
EXTENDED_ARG="${EXTENDED_ARG:-}"

if [ ! -s /config/jwt.hex ]; then
  echo "ERROR: missing /config/jwt.hex — run ./create-jwt.sh on the host first."
  exit 1
fi

# Refuse op-geth datadirs (MDBX vs geth format).
if [ -d "$DATADIR/geth" ]; then
  echo "ERROR: $DATADIR contains op-geth data; op-reth cannot use it."
  echo "Point the bind mount at an empty directory (or restore a celo-reth snapshot)."
  exit 1
fi

# Bootstrap from snapshots.celo.org when the datadir is empty.
if [ "${OP_RETH_SNAPSHOT:-true}" = "true" ] && [ ! -d "$DATADIR/db" ]; then
  SNAPSHOT_PRESET="--${NODE_TYPE}"
  echo "No data in $DATADIR; downloading ${SNAPSHOT_PRESET} snapshot for ${CHAIN}..."
  celo-reth download --datadir="$DATADIR" --chain="$CHAIN" "$SNAPSHOT_PRESET"
fi

if [ -n "${OP_RETH_HISTORICAL_RPC:-}" ]; then
  EXTENDED_ARG="${EXTENDED_ARG} --rollup.historicalrpc=${OP_RETH_HISTORICAL_RPC}"
fi

if [ -n "${OP_RETH_TRUSTED_PEERS:-}" ]; then
  EXTENDED_ARG="${EXTENDED_ARG} --trusted-peers=${OP_RETH_TRUSTED_PEERS}"
fi

# --minimal / --full prune profiles; archive keeps all history (no flag).
if [ "$NODE_TYPE" != "archive" ]; then
  EXTENDED_ARG="${EXTENDED_ARG} --${NODE_TYPE}"
fi

exec celo-reth node \
  --chain="$CHAIN" \
  --datadir="$DATADIR" \
  --storage.v2=true \
  --http \
  --http.corsdomain="*" \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=web3,debug,eth,txpool,net \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.origins="*" \
  --ws.api=debug,eth,txpool,net,web3 \
  --metrics=0.0.0.0:9001 \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/config/jwt.hex \
  --rollup.sequencer="${OP_RETH_SEQUENCER_URL}" \
  --rollup.disable-tx-pool-gossip \
  --bootnodes="${OP_RETH_BOOTNODES}" \
  --port="${RETH_PORT}" \
  --discovery.port="${RETH_PORT}" \
  --discovery.v5.port="${RETH_PORT}" \
  --max-peers=100 \
  --nat="extip:${EXT_IP}" \
  --txpool.nolocals \
  --rpc.txfeecap="${TX_FEE_CAP:-0}" \
  --rpc.gascap="${GAS_CAP:-600000000}" \
  $EXTENDED_ARG
