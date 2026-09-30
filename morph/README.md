# Morph (morph-geth + morph-node)

Mainnet MPT full/archive node (morph-geth **2.2.6** + morph-node **0.6.3**, post–L1 cutover). Chain data: `$HOME/morph-geth-data`, `$HOME/morph-node-data`.

## Start

```bash
./configure.sh
# edit .env — set L1_ETH_RPC
./init-database.sh
./create-jwt.sh
docker compose up -d
```

## Snapshot

Download and extract a snapshot from [snapshot.morphl2.io](https://snapshot.morphl2.io/) (see [run-morph-node README](https://github.com/morph-l2/run-morph-node#snapshot-information)). Latest mainnet archive: `snapshot-archive-20260701-1`.

```bash
SNAP_TMP="${SNAPSHOT_TMPDIR:-$HOME/morph-snapshot-tmp}"
mkdir -p "$SNAP_TMP"
wget -O "$SNAP_TMP/morph-snapshot.tar.gz" \
  https://snapshot.morphl2.io/mainnet/snapshot-archive-20260701-1.tar.gz
tar -xzf "$SNAP_TMP/morph-snapshot.tar.gz" -C "$SNAP_TMP"
mv "$SNAP_TMP/snapshot-archive-20260701-1/geth" $HOME/morph-geth-data/
mkdir -p $HOME/morph-node-data/data
mv "$SNAP_TMP/snapshot-archive-20260701-1/data/"* $HOME/morph-node-data/data/
rm -rf "$SNAP_TMP"
./init-database.sh    # stages config/ into $HOME/morph-node-data/config
./create-jwt.sh
docker compose up -d
```

Set `L1_MSG_START_HEIGHT` in `.env` to match the snapshot table in the official README.

## Upgrade

Bump **geth and node images together** — node **v0.6.3** requires the L1 contract cutover and the companion geth **morph-v2.2.6** release. See [morph v0.6.3](https://github.com/morph-l2/morph/releases/tag/v0.6.3) and [go-ethereum morph-v2.2.6](https://github.com/morph-l2/go-ethereum/releases/tag/morph-v2.2.6) release notes before changing pins on a synced datadir.

## Testnet

```bash
./configure.sh hoodi
# edit .env — set L1_ETH_RPC (Ethereum Hoodi)
./init-database.sh hoodi
./create-jwt.sh
docker compose up -d
```

Uses separate datadirs (`$HOME/morph-hoodi-geth-data`, `$HOME/morph-hoodi-node-data`) so mainnet data is untouched.

## Verify

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8441

curl -s http://127.0.0.1:12657/status | jq '.result.sync_info.catching_up'
```

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `GETH_P2P_PORT` (morph-geth, default `10303`) and `NODE_P2P_PORT` (morph-node, default `10656`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [run-morph-node](https://github.com/morph-l2/run-morph-node) · [Run full node (Docker)](https://docs.morph.network/docs/build-on-morph/developer-resources/node-operation/full-node/run-in-docker)
