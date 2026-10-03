#!/usr/bin/env bash
#
# Patch Heimdall sentry settings into config.toml and app.toml.
# Idempotent — safe to re-run after snapshot restore or .env changes.
#
# Pruned sentry: pruning=default, min-retain-blocks=2000000, indexer=null.
# No bridge, no RabbitMQ.
#
# Usage: ./patch-config.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh <mainnet|amoy> first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-heimdall-data}"
MONIKER="${MONIKER:-heimdall-sentry}"
P2P_PORT="${P2P_PORT:-26656}"
API_PORT="${API_PORT:-1317}"
TM_RPC_PORT="${TM_RPC_PORT:-26657}"
METRICS_PORT="${METRICS_PORT:-26660}"
RPC_BIND_ADDR="${RPC_BIND_ADDR:-127.0.0.1}"
METRICS_BIND_ADDR="${METRICS_BIND_ADDR:-127.0.0.1}"
PRUNING="${PRUNING:-default}"
MIN_RETAIN_BLOCKS="${MIN_RETAIN_BLOCKS:-2000000}"
INDEXER="${INDEXER:-null}"
HEIMDALL_CHAIN="${HEIMDALL_CHAIN:-}"
BOR_RPC_URL="${BOR_RPC_URL:-}"
SEEDS="${SEEDS:-}"
EXT_IP="${EXT_IP:-}"

CONFIG_TOML="${DATA_DIR}/config/config.toml"
APP_TOML="${DATA_DIR}/config/app.toml"

if [[ "${EXT_IP}" == "" || "${EXT_IP}" == *YOUR_PUBLIC_IP* || "${EXT_IP}" == *"<"* ]]; then
  echo "ERROR: EXT_IP is unset — run ./configure.sh" >&2
  exit 1
fi
if [[ -z "${SEEDS}" ]]; then
  echo "ERROR: SEEDS is empty" >&2
  exit 1
fi
if [[ "${HEIMDALL_CHAIN}" != "mainnet" && "${HEIMDALL_CHAIN}" != "amoy" ]]; then
  echo "ERROR: HEIMDALL_CHAIN must be mainnet or amoy (got: ${HEIMDALL_CHAIN:-empty})" >&2
  exit 1
fi
if [[ -z "${BOR_RPC_URL}" ]]; then
  echo "ERROR: BOR_RPC_URL is empty" >&2
  exit 1
fi
if [[ "${MIN_RETAIN_BLOCKS}" -lt 2000000 ]]; then
  echo "ERROR: MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS} is below the client floor of 2000000" >&2
  exit 1
fi

BACKUP_DIR="$(mktemp -d)"
trap 'rm -rf "${BACKUP_DIR}"' EXIT

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -E -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

set_toml_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  if ! grep -qE "^${key}[[:space:]]*=" "${file}"; then
    echo "ERROR: ${key} not found in ${file}" >&2
    exit 1
  fi
  sed_inplace "s|^(${key}[[:space:]]*=[[:space:]]*).*|\1${value}|" "${file}"
}

set_toml_section_key() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local tmp
  tmp="$(mktemp)"

  if ! awk -v section="${section}" -v key="${key}" -v value="${value}" '
    /^\[.*\]$/ {
      line = $0
      gsub(/^\[|\]$/, "", line)
      current = line
    }
    current == section && $0 ~ "^" key "[[:space:]]*=" {
      print key " = " value
      found = 1
      next
    }
    { print }
    END { exit(found ? 0 : 1) }
  ' "${file}" > "${tmp}"; then
    echo "ERROR: [${section}] ${key} not found in ${file}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  mv "${tmp}" "${file}"
}

print_diff() {
  local name="$1"
  local before="$2"
  local after="$3"

  if cmp -s "${before}" "${after}"; then
    echo "    ${name}: unchanged"
    return 0
  fi

  echo ""
  echo "--- ${name} ---"
  diff -u "${before}" "${after}" || true
}

for file in "${CONFIG_TOML}" "${APP_TOML}"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: missing ${file} — run ./init-database.sh first" >&2
    exit 1
  fi
done

cp "${CONFIG_TOML}" "${BACKUP_DIR}/config.toml"
cp "${APP_TOML}" "${BACKUP_DIR}/app.toml"

echo "==> Patching config.toml"
set_toml_key "${CONFIG_TOML}" "moniker" "\"${MONIKER}\""
set_toml_section_key "${CONFIG_TOML}" "rpc" "laddr" "\"tcp://${RPC_BIND_ADDR}:${TM_RPC_PORT}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "laddr" "\"tcp://0.0.0.0:${P2P_PORT}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "external_address" "\"${EXT_IP}:${P2P_PORT}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "seeds" "\"${SEEDS}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "persistent_peers" "\"${SEEDS}\""
set_toml_section_key "${CONFIG_TOML}" "tx_index" "indexer" "\"${INDEXER}\""
set_toml_section_key "${CONFIG_TOML}" "instrumentation" "prometheus" "true"
set_toml_section_key "${CONFIG_TOML}" "instrumentation" "prometheus_listen_addr" "\"${METRICS_BIND_ADDR}:${METRICS_PORT}\""

echo "==> Patching app.toml (pruned sentry)"
set_toml_key "${APP_TOML}" "pruning" "\"${PRUNING}\""
set_toml_key "${APP_TOML}" "min-retain-blocks" "${MIN_RETAIN_BLOCKS}"
set_toml_section_key "${APP_TOML}" "api" "address" "\"tcp://${RPC_BIND_ADDR}:${API_PORT}\""
set_toml_section_key "${APP_TOML}" "custom" "chain" "\"${HEIMDALL_CHAIN}\""
set_toml_section_key "${APP_TOML}" "custom" "bor_rpc_url" "\"${BOR_RPC_URL}\""

echo ""
echo "==> Changes"
print_diff "config.toml" "${BACKUP_DIR}/config.toml" "${CONFIG_TOML}"
print_diff "app.toml" "${BACKUP_DIR}/app.toml" "${APP_TOML}"

echo ""
echo "==> Config patched"
echo "    datadir: ${DATA_DIR}"
echo "    chain=${HEIMDALL_CHAIN} pruning=${PRUNING} min-retain-blocks=${MIN_RETAIN_BLOCKS} indexer=${INDEXER}"
echo "    REST ${RPC_BIND_ADDR}:${API_PORT}  P2P ${EXT_IP}:${P2P_PORT}"
echo "Next: docker compose up -d"
