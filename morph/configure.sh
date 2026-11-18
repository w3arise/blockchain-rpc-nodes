#!/usr/bin/env bash
#
# Configure Morph deployment: create .env from env.template and set public IP.
#
# Usage:
#   ./configure.sh                 # mainnet, geth (defaults)
#   ./configure.sh hoodi           # Hoodi testnet
#   ./configure.sh mainnet reth    # morph-reth instead of morph-geth
#
# The client is stored as COMPOSE_FILE in .env. To switch clients, run
# "docker compose down --remove-orphans" BEFORE re-running this script (it refuses
# while a container of the other client exists).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
# shellcheck source-path=SCRIPTDIR source=client-lib.sh
source "${SCRIPT_DIR}/client-lib.sh"

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

CLIENT="${2:-geth}"
if ! CLIENT_COMPOSE="$(compose_file_for_client "${CLIENT}")"; then
  echo "ERROR: unknown client: ${CLIENT} (use geth|reth)" >&2
  exit 1
fi

ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from $(basename "${ENV_TEMPLATE}")"
fi

CURRENT_CLIENT="$(client_from_env "${ENV_FILE}")"
if [[ "${CURRENT_CLIENT}" != "${CLIENT}" ]] && client_stack_present "${CURRENT_CLIENT}"; then
  echo "ERROR: a morph-${CURRENT_CLIENT} container exists. Switching to ${CLIENT} would orphan it." >&2
  echo "Run 'docker compose down --remove-orphans' (still on the ${CURRENT_CLIENT} COMPOSE_FILE), then re-run this script." >&2
  exit 1
fi

PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]' || true)"
if ! valid_ipv4 "${PUBLIC_IP}"; then
  echo "ERROR: ip.me did not return a valid IPv4 address (got: '${PUBLIC_IP:0:40}')" >&2
  exit 1
fi

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

# An .env created before reth support lacks the RETH_* keys: add the missing ones
# (both clients: the upgrade scripts sync RETH_IMAGE on geth hosts too).
while IFS= read -r line; do
  key="${line%%=*}"
  if ! grep -qE "^${key}=" "${ENV_FILE}"; then
    printf '%s\n' "${line}" >> "${ENV_FILE}"
    echo "added ${key} to .env"
  fi
done < <(grep -E '^RETH_[A-Z0-9_]+=' "${ENV_TEMPLATE}")

# COMPOSE_FILE replaces compose's automatic docker-compose.override.yml pickup,
# so keep a host override file when there is one.
if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
  CLIENT_COMPOSE="${CLIENT_COMPOSE}:docker-compose.override.yml"
fi
CURRENT_COMPOSE="$(grep -E '^COMPOSE_FILE=' "${ENV_FILE}" | tail -n1 | cut -d= -f2- || true)"
if [[ "${CURRENT_COMPOSE}" != "${CLIENT_COMPOSE}" ]]; then
  set_env_var "${ENV_FILE}" COMPOSE_FILE "${CLIENT_COMPOSE}"
  echo "set COMPOSE_FILE=${CLIENT_COMPOSE} in .env (${CLIENT})"
else
  echo "COMPOSE_FILE already ${CLIENT_COMPOSE}"
fi

echo ""
echo "Next:"
echo "  edit .env — set L1_ETH_RPC and L1_ETH_BEACON_RPC"
echo "  ./init-database.sh ${NETWORK}   # or restore a snapshot first (README)"
echo "  ./create-jwt.sh"
echo "  docker compose up -d"
