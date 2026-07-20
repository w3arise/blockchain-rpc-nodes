#!/usr/bin/env bash
#
# Download Pharos mainnet genesis and VERSION into the datadir.
#
# Skip when restoring a snapshot into $HOME/pharos-data (see README).
#
# Usage: ./init-database.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RESOURCES_BASE="https://raw.githubusercontent.com/PharosNetwork/resources/refs/heads/main"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/pharos-data}"
mkdir -p "${DATA_DIR}/bin"

for tool in curl; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

echo "==> Downloading mainnet genesis.conf"
curl -fsSL "${RESOURCES_BASE}/mainnet.genesis" -o "${DATA_DIR}/genesis.conf"

echo "==> Downloading mainnet bin/VERSION"
curl -fsSL "${RESOURCES_BASE}/mainnet.version" -o "${DATA_DIR}/bin/VERSION"

echo ""
echo "==> Initialization complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
