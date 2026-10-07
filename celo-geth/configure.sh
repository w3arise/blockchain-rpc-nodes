#!/usr/bin/env bash
#
# Configure the frozen Celo op-geth replica: create .env, add keys that are
# new in env.template, and check that the datadir already holds chain data.
# There is no P2P, so no public IP is set. Nothing is downloaded or synced.
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
else
  # Append keys missing from an older .env. Existing values are kept.
  while IFS= read -r line; do
    name="${line%%=*}"
    if ! grep -qE "^${name}=" "${ENV_FILE}"; then
      printf '%s\n' "${line}" >> "${ENV_FILE}"
      echo "added ${name} to .env"
    fi
  done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "${ENV_TEMPLATE}")
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

# Same default as docker-compose.yml.
DATA_DIR="${HOST_DATADIR:-${HOME}/celo-op-geth-data}"
if [[ -z "$(ls -A "${DATA_DIR}" 2>/dev/null)" ]]; then
  echo "ERROR: datadir ${DATA_DIR} is missing or empty." >&2
  echo "This replica only serves an existing migrated mainnet op-geth datadir." >&2
  exit 1
fi

echo ""
echo "datadir: ${DATA_DIR}"
echo "Next:"
echo "  docker compose up -d --remove-orphans"
