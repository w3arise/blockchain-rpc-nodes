#!/usr/bin/env bash
#
# Stage Morph node and geth config into host datadirs.
#
# Skip when restoring a snapshot into $HOME/morph-geth-data and $HOME/morph-node-data.
#
# Usage:
#   ./init-database.sh            # mainnet (default)
#   ./init-database.sh hoodi      # Hoodi testnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

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
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

GETH_DATA_DIR="${GETH_DATADIR:-${HOME}/morph-geth-data}"
NODE_DATA_DIR="${NODE_DATADIR:-${HOME}/morph-node-data}"

for f in genesis.json config.toml static-nodes.json geth-genesis.json; do
  if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
    echo "ERROR: missing ${CONFIG_DIR}/${f} — run ./fetch-config.sh first" >&2
    exit 1
  fi
done

mkdir -p "${GETH_DATA_DIR}" "${NODE_DATA_DIR}/config" "${NODE_DATA_DIR}/data"

cp "${CONFIG_DIR}/genesis.json" "${NODE_DATA_DIR}/config/genesis.json"
cp "${CONFIG_DIR}/config.toml" "${NODE_DATA_DIR}/config/config.toml"
cp "${CONFIG_DIR}/geth-genesis.json" "${GETH_DATA_DIR}/genesis.json"
cp "${CONFIG_DIR}/static-nodes.json" "${GETH_DATA_DIR}/static-nodes.json"

if [[ -n "${EXT_IP:-}" && -n "${NODE_P2P_PORT:-}" ]]; then
  sed_inplace() {
    local expr="$1"
    local file="$2"
    local tmp
    tmp="$(mktemp)"
    sed -e "$expr" "$file" > "${tmp}"
    mv "${tmp}" "${file}"
  }
  sed_inplace "s|^external_address = .*|external_address = \"${EXT_IP}:${NODE_P2P_PORT}\"|" \
    "${NODE_DATA_DIR}/config/config.toml"
fi

if [[ ! -f "${NODE_DATA_DIR}/data/priv_validator_state.json" ]]; then
  printf '{\n  "height": "0",\n  "round": 0,\n  "step": 0\n}\n' \
    > "${NODE_DATA_DIR}/data/priv_validator_state.json"
fi

echo "Staged ${NETWORK} config:"
echo "  geth datadir: ${GETH_DATA_DIR}"
echo "  node datadir: ${NODE_DATA_DIR}"
echo ""
echo "Next: ./create-jwt.sh && docker compose up -d"
