#!/usr/bin/env bash
#
# Generate a shared Engine API JWT and op-node P2P private key.
#
# Usage: ./create-jwt.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JWT_FILE="${SCRIPT_DIR}/config/jwt.hex"
P2P_KEY="${SCRIPT_DIR}/config/op-node-priv-key.txt"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "${JWT_FILE}")"
chmod a+rX "${SCRIPT_DIR}/config"

if [[ -f "${JWT_FILE}" ]]; then
  echo "JWT already exists at ${JWT_FILE} (skipping)"
else
  openssl rand -hex 32 > "${JWT_FILE}"
  chmod 644 "${JWT_FILE}"
  echo "Wrote Engine API JWT to ${JWT_FILE}"
fi

if [[ -f "${P2P_KEY}" ]]; then
  echo "op-node P2P key already exists at ${P2P_KEY} (skipping)"
else
  openssl rand -hex 32 > "${P2P_KEY}"
  chmod 644 "${P2P_KEY}"
  echo "Wrote op-node P2P key to ${P2P_KEY}"
fi
