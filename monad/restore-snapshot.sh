#!/usr/bin/env bash
#
# Hard reset and restore mainnet TrieDB from the Monad Foundation snapshot script.
#
# Usage (as root): ./restore-snapshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"

if [[ ! -e /dev/triedb ]]; then
  echo "ERROR: /dev/triedb missing — run ./init-triedb.sh first" >&2
  exit 1
fi

systemctl stop monad-bft monad-execution monad-rpc 2>/dev/null || true

bash /opt/monad/scripts/reset-workspace.sh

echo "restoring ${NETWORK} snapshot from ${MF_BUCKET}..."
curl -fsSL "${MF_BUCKET}/scripts/${NETWORK}/restore-from-snapshot.sh" | bash

VALIDATORS_FILE="${MONAD_HOME}/monad-bft/config/validators/validators.toml"
curl -fsSL "${MF_BUCKET}/validators/${NETWORK}/validators.toml" -o "${VALIDATORS_FILE}"
chown monad:monad "${VALIDATORS_FILE}"

curl -fsSL "${MF_BUCKET}/scripts/${NETWORK}/download-forkpoint.sh" | bash

chown -R monad:monad "${MONAD_HOME}"

echo "snapshot restore complete — start services with:"
echo "  systemctl start monad-bft monad-execution monad-rpc"
