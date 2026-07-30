#!/bin/sh
set -eu

HOME_DIR="${TACCHAIND_HOME:-/data}"
CONFIG_TOML="${HOME_DIR}/config/config.toml"
CHAIN_ID="${CHAIN_ID:-tacchain_239-1}"

if [ ! -f "${CONFIG_TOML}" ]; then
  echo "ERROR: missing ${CONFIG_TOML} — run ./init-database.sh first" >&2
  exit 1
fi

# Advertise public P2P address (CometBFT)
if [ -n "${EXT_IP:-}" ]; then
  P2P_PORT="${P2P_PORT:-26656}"
  sed -i -E "s|^(external_address[[:space:]]+=[[:space:]]+).*\$|\1\"${EXT_IP}:${P2P_PORT}\"|" "${CONFIG_TOML}"
fi

exec tacchaind start \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --json-rpc.enable
