#!/usr/bin/env bash
#
# Configure Lens deployment: create .env from env.template if missing.
#
# Usage: ./configure.sh

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
  echo ".env already exists — not overwriting"
fi

needs_da_seed() {
  local value
  value="$(grep '^EN_DA_SECRETS_SEED_PHRASE=' "${ENV_FILE}" | cut -d= -f2- || true)"
  value="${value%\"}"
  value="${value#\"}"
  [[ -z "${value}" || "${value}" == "<GENERATE_OR_SET>" ]]
}

if needs_da_seed; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to generate EN_DA_SECRETS_SEED_PHRASE" >&2
    exit 1
  fi
  SEED_PHRASE="$("${SCRIPT_DIR}/generate-da-secrets.sh")"
  python3 - "${ENV_FILE}" "${SEED_PHRASE}" <<'PY'
import pathlib
import sys

env_path = pathlib.Path(sys.argv[1])
phrase = sys.argv[2]
lines = []
updated = False
for line in env_path.read_text().splitlines(keepends=True):
    if line.startswith("EN_DA_SECRETS_SEED_PHRASE="):
        lines.append(f'EN_DA_SECRETS_SEED_PHRASE="{phrase}"\n')
        updated = True
    else:
        lines.append(line)
if not updated:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(f'EN_DA_SECRETS_SEED_PHRASE="{phrase}"\n')
env_path.write_text("".join(lines))
PY
  echo "generated EN_DA_SECRETS_SEED_PHRASE in .env"
fi

validate_l1_rpc() {
  local value
  value="$(grep '^EN_ETH_CLIENT_URL=' "${ENV_FILE}" | cut -d= -f2- || true)"
  value="${value%\"}"
  value="${value#\"}"

  if [[ -z "${value}" || "${value}" == "<YOUR_L1_ETH_RPC>" ]]; then
    echo "ERROR: set EN_ETH_CLIENT_URL in .env to a reachable Ethereum mainnet JSON-RPC URL" >&2
    echo "       Example: https://ethereum-rpc.publicnode.com" >&2
    echo "       If your L1 node runs on the host, use host.docker.internal (not 127.0.0.1)." >&2
    exit 1
  fi

  if [[ ! "${value}" =~ ^https?:// ]]; then
    echo "ERROR: EN_ETH_CLIENT_URL must start with http:// or https://" >&2
    exit 1
  fi
}

validate_l1_rpc

echo ""
echo "Next:"
echo "  edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD"
echo "  docker compose up -d"
echo ""
echo "RPC: http://127.0.0.1:\${EN_HTTP_PORT:-3160}  WS: ws://127.0.0.1:\${EN_WS_PORT:-3161}"
