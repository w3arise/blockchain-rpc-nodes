#!/usr/bin/env bash
#
# Compare local BOB genesis.json with Conduit and optionally update it.
#
# Usage (from bob/):
#   ./check-genesis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/check-conduit-genesis-lib.sh
source "${SCRIPT_DIR}/../scripts/check-conduit-genesis-lib.sh"

CHECK_GENESIS_SLUG="bob-mainnet-0"
CHECK_GENESIS_LOCAL="${SCRIPT_DIR}/config/genesis.json"
CHECK_GENESIS_CHAIN_DIR="${SCRIPT_DIR}"

run_check_conduit_genesis "$@"
