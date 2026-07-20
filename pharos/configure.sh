#!/usr/bin/env bash
#
# Configure Pharos deployment: create .env from env.template and prepare datadir.
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/pharos-data}"
mkdir -p "${DATA_DIR}/bin"

RESOURCES_BASE="https://raw.githubusercontent.com/PharosNetwork/resources/refs/heads/main"
if [[ ! -f "${DATA_DIR}/genesis.conf" ]]; then
  echo "==> Downloading mainnet genesis.conf"
  curl -fsSL "${RESOURCES_BASE}/mainnet.genesis" -o "${DATA_DIR}/genesis.conf"
fi
if [[ ! -f "${DATA_DIR}/bin/VERSION" ]]; then
  echo "==> Downloading mainnet bin/VERSION"
  curl -fsSL "${RESOURCES_BASE}/mainnet.version" -o "${DATA_DIR}/bin/VERSION"
fi

if [[ -z "${CONSENSUS_KEY_PWD:-}" ]]; then
  echo "WARNING: set CONSENSUS_KEY_PWD in .env before first start" >&2
fi

echo ""
echo "Next:"
echo "  ./init-database.sh   # from-scratch only; skip when restoring a snapshot"
echo "  docker compose up -d"
