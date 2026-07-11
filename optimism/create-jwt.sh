#!/usr/bin/env bash
#
# Generate a shared Engine API JWT for op-reth (jwt.hex) and op-node (jwt-secret).
# Paths are under $HOME to match a typical bind-mount layout.
#
# Usage: ./create-jwt.sh

set -euo pipefail

RETH_JWT="${HOME}/op-reth-datadir/jwt.hex"
NODE_JWT="${HOME}/op-node-datadir/jwt-secret"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "${RETH_JWT}")" "$(dirname "${NODE_JWT}")"

SECRET="$(openssl rand -hex 32)"
printf '%s' "${SECRET}" > "${RETH_JWT}"
printf '%s' "${SECRET}" > "${NODE_JWT}"
chmod 600 "${RETH_JWT}" "${NODE_JWT}"

echo "Wrote Engine API JWT (hex, no 0x prefix) to:"
echo "  ${RETH_JWT}"
echo "  ${NODE_JWT}"
