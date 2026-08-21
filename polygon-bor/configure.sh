#!/usr/bin/env bash
#
# Configure Polygon Bor: copy env.template.<network> to .env and set EXT_IP.
#
# Usage: ./configure.sh <mainnet|amoy>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"

usage() {
  echo "Usage: $0 <mainnet|amoy>" >&2
  exit 1
}

NETWORK="${1:-}"
case "${NETWORK}" in
  mainnet|amoy) ;;
  *) usage ;;
esac

ENV_TEMPLATE="${SCRIPT_DIR}/env.template.${NETWORK}"

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

cp "${ENV_TEMPLATE}" "${ENV_FILE}"
echo "copied $(basename "${ENV_TEMPLATE}") -> .env"

PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
echo "set EXT_IP=${PUBLIC_IP} in .env"

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-bor-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "chain=${CHAIN}  container=${CONTAINER_NAME}  project=${COMPOSE_PROJECT_NAME}"
echo "datadir=${DATA_DIR}"
echo "HTTP ${HTTP_PORT}  WS ${WS_PORT}  P2P ${P2P_PORT}"
echo "Heimdall REST must be reachable at HEIMDALL_URL=${HEIMDALL_URL}"
if [[ "${CHAIN}" == "amoy" ]]; then
  echo "Amoy uses Polygon's public Heimdall API (no local Heimdall required)."
fi
echo "Next:"
echo "  docker compose pull"
echo "  docker compose up -d"
