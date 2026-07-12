#!/usr/bin/env bash
#
# Generate a shared Engine API JWT for bera-reth and beacon-kit.
#
# Usage: ./create-jwt.sh

set -euo pipefail

JWT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config/jwt.hex"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "${JWT_FILE}")"

openssl rand -hex 32 > "${JWT_FILE}"
chmod 600 "${JWT_FILE}"

echo "Wrote Engine API JWT to ${JWT_FILE}"
