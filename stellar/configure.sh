#!/usr/bin/env bash
#
# Configure Stellar RPC: create .env, datadir, and stellar-rpc.toml from template.
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
RPC_CONFIG="${SCRIPT_DIR}/config/stellar-rpc.toml"
RPC_TEMPLATE="${SCRIPT_DIR}/config/stellar-rpc.toml.template"

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${RPC_TEMPLATE}" ]]; then
  echo "ERROR: missing ${RPC_TEMPLATE}" >&2
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

case "${STELLAR_NETWORK:-pubnet}" in
  pubnet|testnet) ;;
  *)
    echo "ERROR: STELLAR_NETWORK must be pubnet or testnet (got: ${STELLAR_NETWORK:-<unset>})" >&2
    exit 1
    ;;
esac

if [[ -z "${HISTORY_RETENTION_WINDOW:-}" ]] || ! [[ "${HISTORY_RETENTION_WINDOW}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: HISTORY_RETENTION_WINDOW must be a positive integer (ledger count)" >&2
  exit 1
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/stellar-data}"
mkdir -p "${DATA_DIR}/captive-core"

TMP_CONFIG="$(mktemp)"
trap 'rm -f "${TMP_CONFIG}"' EXIT

sed \
  -e "s/@STELLAR_NETWORK@/${STELLAR_NETWORK}/g" \
  -e "s/@HISTORY_RETENTION_WINDOW@/${HISTORY_RETENTION_WINDOW}/g" \
  "${RPC_TEMPLATE}" > "${TMP_CONFIG}"
mv "${TMP_CONFIG}" "${RPC_CONFIG}"
trap - EXIT

echo ""
echo "datadir: ${DATA_DIR}"
echo "rpc config: ${RPC_CONFIG}"
echo "network: ${STELLAR_NETWORK}"
echo "retention: ${HISTORY_RETENTION_WINDOW} ledgers"
echo ""
echo "Next:"
echo "  docker compose up -d"
