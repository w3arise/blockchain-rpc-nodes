#!/usr/bin/env bash
#
# Prepare a Monad mainnet public full node on bare metal:
#   - create /home/monad layout
#   - fetch official MF config
#   - set public IP, node name, keystore password
#
# Usage (as root on the host): ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"

env_require NODE_NAME
env_require TRIEDB_DRIVE
env_require MONAD_VERSION

PUBLIC_IP="$(fetch_public_ip)"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

if [[ "${EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  EXT_IP="${PUBLIC_IP}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
fi

if [[ -z "${KEYSTORE_PASSWORD}" ]]; then
  KEYSTORE_PASSWORD="$(openssl rand -base64 32)"
  sed_inplace "s|^KEYSTORE_PASSWORD=.*|KEYSTORE_PASSWORD='${KEYSTORE_PASSWORD}'|" "${ENV_FILE}"
  echo "generated KEYSTORE_PASSWORD in .env"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

ensure_monad_user

echo "downloading official mainnet config from ${MF_BUCKET}..."
curl -fsSL -o "${MONAD_HOME}/.env.example" \
  "${MF_BUCKET}/config/${NETWORK}/latest/.env.example"
curl -fsSL -o "${MONAD_HOME}/monad-bft/config/node.toml" \
  "${MF_BUCKET}/config/${NETWORK}/latest/full-node-node.toml"

write_monad_env
check_env_drift

sed_inplace "s|^node_name = .*|node_name = \"${NODE_NAME}\"|" \
  "${MONAD_HOME}/monad-bft/config/node.toml"
sed_inplace "s|^beneficiary = .*|beneficiary = \"${BENEFICIARY}\"|" \
  "${MONAD_HOME}/monad-bft/config/node.toml"

chown -R monad:monad "${MONAD_HOME}"

echo ""
echo "Configured ${MONAD_HOME} for public full node ${NODE_NAME} (${EXT_IP}:${P2P_PORT})"
echo ""
echo "Next:"
echo "  ./install-package.sh"
echo "  ./init-triedb.sh"
echo "  ./generate-keystores.sh"
echo "  ./sign-name-record.sh"
echo "  ./restore-snapshot.sh"
echo "  systemctl enable monad-bft monad-execution monad-rpc"
echo "  systemctl start monad-bft monad-execution monad-rpc"
