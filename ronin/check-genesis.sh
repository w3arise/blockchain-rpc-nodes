#!/usr/bin/env bash
#
# Compare Ronin genesis.json (under RONIN_RETH_DATADIR) with Conduit and optionally update it.
#
# Usage (from ronin/):
#   cp env.template .env   # if needed
#   ./check-genesis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# shellcheck source=../scripts/check-conduit-genesis-lib.sh
source "${SCRIPT_DIR}/../scripts/check-conduit-genesis-lib.sh"

expand_value() {
  local val="$1"
  val="${val%$'\r'}"
  val="${val#\"}"
  val="${val%\"}"
  val="${val//\$\{HOME\}/${HOME}}"
  val="${val//\$HOME/${HOME}}"
  printf '%s' "$val"
}

read_env_key() {
  local key="$1"
  local line
  [[ -f "$ENV_FILE" ]] || return 1
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n1)" || return 1
  line="${line#*${key}=}"
  line="${line#"${line%%[![:space:]]*}"}"
  expand_value "$line"
}

RONIN_NETWORK="$(read_env_key RONIN_NETWORK || true)"
RONIN_NETWORK="${RONIN_NETWORK:-ronin}"

RONIN_RETH_DATADIR="$(read_env_key RONIN_RETH_DATADIR || true)"
RONIN_RETH_DATADIR="${RONIN_RETH_DATADIR:-${HOME}/ronin-reth-datadir}"

case "$RONIN_NETWORK" in
  ronin)
    CHECK_GENESIS_SLUG="ronin-mainnet-bfz9fadqzl"
    ;;
  saigon)
    CHECK_GENESIS_SLUG="saigon-testnet-cc58e966ql"
    ;;
  *)
    echo "ERROR: RONIN_NETWORK must be ronin or saigon (got: ${RONIN_NETWORK})" >&2
    exit 1
    ;;
esac

CHECK_GENESIS_LOCAL="${RONIN_RETH_DATADIR}/genesis.json"
CHECK_GENESIS_CHAIN_DIR="${SCRIPT_DIR}"

echo "Network: ${RONIN_NETWORK} (Conduit slug: ${CHECK_GENESIS_SLUG})"
echo "Local genesis: ${CHECK_GENESIS_LOCAL}"

run_check_conduit_genesis "$@"
