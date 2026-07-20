#!/usr/bin/env bash
#
# Configure Morph deployment: create .env from env.template and set public IP.
#
# Usage:
#   ./configure.sh            # mainnet (default)
#   ./configure.sh hoodi      # Hoodi testnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NETWORK="${1:-mainnet}"
case "${NETWORK}" in
  mainnet)
    ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
    ;;
  hoodi)
    ENV_TEMPLATE="${SCRIPT_DIR}/env.hoodi.template"
    ;;
  *)
    echo "ERROR: unknown network: ${NETWORK} (use mainnet|hoodi)" >&2
    exit 1
    ;;
esac

ENV_FILE="${SCRIPT_DIR}/.env"

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from $(basename "${ENV_TEMPLATE}")"
fi

PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

echo ""
echo "Next:"
echo "  edit .env — set L1_ETH_RPC"
echo "  ./init-database.sh ${NETWORK}"
echo "  ./create-jwt.sh"
echo "  docker compose up -d"
