#!/usr/bin/env bash
#
# Create host datadirs (same paths as docker-compose bind mounts), Engine API jwt.hex,
# and download genesis.json + rollup.json for the selected Conduit network.
#
# Usage (from ronin/):
#   cp env.template .env
#   # Set RONIN_NETWORK / datadirs in .env if you do not use defaults.
#   ./init-datadirs.sh
#   ./init-datadirs.sh --force   # overwrite jwt, genesis, rollup
#
# Requires: openssl, curl, jq
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

expand_value() {
  local val="$1"
  val="${val%$'\r'}"
  val="${val#\"}"
  val="${val%\"}"
  val="${val//\$\{HOME\}/${HOME}}"
  val="${val//\$HOME/${HOME}}"
  printf '%s' "$val"
}

# Read KEY=value from .env without sourcing L1 placeholders like <YOUR_...> (break bash).
read_env_key() {
  local key="$1"
  local line
  [[ -f "$ENV_FILE" ]] || return 1
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n1)" || return 1
  line="${line#*${key}=}"
  line="${line#"${line%%[![:space:]]*}"}"
  expand_value "$line"
}

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
  esac
done

RONIN_NETWORK="$(read_env_key RONIN_NETWORK || true)"
RONIN_NETWORK="${RONIN_NETWORK:-ronin}"

RONIN_RETH_DATADIR="$(read_env_key RONIN_RETH_DATADIR || true)"
RONIN_RETH_DATADIR="${RONIN_RETH_DATADIR:-${HOME}/ronin-reth-datadir}"

RONIN_OP_NODE_DATADIR="$(read_env_key RONIN_OP_NODE_DATADIR || true)"
RONIN_OP_NODE_DATADIR="${RONIN_OP_NODE_DATADIR:-${HOME}/ronin-op-node-datadir}"

case "$RONIN_NETWORK" in
  ronin)
    GENESIS_URL="https://api.conduit.xyz/file/v1/optimism/genesis/ronin-mainnet-bfz9fadqzl"
    ROLLUP_URL="https://storage.googleapis.com/conduit-public-dls/ronin-rollup.json"
    ;;
  saigon)
    GENESIS_URL="https://api.conduit.xyz/file/v1/optimism/genesis/saigon-testnet-cc58e966ql"
    ROLLUP_URL="https://storage.googleapis.com/conduit-public-dls/saigon-rollup.json"
    ;;
  *)
    echo "ERROR: RONIN_NETWORK must be ronin or saigon (got: ${RONIN_NETWORK})" >&2
    exit 1
    ;;
esac

for bin in openssl curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: ${bin} is required but not found in PATH." >&2
    exit 1
  fi
done

# Conduit rollup.json from GCS has no alt_da; op-node --altda.enabled=true requires it or it exits with "no altDA config".
patch_rollup_alt_da() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  echo "Ensuring rollup alt_da block (required for op-node --altda.enabled)..."
  jq '.alt_da = {
    "da_commitment_type": "GenericCommitment",
    "da_challenge_contract_address": "0x0000000000000000000000000000000000000000",
    "da_challenge_window": 1,
    "da_resolve_window": 1
  }' "$path" > "${path}.tmp"
  mv "${path}.tmp" "$path"
}

mkdir -p "$RONIN_RETH_DATADIR" "$RONIN_OP_NODE_DATADIR"

JWT_PATH="${RONIN_RETH_DATADIR}/jwt.hex"
if [[ -f "$JWT_PATH" && "$FORCE" -eq 0 ]]; then
  echo "JWT exists (skip). Use --force to replace: $JWT_PATH"
else
  openssl rand -hex 32 > "$JWT_PATH"
  chmod 600 "$JWT_PATH"
  echo "Wrote JWT: $JWT_PATH"
fi

GENESIS_PATH="${RONIN_RETH_DATADIR}/genesis.json"
if [[ -f "$GENESIS_PATH" && "$FORCE" -eq 0 ]]; then
  echo "Genesis exists (skip). Use --force to re-download: $GENESIS_PATH"
else
  echo "Downloading genesis (${RONIN_NETWORK})..."
  curl -fL --retry 5 --retry-delay 5 "$GENESIS_URL" -o "$GENESIS_PATH"
  echo "Wrote $GENESIS_PATH"
fi

ROLLUP_PATH="${RONIN_OP_NODE_DATADIR}/rollup.json"
if [[ -f "$ROLLUP_PATH" && "$FORCE" -eq 0 ]]; then
  echo "Rollup config exists (skip download). Use --force to re-download: $ROLLUP_PATH"
else
  echo "Downloading rollup.json (${RONIN_NETWORK})..."
  curl -fL --retry 5 --retry-delay 5 "$ROLLUP_URL" -o "$ROLLUP_PATH"
  echo "Wrote $ROLLUP_PATH"
fi

patch_rollup_alt_da "$ROLLUP_PATH"

echo ""
echo "Done. Datadirs:"
echo "  reth:    $RONIN_RETH_DATADIR"
echo "  op-node: $RONIN_OP_NODE_DATADIR"
