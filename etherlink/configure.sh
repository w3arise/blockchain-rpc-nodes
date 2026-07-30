#!/usr/bin/env bash
#
# Configure Etherlink EVM observer: create .env, mkdir datadir, print chown.
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
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/etherlink-data}"
mkdir -p "${DATA_DIR}"

echo ""
echo "Datadir: ${DATA_DIR}"
echo "octez-evm-node runs as UID 1000 (tezos). Own the datadir before first start:"
echo "  sudo chown -R 1000:1000 \"${DATA_DIR}\""
echo ""
echo "Next:"
echo "  sudo chown -R 1000:1000 \"${DATA_DIR}\""
echo "  docker compose up -d"
echo ""
echo "First start downloads a ${HISTORY_MODE:-full:1} snapshot via --init-from-snapshot."
