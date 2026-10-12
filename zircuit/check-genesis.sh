#!/usr/bin/env bash
#
# Compare local Zircuit genesis.json with the published Conduit file.
#
# Historical RPC cutoff is --rollup.historicalrpc.block in docker-compose.yml.
# Keep the published genesis (bedrockBlock: 0, conduit.migrationBlock).
#
# Usage (from zircuit/):
#   ./check-genesis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib/check-conduit-genesis-lib.sh
source "${SCRIPT_DIR}/../scripts/lib/check-conduit-genesis-lib.sh"

CHECK_GENESIS_SLUG="zircuit-mainnet"
CHECK_GENESIS_LOCAL="${SCRIPT_DIR}/config/genesis.json"
CHECK_GENESIS_CHAIN_DIR="${SCRIPT_DIR}"

run_check_conduit_genesis "$@"
