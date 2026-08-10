#!/usr/bin/env bash
#
# Configure historical Zircuit RPC: create .env from env.template.
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

mkdir -p "${HOME}/zircuit-historical-data"

echo ""
echo "Next:"
echo "  # restore Liquify lz4 snapshot into HOST_DATADIR — see README"
echo "  docker compose up -d"
