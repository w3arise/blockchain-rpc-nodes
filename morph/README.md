# Morph (morph-geth + morph-node)

Mainnet MPT full/archive node (morph-geth + morph-node, post–L1 cutover). Chain data: `$HOME/morph-geth-data`, `$HOME/morph-node-data`.

## Start

```bash
./configure.sh
# edit .env — set L1_ETH_RPC and L1_ETH_BEACON_RPC
./init-database.sh
./create-jwt.sh
docker compose up -d
```

## Snapshot

Pick a snapshot from the [official snapshot table](https://github.com/morph-l2/run-morph-node#snapshot-information) ([snapshot.morphl2.io](https://snapshot.morphl2.io/)). Set `SNAPSHOT_NAME` and `L1_MSG_START_HEIGHT` in `.env` from the **same row**.

```bash
./configure.sh
# edit .env — L1 RPCs, SNAPSHOT_NAME, L1_MSG_START_HEIGHT
SNAP_NAME="$(grep -E '^SNAPSHOT_NAME=' .env | cut -d= -f2-)"
SNAP_TMP="${SNAPSHOT_TMPDIR:-$HOME/morph-snapshot-tmp}"
SNAP_URL="https://snapshot.morphl2.io/mainnet/${SNAP_NAME}.tar.gz"
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

## Upgrade

Bump **geth and node images together** (same-series pair in `env.template`). Copy both pin lines into `.env`, then `docker compose pull && docker compose up -d`. See the matching [morph](https://github.com/morph-l2/morph/releases) and [go-ethereum](https://github.com/morph-l2/go-ethereum/releases) release notes before changing pins on a synced datadir. Tag-only hosts: `./scripts/apply-tag-only.sh morph`.

## Testnet

```bash
./configure.sh hoodi
# edit .env — set L1_ETH_RPC and L1_ETH_BEACON_RPC (Ethereum Hoodi)
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
