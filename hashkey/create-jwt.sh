#!/usr/bin/env bash
#
# Generate a shared Engine API JWT for op-geth and op-node.
#
# Usage: ./create-jwt.sh

set -euo pipefail

JWT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config/jwt.hex"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "${JWT_FILE}")"

if [[ -f "${JWT_FILE}" ]]; then
  echo "JWT already exists at ${JWT_FILE} (skipping)"
  exit 0
fi

openssl rand -hex 32 > "${JWT_FILE}"
chmod 644 "${JWT_FILE}"

echo "Wrote Engine API JWT to ${JWT_FILE}"
