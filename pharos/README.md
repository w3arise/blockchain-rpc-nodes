# Pharos (pharos_light)

Pacific Mainnet full node. Chain data: `$HOME/pharos-data`.

## Start

```bash
cp env.template .env
# set CONSENSUS_KEY_PWD in .env
./configure.sh
./init-database.sh
docker compose up -d
```

RPC: `http://127.0.0.1:18100` · WS: `ws://127.0.0.1:18200`

## Snapshot

Latest mainnet snapshot and checksum: [Pharos Network Snapshots](https://docs.pharos.xyz/node-and-validator-guide/pharos-network-snapshots).

```bash
cp env.template .env
# set CONSENSUS_KEY_PWD in .env
./configure.sh              # fetches genesis.conf + bin/VERSION; skip init-database.sh

set -a && source .env && set +a
DATA_DIR="${HOST_DATADIR:-$HOME/pharos-data}"

curl -LO "https://snapshot.dplabs-internal.com/mainnet/${SNAPSHOT_NAME}" -o "${DATA_DIR}/${SNAPSHOT_NAME}"
echo "${SNAPSHOT_SHA256}  ${DATA_DIR}/${SNAPSHOT_NAME}" | sha256sum -c -
tar -zxvf "${DATA_DIR}/${SNAPSHOT_NAME}" -C "${DATA_DIR}"

docker compose down
rm -rf "${DATA_DIR}/pharos-node/domain/light/data/public"
mv "${DATA_DIR}/pharos-node/domain/light/data/local_storage" \
  "${DATA_DIR}/pharos-node/domain/light/data/local_storage.bak" 2>/dev/null || true
mv "${DATA_DIR}/public" "${DATA_DIR}/pharos-node/domain/light/data/public"

docker compose up -d
```

Pin `SNAPSHOT_NAME` / `SNAPSHOT_SHA256` in `.env` to the snapshot you download.

## State retention

Pruning is **off** by default (`full.conf`). Pharos auto-prune removes old **state** data only; block and receipt data needed for `eth_getLogs` and block queries are retained.

After the node is synced:

```bash
./enable-pruning.sh
```

Historical state queries (`eth_getBalance`, `eth_getStorageAt`, etc.) outside the pruning window will fail. Do not enable auto-prune on a node you intend to run as a full archive for old state.

Docs: [Enable AutoPruning](https://docs.pharos.xyz/enable-pruning-in-pharos-node) · [Node Configuration](https://docs.pharos.xyz/node-and-validator-guide/validator-node-deployment/node-configuration)

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 18100 | localhost | HTTP JSON-RPC |
| 18200 | localhost | WebSocket |
| 20000 | localhost | Internal RPC |
| 19000 | localhost | P2P TCP |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN or public access to RPC or P2P.

Docs: [Using Docker](https://docs.pharos.xyz/node-and-validator-guide/validator-node-deployment/using-docker-deployment)
