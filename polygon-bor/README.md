# Polygon PoS (Bor)

Mainnet RPC node — **PBSS path** + **archive GC**: full transaction index, long log index, bounded state history. Chain data: `$HOME/polygon-bor-data`.

Bor needs a synced **Heimdall v2** REST API (`HEIMDALL_URL` in `.env`). This compose runs Bor only.

## Start

```bash
./configure.sh mainnet      # copies env.template.mainnet -> .env, sets EXT_IP
docker compose pull
docker compose up -d
```

Heimdall on this host: keep `HEIMDALL_URL=http://127.0.0.1:1317` (compose uses `network_mode: host`). Confirm `curl -s localhost:1317/bor/span/1` returns JSON before starting Bor.

## Snapshot

Community snapshots (match **pebble + path**; hash/leveldb dumps are incompatible):

- [All4nodes Polygon](https://all4nodes.io/Polygon)
- [PublicNode Polygon](https://publicnode.com/snapshots#polygon) (PBSS + PebbleDB listed as beta)
- [Official snapshot docs](https://docs.polygon.technology/pos/how-to/snapshots/)

Restore into `$HOME/polygon-bor-data`, then start as above. Plan **several TB** disk (docs suggest ~8 TB buffer for mainnet growth).

## Pruning Mode

| Flag | This setup | Receipts / logs | State |
| --- | --- | --- | --- |
| `BOR_STATE_SCHEME=path` `BOR_GCMODE=archive` | **PBSS archive** | Full blocks; log index `BOR_HISTORY_LOGS` (0 = entire chain) | Last `BOR_HISTORY_STATE` blocks (`0` = unlimited) |
| `BOR_HISTORY_TRANSACTIONS=0` | Full tx index | `eth_getTransaction*` from genesis | — |

Official `bor-mainnet-archive` packages use **hash** scheme. Do not restore a hash snapshot onto this path datadir (or the reverse). Changing `BOR_HISTORY_STATE` on an existing path DB prunes older state.

## Testnet (Amoy)

```bash
./configure.sh amoy
docker compose pull
docker compose up -d
```

This copies `env.template.amoy` to `.env`: container **`bor-amoy`**, project **`polygon-bor-amoy`**, `$HOME/polygon-bor-amoy-data`, ports **8755** / **8756** / **31304** (`RPC_BIND_ADDR=0.0.0.0`), `--cache=8192`, 12 CPU / 24G, `GAS_CAP=1000000000`, APIs **eth,net,web3,bor**, and `HEIMDALL_URL=https://heimdall-api-amoy.polygon.technology`.

Both can run on one host: different container name, compose project, datadir, and ports. Start mainnet, then `./configure.sh amoy && docker compose up -d` — that overwrites `.env` but leaves `bor` running. `docker compose down` only stops the project named in the current `.env`. To recreate mainnet, run `./configure.sh mainnet` first.

Amoy snapshots: [All4nodes](https://all4nodes.io/Polygon) / [PublicNode](https://publicnode.com/snapshots#polygon) — pick **amoy bor**, pebble+path. Docs suggest ~1 TB disk.

## Host ports

Host network. Mainnet P2P **30304** TCP+UDP, HTTP/WS **8745** / **8746** on all interfaces. Amoy: P2P **31304**, HTTP/WS **8755** / **8756** on all interfaces.

Docs: [Full node (Docker)](https://docs.polygon.technology/pos/how-to/full-node/full-node-docker) · [0xPolygon/bor](https://github.com/0xPolygon/bor)
