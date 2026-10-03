#!/usr/bin/env bash
#
# Configure Sonic: create .env, set EXT_IP, and create the datadir.
# Genesis download happens in ./sonic-init.sh, and only when the datadir
# has no chain database.
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

set_env_value() {
  local name="$1"
  local value="$2"
  if grep -qE "^${name}=" "${ENV_FILE}"; then
    sed_inplace "s|^${name}=.*|${name}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${name}" "${value}" >> "${ENV_FILE}"
  fi
}

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

# Replace the placeholder before sourcing. An unquoted EXT_IP=<YOUR_PUBLIC_IP>
# is a redirect and makes `source .env` fail. Existing .env files copied from
# an older template still have that line.
PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
CURRENT_EXT_IP="${CURRENT_EXT_IP%\"}"
CURRENT_EXT_IP="${CURRENT_EXT_IP#\"}"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  set_env_value EXT_IP "${PUBLIC_IP}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/sonic-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "datadir: ${DATA_DIR}"
echo "Next:"
echo "  docker compose build"
echo "  ./sonic-init.sh"
echo "  docker compose up -d"
