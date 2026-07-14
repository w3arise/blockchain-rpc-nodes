#!/bin/sh
set -eu

EXTRA_NET_FLAG="--mainnet"
if [ "${NETWORK:-mainnet}" = "testnet" ]; then
  EXTRA_NET_FLAG="--testnet"
fi

exec geth \
  ${EXTRA_NET_FLAG} \
  --config=/config/config.toml \
  --datadir=/data \
  --syncmode="${SYNC_MODE:-snap}" \
  --gcmode="${GCMODE:-full}" \
  --nat="extip:${EXT_IP}" \
  --authrpc.port="${AUTHRPC_PORT:-8445}" \
  --traceaction="${TRACEACTION:-2}" \
  --verbosity="${VERBOSITY:-3}" \
  --bootnodes="${BOOTNODES}" \
  "$@"
