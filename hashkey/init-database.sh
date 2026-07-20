#!/usr/bin/env bash
#
# Initialize HashKey op-geth datadir from genesis (first start only).
#
# Usage: ./init-database.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/hashkey-op-geth-data}"
DATA_DIR="${DATA_DIR/\$HOME/$HOME}"
GENESIS_FILE="${SCRIPT_DIR}/config/genesis.json"
OP_GETH_IMAGE="${OP_GETH_IMAGE:?set OP_GETH_IMAGE in .env (run ./configure.sh first)}"

if [[ ! -f "${GENESIS_FILE}" ]]; then
  echo "ERROR: missing ${GENESIS_FILE}" >&2
  exit 1
fi

mkdir -p "${DATA_DIR}"

if [[ -d "${DATA_DIR}/geth" ]]; then
  echo "datadir already initialized at ${DATA_DIR}/geth (skipping)"
  exit 0
fi

echo "initializing ${DATA_DIR} from genesis..."
docker run --rm \
  --platform linux/amd64 \
  -v "${DATA_DIR}:/data" \
  -v "${GENESIS_FILE}:/genesis.json:ro" \
  "${OP_GETH_IMAGE}" \
  init --state.scheme=hash --datadir=/data /genesis.json

echo "done."
