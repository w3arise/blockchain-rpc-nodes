#!/usr/bin/env bash
#
# Apply Sei mainnet Option A settings to config.toml and app.toml under the datadir.
#
# Option A: min-retain-blocks=0 (full blocks + EVM receipts), ss-keep-recent=100000
# (pruned state). Idempotent — safe to re-run after snapshot restore or .env changes.
#
# Usage: ./patch-config.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/sei-data}"
P2P_PORT="${P2P_PORT:-26656}"
PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
MIN_RETAIN_BLOCKS="${MIN_RETAIN_BLOCKS:-0}"
SS_KEEP_RECENT="${SS_KEEP_RECENT:-100000}"
MINIMUM_GAS_PRICES="${MINIMUM_GAS_PRICES:-0.02usei}"
INDEXER="${INDEXER:-kv}"
CONCURRENCY_WORKERS="${CONCURRENCY_WORKERS:-500}"
GAS_CAP="${GAS_CAP:-600000000}"
MAX_BLOCKS_FOR_LOG="${MAX_BLOCKS_FOR_LOG:-2000}"

CONFIG_TOML="${DATA_DIR}/config/config.toml"
APP_TOML="${DATA_DIR}/config/app.toml"

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
set_toml_key "${CONFIG_TOML}" "persistent-peers" "\"${PERSISTENT_PEERS}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "laddr" "\"tcp://0.0.0.0:${P2P_PORT}\""
set_toml_section_key "${CONFIG_TOML}" "rpc" "laddr" "\"tcp://0.0.0.0:26657\""
set_toml_section_key "${CONFIG_TOML}" "tx-index" "indexer" "[\"${INDEXER}\"]"
set_toml_section_key "${CONFIG_TOML}" "statesync" "enable" "false"

if [[ -n "${EXT_IP:-}" ]]; then
  set_toml_section_key "${CONFIG_TOML}" "p2p" "external-address" "\"${EXT_IP}:${P2P_PORT}\""
else
  set_toml_section_key "${CONFIG_TOML}" "p2p" "external-address" '""'
fi

echo "==> Patching app.toml (Option A — historical blocks/receipts)"
set_toml_key "${APP_TOML}" "min-retain-blocks" "${MIN_RETAIN_BLOCKS}"
set_toml_key "${APP_TOML}" "minimum-gas-prices" "\"${MINIMUM_GAS_PRICES}\""
set_toml_key "${APP_TOML}" "concurrency-workers" "${CONCURRENCY_WORKERS}"
set_toml_key "${APP_TOML}" "occ-enabled" "true"
set_toml_section_key "${APP_TOML}" "state-commit" "sc-enable" "true"
set_toml_section_key "${APP_TOML}" "state-store" "ss-enable" "true"
set_toml_section_key "${APP_TOML}" "state-store" "ss-keep-recent" "${SS_KEEP_RECENT}"
set_toml_section_key "${APP_TOML}" "evm" "http_enabled" "true"
set_toml_section_key "${APP_TOML}" "evm" "http_port" "8545"
set_toml_section_key "${APP_TOML}" "evm" "ws_enabled" "true"
set_toml_section_key "${APP_TOML}" "evm" "ws_port" "8546"
set_toml_section_key "${APP_TOML}" "evm" "simulation_gas_limit" "${GAS_CAP}"
set_toml_section_key "${APP_TOML}" "evm" "max_blocks_for_log" "${MAX_BLOCKS_FOR_LOG}"
set_toml_section_key "${APP_TOML}" "api" "enable" "true"
set_toml_section_key "${APP_TOML}" "api" "address" "\"tcp://0.0.0.0:1317\""
set_toml_section_key "${APP_TOML}" "grpc" "enable" "true"
set_toml_section_key "${APP_TOML}" "grpc" "address" "\"0.0.0.0:9090\""

echo ""
echo "==> Changes"
print_diff "config.toml" "${BACKUP_DIR}/config.toml" "${CONFIG_TOML}"
print_diff "app.toml" "${BACKUP_DIR}/app.toml" "${APP_TOML}"

echo ""
echo "==> Config patched"
echo "    datadir: ${DATA_DIR}"
echo "    min-retain-blocks=${MIN_RETAIN_BLOCKS} ss-keep-recent=${SS_KEEP_RECENT}"
echo "    indexer=${INDEXER} gas-cap(sim)=${GAS_CAP}"
echo "Next: docker compose up -d"
