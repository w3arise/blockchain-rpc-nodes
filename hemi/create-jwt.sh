#!/usr/bin/env bash
#
# Generate Engine API JWT and op-node P2P private key for Hemi.
#
# Usage: ./create-jwt.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JWT_FILE="${SCRIPT_DIR}/jwt.hex"
OP_NODE_KEY="${SCRIPT_DIR}/op-node-priv-key.txt"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

if [[ -f "${JWT_FILE}" ]]; then
  echo "JWT already exists at ${JWT_FILE} (skipping)"
else
  openssl rand -hex 32 > "${JWT_FILE}"
  chmod 644 "${JWT_FILE}"
  echo "Wrote Engine API JWT to ${JWT_FILE}"
fi

if [[ -f "${OP_NODE_KEY}" ]]; then
  echo "op-node key already exists at ${OP_NODE_KEY} (skipping)"
else
  openssl rand -hex 32 > "${OP_NODE_KEY}"
  chmod 644 "${OP_NODE_KEY}"
  echo "Wrote op-node P2P key to ${OP_NODE_KEY}"
fi
