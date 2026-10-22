#!/usr/bin/env bash
#
# Create .env from env.template, mkdir datadirs, render config/l1dtl.env + l2geth.env.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"

env_var_ok() {
  local val="${1-}"
  [[ -n "${val}" && "${val}" != "<YOUR_"* && "${val}" != "<MINIO_"* ]]
}

collect_missing_env() {
  MISSING_ENV=()
  env_var_ok "${L1_ETH_RPC:-}" || MISSING_ENV+=("L1_ETH_RPC")
  env_var_ok "${L1_BEACON:-}" || MISSING_ENV+=("L1_BEACON")
}

render_service_env() {
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a

  collect_missing_env
  if ((${#MISSING_ENV[@]} > 0)); then
    echo "ERROR: .env is missing: ${MISSING_ENV[*]}" >&2
    return 1
  fi

  if ! command -v envsubst >/dev/null 2>&1; then
    echo "ERROR: envsubst not found (install gettext-base)" >&2
    return 1
  fi

  mkdir -p "${SCRIPT_DIR}/config"
  envsubst < "${SCRIPT_DIR}/config/l1dtl.env.template" > "${SCRIPT_DIR}/config/l1dtl.env"
  envsubst < "${SCRIPT_DIR}/config/l2geth.env.template" > "${SCRIPT_DIR}/config/l2geth.env"
  echo "wrote config/l1dtl.env and config/l2geth.env"
}

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

mkdir -p "${HOST_DTL_DATADIR:-$HOME/metis-l1dtl-data}"
mkdir -p "${HOST_L2GETH_DATADIR:-$HOME/metis-l2geth-data}"

collect_missing_env
if ((${#MISSING_ENV[@]} > 0)); then
  echo ""
  echo ".env still needs values for:"
  for key in "${MISSING_ENV[@]}"; do
    case "${key}" in
      L1_ETH_RPC) echo "  - L1_ETH_RPC   (Ethereum mainnet execution JSON-RPC)" ;;
      L1_BEACON) echo "  - L1_BEACON    (Ethereum beacon / consensus HTTP API)" ;;
      *) echo "  - ${key}" ;;
    esac
  done
  echo ""
  echo "Set those in .env, then run ./configure.sh again."
  echo "That pass renders config/l1dtl.env (DTL) and config/l2geth.env (l2geth) for docker compose."
  exit 0
fi

render_service_env

echo ""
echo "Rendered config/l1dtl.env and config/l2geth.env from .env."
echo "If you change .env later, run ./configure.sh again before docker compose up or recreate."
echo ""
echo "Next:"
echo "  ./restore-snapshot.sh   # if datadirs are empty"
echo "  docker compose up -d"
