#!/usr/bin/env bash
# maru-genesis-checks.sh

EXPECTED_STATE_ROOT="0x0c52edaac4a3b6e7cc11ea21443a4b001f4d68e016817469827a0dff8b50409e"

echo "=== Checking Beacon Block 0 state_root ==="
STATE_ROOT=$(curl -s http://localhost:8088/eth/v2/beacon/blocks/0 | jq -r '.data.message.state_root')

if [[ -z "$STATE_ROOT" || "$STATE_ROOT" == "null" ]]; then
  echo "❌ Failed to retrieve state_root!"
  exit 1
fi

echo "Retrieved state_root: $STATE_ROOT"
echo "Expected state_root:  $EXPECTED_STATE_ROOT"

if [[ "$STATE_ROOT" == "$EXPECTED_STATE_ROOT" ]]; then
  echo "✅ State root matches expected value."
else
  echo "⚠️  State root does NOT match expected value!"
fi

echo
echo "=== Checking Node Health ==="
curl -s http://localhost:8088/eth/v1/node/health