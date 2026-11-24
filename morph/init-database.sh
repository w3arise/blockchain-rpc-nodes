#!/usr/bin/env bash
#
# Stage Morph node and execution-client config into host datadirs.
# The client (geth or reth) comes from COMPOSE_FILE in .env (see configure.sh).
#
# Run it after a snapshot restore too: it adds the config files the snapshot lacks.
#
# Usage:
#   ./init-database.sh            # mainnet (default)
#   ./init-database.sh hoodi      # Hoodi testnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
# shellcheck source-path=SCRIPTDIR source=client-lib.sh
source "${SCRIPT_DIR}/client-lib.sh"

NETWORK="${1:-mainnet}"
case "${NETWORK}" in
  mainnet)
    CONFIG_DIR="${SCRIPT_DIR}/config"
    ;;
  hoodi)
    CONFIG_DIR="${SCRIPT_DIR}/config/hoodi"
    ;;
  *)
    echo "ERROR: unknown network: ${NETWORK} (use mainnet|hoodi)" >&2
    exit 1
    ;;
esac

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

CLIENT="$(client_from_env "${ENV_FILE}")"
if [[ "${CLIENT}" == "reth" ]]; then
  EL_DATA_DIR="${RETH_DATADIR:-${HOME}/morph-reth-data}"
  NODE_DATA_DIR="${RETH_NODE_DATADIR:-${HOME}/morph-reth-node-data}"
else
  EL_DATA_DIR="${GETH_DATADIR:-${HOME}/morph-geth-data}"
  NODE_DATA_DIR="${NODE_DATADIR:-${HOME}/morph-node-data}"
fi

for f in genesis.json config.toml static-nodes.json geth-genesis.json; do
  if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
    echo "ERROR: missing ${CONFIG_DIR}/${f} — run ./fetch-config.sh first" >&2
    exit 1
  fi
done

mkdir -p "${EL_DATA_DIR}" "${NODE_DATA_DIR}/config" "${NODE_DATA_DIR}/data"

# stage_file SRC DST: copy unless DST is already identical; a datadir chowned to a
# container user is not writable here, so fail with a hint instead of a raw abort.
stage_file() {
  local src="$1" dst="$2"
  if [[ -f "${dst}" ]] && cmp -s "${src}" "${dst}"; then
    return 0
  fi
  if ! cp "${src}" "${dst}" 2>/dev/null; then
    echo "ERROR: cannot write ${dst} (datadir owned by another user?)." >&2
    echo "Re-run with sudo, or: sudo chown -R \"\$(id -u):\$(id -g)\" \"$(dirname "${dst}")\" and chown it back afterwards." >&2
    exit 1
  fi
  chmod 644 "${dst}"  # bind-mounted into containers that run as non-root users
}

stage_file "${CONFIG_DIR}/genesis.json" "${NODE_DATA_DIR}/config/genesis.json"
stage_file "${CONFIG_DIR}/config.toml" "${NODE_DATA_DIR}/config/config.toml"
stage_file "${CONFIG_DIR}/static-nodes.json" "${EL_DATA_DIR}/static-nodes.json"
if [[ "${CLIENT}" == "geth" ]]; then
  stage_file "${CONFIG_DIR}/geth-genesis.json" "${EL_DATA_DIR}/genesis.json"  # reth has the chain spec built in
fi

if [[ -n "${EXT_IP:-}" && -n "${NODE_P2P_PORT:-}" ]]; then
  sed_inplace "s|^external_address = .*|external_address = \"${EXT_IP}:${NODE_P2P_PORT}\"|" \
    "${NODE_DATA_DIR}/config/config.toml"
fi

if [[ ! -f "${NODE_DATA_DIR}/data/priv_validator_state.json" ]]; then
  printf '{\n  "height": "0",\n  "round": 0,\n  "step": 0\n}\n' \
    > "${NODE_DATA_DIR}/data/priv_validator_state.json"
fi

echo "Staged ${NETWORK} config:"
echo "  ${CLIENT} datadir: ${EL_DATA_DIR}"
echo "  node datadir: ${NODE_DATA_DIR}"
echo ""
echo "Next: ./create-jwt.sh && docker compose up -d"
