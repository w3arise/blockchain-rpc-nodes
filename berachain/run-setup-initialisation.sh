#!/usr/bin/env bash
#
# Patch beacond config after init (or IP change): P2P external address,
# Engine API dial URL, and KZG path for docker-compose networking.
#
# Usage: ./run-setup-initialisation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
BEACOND_HOME="${BEACOND_HOME:-$HOME/berachain-beacond-data}"
RETH_DATA="${RETH_DATA:-$HOME/berachain-reth-data}"
CONFIG_TOML="${BEACOND_HOME}/config/config.toml"
APP_TOML="${BEACOND_HOME}/config/app.toml"
KZG_PATH="${KZG_PATH:-/root/.beacond/config/kzg-trusted-setup.json}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

BEACON_P2P_PORT="${BEACON_P2P_PORT:-20656}"
EXT_IP="${EXT_IP:-$(curl -s ifconfig.me --ipv4)}"
ENGINE_RPC_URL="${ENGINE_RPC_URL:-http://berachain-mainnet-reth:8551}"
JWT_PATH="${JWT_PATH:-/config/jwt.hex}"
FEE_RECIPIENT="${FEE_RECIPIENT:-0x0000000000000000000000000000000000000000}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${SCRIPT_DIR}/env.template" "${ENV_FILE}"
fi

if [[ "${NONINTERACTIVE}" != "1" ]]; then
  if [[ -f "${BEACOND_HOME}/config/node_key.json" ]]; then
    read -r -p "Delete ${BEACOND_HOME}/config/node_key.json? (y/n) " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
      rm -f "${BEACOND_HOME}/config/node_key.json"
    fi
  fi

  if [[ -f "${RETH_DATA}/discovery-secret" ]]; then
    read -r -p "Delete ${RETH_DATA}/discovery-secret? (y/n) " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
      rm -f "${RETH_DATA}/discovery-secret"
    fi
  fi
fi

mkdir -p "${BEACOND_HOME}/data"
echo '{}' > "${BEACOND_HOME}/data/priv_validator_state.json"

if [[ ! -f "${CONFIG_TOML}" ]]; then
  echo "ERROR: ${CONFIG_TOML} not found. Run ./init-database.sh first." >&2
  exit 1
fi

if [[ ! -f "${APP_TOML}" ]]; then
  echo "ERROR: ${APP_TOML} not found. Run ./init-database.sh first." >&2
  exit 1
fi

CFG_BAK="$(mktemp)"
ENV_BAK="$(mktemp)"
APP_BAK="$(mktemp)"

cp "${CONFIG_TOML}" "${CFG_BAK}"
cp "${ENV_FILE}" "${ENV_BAK}"
cp "${APP_TOML}" "${APP_BAK}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' -e "s|laddr = \"tcp://.*26656\"|laddr = \"tcp://0.0.0.0:${BEACON_P2P_PORT}\"|" \
            -e "s|external_address = .*\"|external_address = \"tcp://${EXT_IP}:${BEACON_P2P_PORT}\"|" \
            "${CONFIG_TOML}"
  sed -i '' -E "s|^EXT_IP=.*|EXT_IP=${EXT_IP}|" "${ENV_FILE}"
  sed -i '' -e "s|^rpc-dial-url = \".*\"|rpc-dial-url = \"${ENGINE_RPC_URL}\"|" \
            -e "s|^jwt-secret-path = \".*\"|jwt-secret-path = \"${JWT_PATH}\"|" \
            -e "s|^trusted-setup-path = \".*\"|trusted-setup-path = \"${KZG_PATH}\"|" \
            -e "s|^suggested-fee-recipient = \".*\"|suggested-fee-recipient = \"${FEE_RECIPIENT}\"|" \
            "${APP_TOML}"
else
  sed -i -e "s|laddr = \"tcp://.*26656\"|laddr = \"tcp://0.0.0.0:${BEACON_P2P_PORT}\"|" \
         -e "s|external_address = .*\"|external_address = \"tcp://${EXT_IP}:${BEACON_P2P_PORT}\"|" \
         "${CONFIG_TOML}"
  sed -i -E "s|^EXT_IP=.*|EXT_IP=${EXT_IP}|" "${ENV_FILE}"
  sed -i -e "s|^rpc-dial-url = \".*\"|rpc-dial-url = \"${ENGINE_RPC_URL}\"|" \
         -e "s|^jwt-secret-path = \".*\"|jwt-secret-path = \"${JWT_PATH}\"|" \
         -e "s|^trusted-setup-path = \".*\"|trusted-setup-path = \"${KZG_PATH}\"|" \
         -e "s|^suggested-fee-recipient = \".*\"|suggested-fee-recipient = \"${FEE_RECIPIENT}\"|" \
         "${APP_TOML}"
fi

echo "=== config.toml ==="
diff -u "${CFG_BAK}" "${CONFIG_TOML}" || true
echo "=== app.toml ==="
diff -u "${APP_BAK}" "${APP_TOML}" || true
echo "=== .env ==="
diff -u "${ENV_BAK}" "${ENV_FILE}" || true

rm -f "${CFG_BAK}" "${ENV_BAK}" "${APP_BAK}"
