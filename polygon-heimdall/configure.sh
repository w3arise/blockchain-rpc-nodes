#!/usr/bin/env bash
#
# Configure Polygon Heimdall: copy env.template.<network> to .env and set EXT_IP.
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

BUILD_UID="$(id -u)"
BUILD_GID="$(id -g)"
sed_inplace "s|^BUILD_UID=.*|BUILD_UID=${BUILD_UID}|" "${ENV_FILE}"
sed_inplace "s|^BUILD_GID=.*|BUILD_GID=${BUILD_GID}|" "${ENV_FILE}"
echo "set BUILD_UID=${BUILD_UID} BUILD_GID=${BUILD_GID} in .env"

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-heimdall-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "chain=${CHAIN}  container=${CONTAINER_NAME}  project=${COMPOSE_PROJECT_NAME}"
echo "datadir=${DATA_DIR}"
echo "REST ${API_PORT}  CometBFT ${TM_RPC_PORT}  P2P ${P2P_PORT}  metrics ${METRICS_PORT}"
echo "Next:"
echo "  ./init-database.sh"
echo "  ./restore-snapshot.sh    # set SNAPSHOT_URL to a pruned Heimdall tarball"
echo "  ./patch-config.sh"
echo "  docker compose up -d"
