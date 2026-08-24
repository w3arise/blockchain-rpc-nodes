#!/usr/bin/env bash
#
# Compare local Katana genesis.json with Conduit and optionally update it.
#
# Usage (from katana/):
#   ./check-genesis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/check-conduit-genesis-lib.sh
source "${SCRIPT_DIR}/../scripts/check-conduit-genesis-lib.sh"

CHECK_GENESIS_SLUG="katana"
CHECK_GENESIS_LOCAL="${SCRIPT_DIR}/config/genesis.json"
CHECK_GENESIS_CHAIN_DIR="${SCRIPT_DIR}"

run_check_conduit_genesis "$@"
