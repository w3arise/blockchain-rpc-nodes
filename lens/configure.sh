#!/usr/bin/env bash
#
# Configure Lens deployment: create .env from env.template if missing.
#
# Usage: ./configure.sh

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
else
  echo ".env already exists — not overwriting"
fi

if grep -q 'EN_DA_SECRETS_SEED_PHRASE=<GENERATE_OR_SET>' "${ENV_FILE}"; then
  EN_VERSION="$(grep '^EN_VERSION=' "${ENV_FILE}" | cut -d= -f2-)"
  echo ""
  echo "Set EN_DA_SECRETS_SEED_PHRASE in .env (any fresh BIP39 12-word phrase)."
  echo "Example generator:"
  echo "  docker run --rm --entrypoint /usr/bin/zksync_external_node matterlabs/external-node:${EN_VERSION} generate-secrets"
fi

echo ""
echo "Next:"
echo "  edit .env — set EN_ETH_CLIENT_URL, DB_PASSWORD, and EN_DA_SECRETS_SEED_PHRASE"
echo "  docker compose up -d"
echo ""
echo "RPC: http://127.0.0.1:\${EN_HTTP_PORT:-3060}  WS: ws://127.0.0.1:\${EN_WS_PORT:-3061}"
