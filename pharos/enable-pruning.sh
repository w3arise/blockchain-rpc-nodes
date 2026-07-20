#!/usr/bin/env bash
#
# Enable Pharos auto state pruning (block/receipt history retained for getLogs).
#
# Run after the node has synced. Official docs:
# https://docs.pharos.xyz/enable-pruning-in-pharos-node
#
# Usage: ./enable-pruning.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

docker compose exec pharos sh -c \
  'cd /data/bin && LD_PRELOAD=./libevmone.so ./pharos_cli prune --c ../pharos.conf --enable_auto_prune'

echo ""
echo "Current pruning settings:"
docker compose exec pharos sh -c \
  'cd /data/bin && LD_PRELOAD=./libevmone.so ./pharos_cli prune --c ../pharos.conf --get'
