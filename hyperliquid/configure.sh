#!/usr/bin/env bash
#
# Create .env from env.template, ensure HOST_DATADIR exists, and write
# override_public_ip_address from the host public IP.
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"
DATADIR="${HOST_DATADIR:-$HOME/hyperliquid-data}"
mkdir -p "${DATADIR}"

PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

IP_FILE="${DATADIR}/override_public_ip_address"
CURRENT_IP=""
if [[ -f "${IP_FILE}" ]]; then
  CURRENT_IP="$(tr -d '[:space:]' < "${IP_FILE}")"
fi
if [[ "${CURRENT_IP}" != "${PUBLIC_IP}" ]]; then
  if [[ -w "${DATADIR}" ]]; then
    printf '%s\n' "${PUBLIC_IP}" > "${IP_FILE}"
  else
    printf '%s\n' "${PUBLIC_IP}" | sudo tee "${IP_FILE}" >/dev/null
  fi
  echo "set ${IP_FILE} to ${PUBLIC_IP}"
else
  echo "public IP already ${PUBLIC_IP}"
fi

if [[ ! -f "${SCRIPT_DIR}/override_gossip_config.json" ]]; then
  echo "WARN: missing override_gossip_config.json — run ./override-gossip.sh or copy from upstream node repo" >&2
fi

echo ""
echo "Datadir: ${DATADIR}"
echo "Before first start: sudo chown -R 10000:10000 ${DATADIR}"
echo ""
echo "Next:"
echo "  docker compose build"
echo "  docker compose up -d"
