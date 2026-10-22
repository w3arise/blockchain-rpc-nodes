#!/usr/bin/env bash
#
# Configure Ronin deployment: create .env from env.template and set public IP.
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

# Append keys added to env.template since .env was created (keeps existing values).
[[ -z "$(tail -c1 "${ENV_FILE}")" ]] || echo >> "${ENV_FILE}"
while IFS= read -r line; do
  key="${line%%=*}"
  if ! grep -qE "^${key}=" "${ENV_FILE}"; then
    printf '%s\n' "${line}" >> "${ENV_FILE}"
    echo "added ${key} to .env from env.template"
  fi
done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${ENV_TEMPLATE}")

# Set KEY=PUBLIC_IP in .env unless it already holds that value.
set_public_ip() {
  local key="$1"
  local current
  current="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- || true)"
  current="${current%%#*}"
  current="${current//[[:space:]\"\']/}"
  if [[ "${current}" != "${PUBLIC_IP}" ]]; then
    sed_inplace "s|^${key}=.*|${key}=${PUBLIC_IP}|" "${ENV_FILE}"
    echo "set ${key}=${PUBLIC_IP} in .env"
  else
    echo "${key} already set to ${PUBLIC_IP}"
  fi
}

set_public_ip EXT_IP
set_public_ip OP_NODE_P2P_ADVERTISE_IP

echo ""
echo "Next:"
echo "  edit .env — set L1_RPC and L1_BEACON"
echo "  ./init-datadirs.sh"
echo "  docker compose up -d"
