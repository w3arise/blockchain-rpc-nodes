#!/usr/bin/env bash
#
# Apply Cronos mainnet settings to config.toml and app.toml under the datadir.
#
# Idempotent — safe to re-run after snapshot restore, .env changes, or manual edits.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/cronos-data}"
P2P_PORT="${P2P_PORT:-26656}"
SEEDS="${SEEDS:-}"
PRUNING="${PRUNING:-default}"
MINIMUM_GAS_PRICES="${MINIMUM_GAS_PRICES:-1basecro}"
LOGS_CAP="${LOGS_CAP:-100000}"
BLOCK_RANGE_CAP="${BLOCK_RANGE_CAP:-100000}"
GAS_CAP="${GAS_CAP:-600000000}"

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

# Set a top-level TOML key to an exact value (idempotent).
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

# Set a key inside a TOML section, e.g. [p2p] or [json-rpc] (idempotent).
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
set_toml_key "${CONFIG_TOML}" "seeds" "\"${SEEDS}\""
set_toml_section_key "${CONFIG_TOML}" "p2p" "laddr" "\"tcp://0.0.0.0:${P2P_PORT}\""
set_toml_section_key "${CONFIG_TOML}" "rpc" "laddr" "\"tcp://0.0.0.0:26657\""

if [[ -n "${EXT_IP:-}" ]]; then
  set_toml_section_key "${CONFIG_TOML}" "p2p" "external_address" "\"${EXT_IP}:${P2P_PORT}\""
else
  set_toml_section_key "${CONFIG_TOML}" "p2p" "external_address" '""'
fi

echo "==> Patching app.toml"
set_toml_key "${APP_TOML}" "pruning" "\"${PRUNING}\""
set_toml_key "${APP_TOML}" "minimum-gas-prices" "\"${MINIMUM_GAS_PRICES}\""
set_toml_section_key "${APP_TOML}" "json-rpc" "logs-cap" "${LOGS_CAP}"
set_toml_section_key "${APP_TOML}" "json-rpc" "block-range-cap" "${BLOCK_RANGE_CAP}"
set_toml_section_key "${APP_TOML}" "json-rpc" "gas-cap" "${GAS_CAP}"
set_toml_section_key "${APP_TOML}" "json-rpc" "address" "\"0.0.0.0:8545\""
set_toml_section_key "${APP_TOML}" "json-rpc" "ws-address" "\"0.0.0.0:8546\""

echo ""
echo "==> Changes"
print_diff "config.toml" "${BACKUP_DIR}/config.toml" "${CONFIG_TOML}"
print_diff "app.toml" "${BACKUP_DIR}/app.toml" "${APP_TOML}"

echo ""
echo "==> Config patched"
echo "    datadir: ${DATA_DIR}"
echo "    pruning=${PRUNING} minimum-gas-prices=${MINIMUM_GAS_PRICES}"
echo "    logs-cap=${LOGS_CAP} block-range-cap=${BLOCK_RANGE_CAP} gas-cap=${GAS_CAP}"
echo "Next: docker compose up -d"
