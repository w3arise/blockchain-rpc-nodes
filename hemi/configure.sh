#!/usr/bin/env bash
#
# Configure Hemi: create .env, set EXT_IP, create datadirs.
#
# Usage: ./configure.sh
#
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

env_get() {
  local key="$1"
  local default="$2"
  if [[ -f "${ENV_FILE}" ]] && grep -qE "^${key}=" "${ENV_FILE}"; then
    local val
    val="$(grep -E "^${key}=" "${ENV_FILE}" | cut -d= -f2-)"
    val="${val/\$HOME/$HOME}"
    echo "${val}"
    return
  fi
  echo "${default}"
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

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

HEMI_GETH_DATA="$(env_get HEMI_GETH_DATA "${HOME}/hemi-op-geth-data")"
HEMI_TBC_DATA="$(env_get HEMI_TBC_DATA "${HOME}/hemi-tbc-data")"
HEMI_OP_NODE_DATA="$(env_get HEMI_OP_NODE_DATA "${HOME}/hemi-op-node-data")"

mkdir -p "${HEMI_GETH_DATA}" "${HEMI_TBC_DATA}" "${HEMI_OP_NODE_DATA}"
chmod -R a+rX "${SCRIPT_DIR}/config"

echo "created datadirs:"
echo "  ${HEMI_GETH_DATA}"
echo "  ${HEMI_TBC_DATA}"
echo "  ${HEMI_OP_NODE_DATA}"

echo ""
echo "First start only — op-geth runs as UID 65532; set datadir ownership before compose up:"
echo "  sudo chown -R 65532:65532 ${HEMI_GETH_DATA} ${HEMI_TBC_DATA}"
echo ""
echo "Next:"
echo "  # set GETHL1ENDPOINT and PRYSMENDPOINT in .env"
echo "  ./create-jwt.sh"
echo "  docker compose up -d"
