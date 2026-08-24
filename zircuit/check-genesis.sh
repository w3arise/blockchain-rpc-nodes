#!/usr/bin/env bash
#
# Compare local Zircuit genesis.json with Conduit and optionally update it.
#
# Conduit publishes bedrockBlock: 0; this repo keeps bedrockBlock: 32956468 for
# historical RPC via zircuit-legacy + --rollup.historicalrpc (see README).
#
# Usage (from zircuit/):
#   ./check-genesis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/check-conduit-genesis-lib.sh
source "${SCRIPT_DIR}/../scripts/check-conduit-genesis-lib.sh"

ZIRCUIT_BEDROCK_BLOCK=32956468

check_genesis_patch_zircuit_remote() {
  local remote_file="$1"
  jq --argjson bedrock "$ZIRCUIT_BEDROCK_BLOCK" '.config.bedrockBlock = $bedrock' \
    "$remote_file" > "${remote_file}.patched"
  mv "${remote_file}.patched" "$remote_file"
  echo ""
  echo "Applied repo patch: config.bedrockBlock=${ZIRCUIT_BEDROCK_BLOCK}"
}

CHECK_GENESIS_SLUG="zircuit-mainnet"
CHECK_GENESIS_LOCAL="${SCRIPT_DIR}/config/genesis.json"
CHECK_GENESIS_CHAIN_DIR="${SCRIPT_DIR}"
CHECK_GENESIS_PATCH_REMOTE_CMD="check_genesis_patch_zircuit_remote"

run_check_conduit_genesis "$@"
