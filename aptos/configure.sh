#!/usr/bin/env bash
#
# Configure Aptos fullnode: create .env and prepare datadir.
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
CONFIG_DIR="${SCRIPT_DIR}/config"

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

for f in genesis.blob waypoint.txt fullnode.yaml; do
  if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
    echo "ERROR: missing ${CONFIG_DIR}/${f} (required for aptos-node startup)" >&2
    exit 1
  fi
done

DATA_DIR="${HOST_DATADIR:-${HOME}/aptos-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "datadir: ${DATA_DIR}"
echo "Next:"
echo "  docker compose up -d"
