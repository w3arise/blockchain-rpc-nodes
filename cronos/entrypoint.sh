#!/bin/sh
set -eu

HOME_DIR="${CRONOSD_HOME:-/data}"
CONFIG_TOML="${HOME_DIR}/config/config.toml"

if [ ! -f "${CONFIG_TOML}" ]; then
  echo "ERROR: missing ${CONFIG_TOML} — run ./init-database.sh first" >&2
  exit 1
fi

# Advertise public P2P address (CometBFT)
if [ -n "${EXT_IP:-}" ]; then
  P2P_PORT="${P2P_PORT:-26656}"
  sed -i -E "s|^(external_address[[:space:]]+=[[:space:]]+).*\$|\1\"${EXT_IP}:${P2P_PORT}\"|" "${CONFIG_TOML}"
fi

exec cronosd start --home "${HOME_DIR}"
