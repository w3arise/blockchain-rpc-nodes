#!/usr/bin/env bash
#
# Generate a shared Engine API JWT for op-geth and op-node.
#
# Usage: ./create-jwt.sh

set -euo pipefail

JWT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jwt.txt"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH." >&2
  exit 1
fi

openssl rand -hex 32 > "${JWT_FILE}"
# Container processes often run as non-root and need to read the bind-mounted JWT.
chmod 644 "${JWT_FILE}"

echo "Wrote Engine API JWT to ${JWT_FILE}"
