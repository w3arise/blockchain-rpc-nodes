#!/usr/bin/env bash
#
# Configure Unichain deployment: create .env from env.template and set public IP.
#
# Usage: ./configure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

strip_quotes() {
  local val="$1"
  val="${val%\"}"
  val="${val#\"}"
  printf '%s' "${val}"
}

env_get() {
  local key="$1"
  local default="$2"
  if [[ -f "${ENV_FILE}" ]] && grep -qE "^${key}=" "${ENV_FILE}"; then
    local val
    val="$(grep -E "^${key}=" "${ENV_FILE}" | cut -d= -f2-)"
    val="$(strip_quotes "${val}")"
    val="${val/\$HOME/$HOME}"
    printf '%s' "${val}"
    return
  fi
  printf '%s' "${default}"
}

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

CURRENT_EXT_IP="$(strip_quotes "$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)")"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

CURRENT_ADVERTISE_IP="$(strip_quotes "$(grep -E '^OP_NODE_P2P_ADVERTISE_IP=' "${ENV_FILE}" | cut -d= -f2- || true)")"
if [[ "${CURRENT_ADVERTISE_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^OP_NODE_P2P_ADVERTISE_IP=.*|OP_NODE_P2P_ADVERTISE_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set OP_NODE_P2P_ADVERTISE_IP=${PUBLIC_IP} in .env"
else
  echo "OP_NODE_P2P_ADVERTISE_IP already set to ${PUBLIC_IP}"
fi

HOST_DATADIR="$(env_get HOST_DATADIR "${HOME}/unichain-op-reth-data")"
HOST_OP_NODE_DATADIR="$(env_get HOST_OP_NODE_DATADIR "${HOME}/unichain-op-node-data")"
mkdir -p "${HOST_DATADIR}" "${HOST_OP_NODE_DATADIR}" "${SCRIPT_DIR}/config"

echo ""
echo "Next:"
echo "  edit .env — set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON"
echo "  ./create-jwt.sh"
echo "  docker compose up -d"
