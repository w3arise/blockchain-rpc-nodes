#!/usr/bin/env bash
#
# Configure Abstract deployment: create .env from env.template if missing.
#
# Usage: ./configure.sh [mainnet|testnet]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NETWORK="${1:-mainnet}"
ENV_FILE="${SCRIPT_DIR}/.env"

case "${NETWORK}" in
  mainnet)
    ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
    ;;
  testnet)
    ENV_TEMPLATE="${SCRIPT_DIR}/env.testnet.template"
    ;;
  *)
    echo "ERROR: network must be mainnet or testnet" >&2
    exit 1
    ;;
esac

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from $(basename "${ENV_TEMPLATE}")"
else
  echo ".env already exists — not overwriting"
fi

echo ""
echo "Next:"
echo "  edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD"
echo "  docker compose up -d"
echo ""
echo "RPC: http://127.0.0.1:\${EN_HTTP_PORT:-3060}  WS: ws://127.0.0.1:\${EN_WS_PORT:-3061}"
echo "Grafana: http://127.0.0.1:8300"
