#!/usr/bin/env bash
#
# Configure Polygon Bor: create .env, apply mainnet or Amoy presets, set EXT_IP.
#
# Usage: ./configure.sh <mainnet|amoy>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

MAINNET_BOOTNODES='enode://48e6326841ce106f6b4e229a1be7e98a1d12be57e328b08cb461f6744ae4e78f5ec2340996ce9b40928a1a90137aadea13e25ca34774b52a3600d13a52c5c7bb@34.185.209.56:30303,enode://8ab6905fe76aa9001adb77135250e918db888cac216870c0e95cf26650d83d31d8c2c93d54c3333e0a2196517c41651d174b743ec3e11f44e595f62b77fec7ba@34.185.162.14:30303,enode://02e0b33cf60fb1f88f853c7c04830156151f4acd1c36173cd3fe1f375801fb4f5be5b3a89c98527915d37ed217752933c3faf4c820df740c9dd681294caebcf6@34.179.171.228:30303,enode://079c387b65b09674825462ea63c528ca996af7b03d19b1b2ab6557347434838067db6dd7ae5e0c2e08d5ba164117f3d7faffbf3e890cb91cffbdf45a433ddfce@35.246.166.189:30303,enode://191d06720948ae0119343e5798098f5b1f95a308174c4119d226da91833bc0176009bcc8bf5012e490500562d4d5b5427c307b01f3485b2e8351ac5afd946864@34.142.28.190:30303,enode://30a4651b245e9a0cec674b9ecb5a06ca01553aa727e14a77d0f1ccdb9e48a975f3be631505f417aae438be545ac3b290cd3ed00bef96efd7fb0fb7f916397b3f@34.39.56.114:30303,enode://b950b98b92e118551d79c7280b97ddfcdf3dacb620367ebd45e8382f8e69390df192055386221025ffd3c03912da2aadf668ae6ea7b35f391d82ef87452b3f02@34.147.169.102:30303,enode://5f6232dc546bf615c7b5bc1c896323340892a1c41097a89a1d38385a5d48bb02f9023377e526911a9da6e4112415aa9f3803cbeeef8243a2bfc4a3d0219ae69e@35.230.142.203:30303'
AMOY_BOOTNODES='enode://8b62d23881dddc0ea26e88f3b15b4d3a04a6dc4480bec4b2121aff02126d4a0fb50032880772a0a7cfe408938a3863c6635d6f674298255c54a4cbef1ad0992c@34.89.255.109:30303,enode://9fa548b9d1c6760df0f80214d354dffd008a1d56509e4bd12342c84322b5c974b71d38275401a8ca0f2b24437e8609975be1de906090234e84e986739e0f82b3@34.89.119.250:30303,enode://26f30c60179b60d976f0ff2f7e197147479a9609fa38af13a7168f0bfeb842adad8750bc3f8e8d46ceacf2071981c492c2bb6760537ca0eb870e9aece7a59b31@34.89.40.235:30303,enode://c4245ae8a1b7c4452b24c9d0384ed47c6bb657f3d23d0cc62bccee54d71d1b5fc76225693474070feaa834780a5b274126aef56c2f4f4537cbe81478e45ac242@34.179.189.75:30303'

usage() {
  echo "Usage: $0 <mainnet|amoy>" >&2
  exit 1
}

NETWORK="${1:-}"
case "${NETWORK}" in
  mainnet|amoy) ;;
  *) usage ;;
esac

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local current tmp
  current="$(grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2- || true)"
  if [[ "${current}" == "${value}" ]]; then
    return 0
  fi
  tmp="$(mktemp)"
  export _SET_ENV_KEY="${key}" _SET_ENV_VALUE="${value}"
  awk '
    BEGIN { key=ENVIRON["_SET_ENV_KEY"]; value=ENVIRON["_SET_ENV_VALUE"]; done=0 }
    index($0, key "=") == 1 { print key "=" value; done=1; next }
    { print }
    END { if (!done) print key "=" value }
  ' "${ENV_FILE}" > "${tmp}"
  unset _SET_ENV_KEY _SET_ENV_VALUE
  mv "${tmp}" "${ENV_FILE}"
  if [[ ${#value} -gt 80 ]]; then
    echo "set ${key}"
  else
    echo "set ${key}=${value}"
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

if [[ "${NETWORK}" == "amoy" ]]; then
  set_env_value CHAIN amoy
  set_env_value HOST_DATADIR '$HOME/polygon-bor-amoy-data'
  set_env_value HTTP_PORT 8755
  set_env_value WS_PORT 8756
  set_env_value P2P_PORT 30305
  set_env_value BOOTNODES "${AMOY_BOOTNODES}"
  set_env_value DISCOVERY_DNS 'enrtree://AKUEZKN7PSKVNR65FZDHECMKOJQSGPARGTPPBI7WS2VUL4EGR6XPC@amoy.polygon-peers.io'
else
  set_env_value CHAIN mainnet
  set_env_value HOST_DATADIR '$HOME/polygon-bor-data'
  set_env_value HTTP_PORT 8745
  set_env_value WS_PORT 8746
  set_env_value P2P_PORT 30304
  set_env_value BOOTNODES "${MAINNET_BOOTNODES}"
  set_env_value DISCOVERY_DNS 'enrtree://AKUEZKN7PSKVNR65FZDHECMKOJQSGPARGTPPBI7WS2VUL4EGR6XPC@pos.polygon-peers.io'
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

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-bor-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "chain=${CHAIN}  datadir=${DATA_DIR}"
echo "HTTP ${HTTP_PORT}  WS ${WS_PORT}  P2P ${P2P_PORT}"
echo "Heimdall REST must be reachable at HEIMDALL_URL=${HEIMDALL_URL}"
if [[ "${CHAIN}" == "amoy" ]]; then
  echo "Use an Amoy Heimdall v2 (heimdallv2-80002), not mainnet."
fi
echo "Next:"
echo "  docker compose pull"
echo "  docker compose up -d"
