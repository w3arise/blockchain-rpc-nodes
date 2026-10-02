#!/usr/bin/env bash
#
# Create .env, set EXT_IP, fetch mainnet genesis, generate a PFN identity,
# and render gravity_node config. Archive receipts/logs, with account and
# storage history pruned (same idea as celo/scripts/start-op-reth.sh).
#
# Usage: ./configure.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
CONFIG_DIR="${SCRIPT_DIR}/config"

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

# chmod fails with "Operation not permitted" when Docker created the file as
# root. Do not abort; print the sudo command and continue.
chmod_or_sudo() {
  local mode="$1"
  shift
  local path
  if chmod "${mode}" "$@" 2>/dev/null; then
    return 0
  fi
  echo "WARNING: chmod ${mode} failed (not permitted)." >&2
  echo "Run manually:" >&2
  for path in "$@"; do
    echo "  sudo chmod ${mode} \"${path}\"" >&2
  done
}

if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

# Replace the placeholder before sourcing. An unquoted EXT_IP=<YOUR_PUBLIC_IP>
# is a redirect and makes `source .env` fail. Existing .env files from the
# first template copy still have that line.
PUBLIC_IP="$(curl -4 -sf ip.me | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: failed to fetch public IP from ip.me" >&2
  exit 1
fi

CURRENT_EXT_IP="$(grep -E '^EXT_IP=' "${ENV_FILE}" | cut -d= -f2- || true)"
CURRENT_EXT_IP="${CURRENT_EXT_IP%\"}"
CURRENT_EXT_IP="${CURRENT_EXT_IP#\"}"
if [[ "${CURRENT_EXT_IP}" != "${PUBLIC_IP}" ]]; then
  sed_inplace "s|^EXT_IP=.*|EXT_IP=${PUBLIC_IP}|" "${ENV_FILE}"
  echo "set EXT_IP=${PUBLIC_IP} in .env"
else
  echo "EXT_IP already set to ${PUBLIC_IP}"
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

if [[ "${NODE_TYPE:-archive}" != "archive" ]]; then
  echo "ERROR: NODE_TYPE=${NODE_TYPE} is not supported." >&2
  echo "       archive keeps receipts and logs and prunes only account/storage history." >&2
  echo "       gravity-reth --full also prunes receipts to ~10064 blocks." >&2
  exit 1
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/gravity-data}"
LOG_DIR="${HOST_LOGDIR:-${HOME}/gravity-logs}"
mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${CONFIG_DIR}"

SDK_REF="${GRAVITY_SDK_REF:-v1.9.3}"
GENESIS_URL="https://raw.githubusercontent.com/Galxe/gravity-sdk/${SDK_REF}/genesis/mainnet/genesis.json"
WAYPOINT_URL="https://raw.githubusercontent.com/Galxe/gravity-sdk/${SDK_REF}/genesis/mainnet/waypoint.txt"

echo "==> Fetching mainnet genesis and waypoint (${SDK_REF})"
curl -fsSL "${GENESIS_URL}" -o "${CONFIG_DIR}/genesis.json"
curl -fsSL "${WAYPOINT_URL}" -o "${CONFIG_DIR}/waypoint.txt"
chmod_or_sudo 644 "${CONFIG_DIR}/genesis.json" "${CONFIG_DIR}/waypoint.txt"

if [[ ! -s "${CONFIG_DIR}/identity.yaml" ]]; then
  echo "==> Generating PFN identity (stays on this host; not committed)"
  docker run --rm --user root --entrypoint gravity_cli \
    -v "${CONFIG_DIR}:/out" \
    "${GRAVITY_IMAGE:?GRAVITY_IMAGE must be set in .env}" \
    genesis generate-key \
      --output-file /out/identity.yaml \
      --public-output-file /out/identity.public.yaml
  chmod_or_sudo 600 "${CONFIG_DIR}/identity.yaml"
else
  echo "identity.yaml already present; leaving it"
fi

export CONFIG_DIR DATA_DIR
python3 - << 'PY'
import json, os
from pathlib import Path

cfg = Path(os.environ["CONFIG_DIR"])
e = os.environ

def req(name):
    val = e.get(name, "")
    if val == "":
        raise SystemExit(f"ERROR: {name} is empty in .env")
    return val

account = int(req("PRUNE_ACCOUNT_HISTORY_DISTANCE"))
storage = int(req("PRUNE_STORAGE_HISTORY_DISTANCE"))
if account < 10064 or storage < 10064:
    raise SystemExit(
        "ERROR: account/storage history distance must be >= 10064 "
        "(gravity-reth MINIMUM_UNWIND_SAFE_DISTANCE)"
    )

# No --full / --minimal: Reth's default prune profile is archive (receipts
# and logs kept). The two distance flags prune account and storage history only.
reth = {
    "reth_args": {
        "chain": "/gravity/config/genesis.json",
        "prune.account-history.distance": account,
        "prune.storage-history.distance": storage,
        "http": "",
        "http.port": int(req("HTTP_PORT")),
        "http.corsdomain": "*",
        "http.api": req("HTTP_API"),
        "http.addr": req("RPC_BIND_ADDR"),
        "ws": "",
        "ws.port": int(req("WS_PORT")),
        "ws.origins": "*",
        "ws.api": "debug,eth,net,txpool,web3",
        "ws.addr": req("RPC_BIND_ADDR"),
        "rpc.gascap": int(req("GAS_CAP")),
        "port": int(req("RETH_P2P_PORT")),
        "authrpc.port": int(req("AUTHRPC_PORT")),
        "authrpc.addr": "127.0.0.1",
        "metrics": f"{req('METRICS_BIND_ADDR')}:{req('METRICS_PORT')}",
        "log.file.filter": "info",
        "log.stdout.filter": "error",
        "datadir": "/gravity/data/data/reth",
        "datadir.static-files": "/gravity/data/data/reth",
        "gravity_node_config": "/gravity/config/public_full_node.yaml",
        "log.file.directory": "/gravity/logs/execution_logs/",
        "rpc.max-subscriptions-per-connection": 20000,
        "rpc.max-connections": 20000,
        "txpool.max-new-pending-txs-notifications": 1000000,
        "txpool.max-pending-txns": 1000000,
        "txpool.pending-max-count": 200000,
        "txpool.pending-max-size": 512,
        "txpool.basefee-max-count": 200000,
        "txpool.basefee-max-size": 512,
        "txpool.queued-max-count": 100000,
        "txpool.queued-max-size": 256,
        "txpool.max-account-slots": int(req("TXPOOL_MAX_ACCOUNT_SLOTS")),
        "ipcdisable": "",
    },
    "env_vars": {"BATCH_INSERT_TIME": 20},
}
(cfg / "reth_config.json").write_text(json.dumps(reth, indent=2) + "\n")

public_port = req("PUBLIC_PORT")
inspection = req("INSPECTION_PORT")
yaml = f"""base:
  role: "full_node"
  data_dir: "/gravity/data/data"
  waypoint:
    from_file: "/gravity/config/waypoint.txt"

consensus:
  safety_rules:
    backend:
      type: "on_disk_storage"
      path: /gravity/data/data/secure_storage.json
      initial_safety_rules_config:
        from_file:
          waypoint:
            from_file: /gravity/config/waypoint.txt
          identity_blob_path: /gravity/config/identity.yaml
  enable_pipeline: true
  max_sending_block_txns_after_filtering: 5000
  max_sending_block_txns: 5000
  max_receiving_block_txns: 5000
  max_sending_block_bytes: 31457280
  max_receiving_block_bytes: 31457280
  quorum_store:
    receiver_max_total_txns: 7000
    sender_max_total_txns: 7000
    receiver_max_batch_bytes: 1048736
    sender_max_batch_bytes: 1048736
    sender_max_total_bytes: 1073741824
    receiver_max_total_bytes: 1073741824
    memory_quota: 1073741824
    db_quota: 1073741824
    back_pressure:
      dynamic_max_txn_per_s: 30000
      backlog_txn_limit_count: 50000
      backlog_per_validator_batch_limit_count: 2000

full_node_networks:
  - network_id: public
    listen_address: "/ip4/0.0.0.0/tcp/{public_port}"
    identity:
      type: "from_file"
      path: /gravity/config/identity.yaml
    seeds:
      "0x38013b46c21388c3fd08ab32b86b478b3109125566d63c2da8fdc941dc474077":
        addresses:
          - "/dns/mainnet-rpc-p2p-1.gravity.xyz/tcp/6180/noise-ik/234aee14677a3d2198208ea72ca5e95ed75520df27f01f0c36220303ff78642f/handshake/0"
        role: PreferredUpstream
      "0x2d30cf69303d40e0efcdb0f3a6545d43b055e86729287f2f1328c001caeb2be4":
        addresses:
          - "/dns/mainnet-rpc-p2p-3.gravity.xyz/tcp/6180/noise-ik/0a71ef75482f617203f64b0d5e9e3a66361b5f35e9d709ef873c494cd76d2365/handshake/0"
        role: PreferredUpstream

storage:
  dir: "/gravity/data/data"

log_file_path: "/gravity/logs/consensus_log/vfn.log"

inspection_service:
  port: {inspection}
  address: 127.0.0.1

mempool:
  capacity_per_user: 20000

logger:
  level: INFO
"""
(cfg / "public_full_node.yaml").write_text(yaml)
print(f"rendered {cfg / 'reth_config.json'}")
print(f"rendered {cfg / 'public_full_node.yaml'}")
PY

chmod_or_sudo 644 "${CONFIG_DIR}/reth_config.json" "${CONFIG_DIR}/public_full_node.yaml" "${CONFIG_DIR}/waypoint.txt"

echo ""
echo "Datadir: ${DATA_DIR}"
echo "Logs:    ${LOG_DIR}"
echo ""
echo "The container runs as uid 10001. Before the first start:"
echo "  sudo chown -R 10001:10001 \"${DATA_DIR}\" \"${LOG_DIR}\" \"${CONFIG_DIR}\""
echo "  sudo chmod 600 \"${CONFIG_DIR}/identity.yaml\""
echo ""
echo "Next:"
echo "  ./restore-snapshot.sh"
echo "  docker compose up -d"
