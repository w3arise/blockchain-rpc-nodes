#!/usr/bin/env bash
#
# Configure Linea Besu deployment: .env, public IP, Maru P2P address, file permissions.
#
# Usage: ./configure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
MARU_CONFIG="${SCRIPT_DIR}/maru/maru-config.toml"

sed_inplace() {
  sed -i -e "$1" "$2"
}

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env"
fi

PUBLIC_IP="$(curl -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
fi

CURRENT_MARU_IP="$(grep -E '^ip-address' "${MARU_CONFIG}" | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ "${CURRENT_MARU_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^ip-address = \".*\"|ip-address = \"${PUBLIC_IP}\"|" "${MARU_CONFIG}"
  echo "set ip-address=${PUBLIC_IP} in maru/maru-config.toml"
fi

find besu maru -type f -exec chmod o+r {} +
echo "chmod o+r besu maru"
