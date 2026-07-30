#!/usr/bin/env bash
# RPC-only XDPoSChain start (no mining / unlock). Used as container entrypoint.
set -euo pipefail

DATADIR="${DATADIR:-/data}"
GENESIS="${GENESIS:-/config/genesis.json}"
BOOTNODES_FILE="${BOOTNODES_FILE:-/config/bootnodes.list}"
# Official image ships network-specific binaries; entry.sh normally symlinks XDC.
XDC_BIN="${XDC_BIN:-/usr/bin/XDC-mainnet}"

NETWORK_ID="${NETWORK_ID:-50}"
SYNC_MODE="${SYNC_MODE:-full}"
GC_MODE="${GC_MODE:-full}"
STORE_REWARD="${STORE_REWARD:-false}"
P2P_PORT="${P2P_PORT:-30101}"
HTTP_PORT="${HTTP_PORT:-8989}"
WS_PORT="${WS_PORT:-8888}"
HTTP_API="${HTTP_API:-eth,net,web3,txpool,XDPoS}"
WS_API="${WS_API:-eth,net,web3,txpool,XDPoS}"
ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-*}"
RPC_VHOSTS="${RPC_VHOSTS:-*}"
GAS_CAP="${GAS_CAP:-600000000}"
MAX_PEERS="${MAX_PEERS:-50}"
VERBOSITY="${VERBOSITY:-3}"
ENABLE_0X_PREFIX="${ENABLE_0X_PREFIX:-true}"
EXT_IP="${EXT_IP:-}"

if [[ ! -d "${DATADIR}/XDC/chaindata" ]]; then
  echo "ERROR: missing ${DATADIR}/XDC/chaindata — run ./init-database.sh or ./restore-snapshot.sh first" >&2
  exit 1
fi

bootnodes=""
if [[ -f "${BOOTNODES_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    if [[ -z "${bootnodes}" ]]; then
      bootnodes="${line}"
    else
      bootnodes="${bootnodes},${line}"
    fi
  done <"${BOOTNODES_FILE}"
fi

args=(
  --datadir "${DATADIR}"
  --networkid "${NETWORK_ID}"
  --syncmode "${SYNC_MODE}"
  --gcmode "${GC_MODE}"
  --port "${P2P_PORT}"
  --maxpeers "${MAX_PEERS}"
  --verbosity "${VERBOSITY}"
  --http
  --http-addr "0.0.0.0"
  --http-port "${HTTP_PORT}"
  --http-api "${HTTP_API}"
  --http-corsdomain "${ALLOWED_ORIGINS}"
  --http-vhosts "${RPC_VHOSTS}"
  --ws
  --ws-addr "0.0.0.0"
  --ws-port "${WS_PORT}"
  --ws-api "${WS_API}"
  --ws-origins "${ALLOWED_ORIGINS}"
  --rpc-gascap "${GAS_CAP}"
)

if [[ -n "${bootnodes}" ]]; then
  args+=(--bootnodes "${bootnodes}")
fi

if [[ -n "${EXT_IP}" ]]; then
  args+=(--nat "extip:${EXT_IP}")
fi

if [[ "${STORE_REWARD}" == "true" ]]; then
  args+=(--store-reward)
fi

if [[ "${ENABLE_0X_PREFIX}" == "true" ]]; then
  args+=(--enable-0x-prefix)
fi

# genesis path kept for tooling; init is done by init-database.sh
: "${GENESIS}"

if [[ ! -x "${XDC_BIN}" ]]; then
  echo "ERROR: XDC binary not found at ${XDC_BIN}" >&2
  exit 1
fi

echo "Starting XDC RPC node (sync=${SYNC_MODE} gc=${GC_MODE} networkid=${NETWORK_ID})"
exec "${XDC_BIN}" "${args[@]}"
