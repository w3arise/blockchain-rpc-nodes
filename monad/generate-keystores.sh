#!/usr/bin/env bash
#
# Generate SECP and BLS keystores for peer discovery (public full node identity).
#
# Usage (as root): ./generate-keystores.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"
env_require KEYSTORE_PASSWORD

KEY_DIR="${MONAD_HOME}/monad-bft/config"
BACKUP_DIR="/opt/monad/backup"

if [[ -f "${KEY_DIR}/id-secp" || -f "${KEY_DIR}/id-bls" ]]; then
  echo "keystores already exist in ${KEY_DIR}; skipping"
  exit 0
fi

mkdir -p "${BACKUP_DIR}"

# shellcheck disable=SC1091
source "${MONAD_HOME}/.env"

monad-keystore create \
  --key-type secp \
  --keystore-path "${KEY_DIR}/id-secp" \
  --password "${KEYSTORE_PASSWORD}" > "${BACKUP_DIR}/secp-backup"

monad-keystore create \
  --key-type bls \
  --keystore-path "${KEY_DIR}/id-bls" \
  --password "${KEYSTORE_PASSWORD}" > "${BACKUP_DIR}/bls-backup"

grep "public key" "${BACKUP_DIR}/secp-backup" "${BACKUP_DIR}/bls-backup" \
  | tee "${MONAD_HOME}/pubkey-secp-bls"

chown -R monad:monad "${KEY_DIR}" "${MONAD_HOME}/pubkey-secp-bls"
chmod 700 "${BACKUP_DIR}"
chmod 600 "${BACKUP_DIR}/"*

echo ""
echo "Back up /opt/monad/backup/secp-backup and bls-backup off-host before continuing."
