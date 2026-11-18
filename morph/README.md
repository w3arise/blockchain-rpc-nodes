# Morph (morph-geth or morph-reth + morph-node)

Mainnet MPT full/archive node (post–L1 cutover). Chain data: `$HOME/morph-geth-data`, `$HOME/morph-node-data` (geth) or `$HOME/morph-reth-data`, `$HOME/morph-reth-node-data` (reth).

## Choose a client

`./configure.sh [mainnet|hoodi] [geth|reth]` (default `geth`) writes `COMPOSE_FILE` into `.env`: `docker-compose.yml` (morph-geth) or `docker-compose.reth.yml` (morph-reth). Both use the same host ports, so run one. To switch, run `docker compose down --remove-orphans` **before** re-running `configure.sh` (it refuses while a container of the other client exists). A geth datadir cannot be reused by reth: each client has its own datadirs and snapshot. Morph labels [morph-reth as internal testing, not yet recommended for production](https://github.com/morph-l2/run-morph-node#snapshot-information).

The steps below are for geth. morph-reth: [Reth](#reth).

## Start

```bash
./configure.sh
# edit .env — set L1_ETH_RPC and L1_ETH_BEACON_RPC
./init-database.sh
./create-jwt.sh
docker compose up -d
```

## Snapshot

Pick a snapshot from the [official snapshot table](https://github.com/morph-l2/run-morph-node#snapshot-information) ([snapshot.morph.network](https://snapshot.morph.network/)). Set `SNAPSHOT_NAME` and `L1_MSG_START_HEIGHT` in `.env` from the **same row**.

```bash
./configure.sh
# edit .env — L1 RPCs, SNAPSHOT_NAME, L1_MSG_START_HEIGHT
SNAP_NAME="$(grep -E '^SNAPSHOT_NAME=' .env | cut -d= -f2-)"
SNAP_TMP="${SNAPSHOT_TMPDIR:-$HOME/morph-snapshot-tmp}"
SNAP_URL="https://snapshot.morph.network/mainnet/${SNAP_NAME}.tar.gz"
mkdir -p "$SNAP_TMP" "$HOME/morph-geth-data" "$HOME/morph-node-data/data"
if command -v aria2c >/dev/null; then
  aria2c -c -x 8 -s 8 -d "$SNAP_TMP" -o "${SNAP_NAME}.tar.gz" "$SNAP_URL"
else
  curl -fL -C - -o "$SNAP_TMP/${SNAP_NAME}.tar.gz" "$SNAP_URL"
fi
tar -xzf "$SNAP_TMP/${SNAP_NAME}.tar.gz" -C "$SNAP_TMP"
mv "$SNAP_TMP/${SNAP_NAME}/geth" "$HOME/morph-geth-data/"
mv "$SNAP_TMP/${SNAP_NAME}/data/"* "$HOME/morph-node-data/data/"
./init-database.sh    # stages config/ into $HOME/morph-node-data/config
./create-jwt.sh
docker compose up -d
```

Keep `SNAPSHOT_TMPDIR` on the same volume as the datadirs so `mv` is a rename, not a copy. The downloaded archive stays in `$SNAP_TMP` (resumable); delete it yourself once the node is synced.

## Reth

morph-reth runs in **archive** mode (no `--full`, no `--prune.*`); RPC namespaces `web3,eth,txpool,net,morph`. Peers come from `static-nodes.json` (`--disable-discovery`), so only the TCP P2P port is published. Needs a reth snapshot (`snapshot-archive-reth-*` rows of the [official table](https://github.com/morph-l2/run-morph-node#snapshot-information)); `RETH_SNAPSHOT_NAME` and the three `RETH_*` heights in `.env` must come from the **same row**.

```bash
./configure.sh mainnet reth        # hoodi: ./configure.sh hoodi reth
# edit .env — L1_ETH_RPC, L1_ETH_BEACON_RPC (and RETH_* snapshot name/heights if you pick another row)
SNAP_NET=mainnet                   # or hoodi
RETH_DIR="$HOME/morph-reth-data"; RETH_NODE_DIR="$HOME/morph-reth-node-data"   # hoodi: morph-hoodi-reth-data, morph-hoodi-reth-node-data
SNAP_NAME="$(grep -E '^RETH_SNAPSHOT_NAME=' .env | cut -d= -f2-)"
SNAP_TMP="${SNAPSHOT_TMPDIR:-$HOME/morph-snapshot-tmp}"
SNAP_URL="https://snapshot.morph.network/${SNAP_NET}/${SNAP_NAME}.tar.gz"
mkdir -p "$SNAP_TMP" "$RETH_DIR" "$RETH_NODE_DIR/data"
if command -v aria2c >/dev/null; then
  aria2c -c -x 8 -s 8 -d "$SNAP_TMP" -o "${SNAP_NAME}.tar.gz" "$SNAP_URL"
else
  curl -fL -C - -o "$SNAP_TMP/${SNAP_NAME}.tar.gz" "$SNAP_URL"
fi
echo "$(curl -fsSL "${SNAP_URL}.sha256" | cut -d' ' -f1)  $SNAP_TMP/${SNAP_NAME}.tar.gz" | sha256sum -c -
tar -xzf "$SNAP_TMP/${SNAP_NAME}.tar.gz" -C "$SNAP_TMP"
mv "$SNAP_TMP/${SNAP_NAME}/reth-data/"* "$RETH_DIR/"
mv "$SNAP_TMP/${SNAP_NAME}/data/"* "$RETH_NODE_DIR/data/"
./init-database.sh ${SNAP_NET}     # adds node config and static-nodes.json; run before the chown
./create-jwt.sh
# morph-reth runs as a non-root user: find its IDs and own the datadir
RETH_IMAGE="$(grep -E '^RETH_IMAGE=' .env | cut -d= -f2-)"
docker run --rm --entrypoint id "$RETH_IMAGE"
sudo chown -R <UID>:<GID> "$RETH_DIR"
docker compose up -d
```

Same staging rules as the geth snapshot (`SNAPSHOT_TMPDIR` on the datadir volume, archive kept for you to delete). The snapshot is the supported bootstrap (the `RETH_*` heights are tied to its row); a genesis sync is untested.

After a restore, confirm history is present (a block from early in the chain, not the tip):

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockReceipts","params":["<EARLY_BLOCK_HEX>"],"id":1}' http://127.0.0.1:8441
```

`eth_getLogs` over a one-block range of the same block must return the same events.

## State retention

- **geth**: `GETH_GCMODE` in `.env`. `full` keeps all blocks, receipts and logs and prunes old state; `archive` keeps state too (much heavier). Both serve historical `eth_getLogs`.
- **reth**: archive keeps full receipts, logs and state. After an archive-snapshot restore start it with no prune flags (the entrypoint sets none); do not add `--full` (it prunes receipts/logs) or `--prune.*` on a restored datadir. Optional state-only pruning (offline) follows the Reth policy in [AGENTS.md](../AGENTS.md#reth--op-reth-state-pruning).

## Upgrade

Bump the **execution-client and node images together** (same-series pair in `env.template`: `GETH_IMAGE` or `RETH_IMAGE`, plus `NODE_IMAGE`). Copy the pin lines into `.env`, then `docker compose pull && docker compose up -d`. See the matching [morph](https://github.com/morph-l2/morph/releases), [go-ethereum](https://github.com/morph-l2/go-ethereum/releases) and [morph-reth](https://github.com/morph-l2/morph-reth/releases) release notes before changing pins on a synced datadir. Tag-only hosts: `./scripts/apply-tag-only.sh morph` (one group for all three pins; compose follows `COMPOSE_FILE`, so only the active client is pulled and recreated).

## Testnet

```bash
./configure.sh hoodi
# edit .env — set L1_ETH_RPC and L1_ETH_BEACON_RPC (Ethereum Hoodi)
./init-database.sh hoodi
./create-jwt.sh
docker compose up -d
```

morph-reth on Hoodi: run `./configure.sh hoodi reth` and follow the [Reth](#reth) steps with `SNAP_NET=hoodi` (they include the `id` + `chown` step).

Uses separate datadirs (`$HOME/morph-hoodi-geth-data`, `$HOME/morph-hoodi-node-data`; reth: `$HOME/morph-hoodi-reth-data`, `$HOME/morph-hoodi-reth-node-data`) so mainnet data is untouched.

## Verify

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8441

curl -s http://127.0.0.1:12657/status | jq '.result.sync_info.catching_up'
```

## Host ports

When running a public replica, allow inbound P2P: `GETH_P2P_PORT` (morph-geth, default `10303`, TCP + UDP) or `RETH_P2P_PORT` (morph-reth, default `10303`, TCP only) and `NODE_P2P_PORT` (morph-node, default `10656`, TCP + UDP). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [run-morph-node](https://github.com/morph-l2/run-morph-node) · [morph-reth](https://github.com/morph-l2/morph-reth) · [Run full node (Docker)](https://docs.morph.network/docs/build-on-morph/developer-resources/node-operation/full-node/run-in-docker)
