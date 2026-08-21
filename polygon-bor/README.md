# Polygon PoS (Bor)

Mainnet RPC node — **PBSS path** + **archive GC**: full transaction index, long log index, bounded state history. Chain data: `$HOME/polygon-bor-data`.

Bor needs a synced **Heimdall v2** REST API (`HEIMDALL_URL` in `.env`). This compose runs Bor only.

## Start

```bash
./configure.sh              # .env + EXT_IP; set HEIMDALL_URL if Heimdall is not on localhost
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
| `BOR_STATE_SCHEME=path` `BOR_GCMODE=archive` | **PBSS archive** | Full blocks; log index `HISTORY_LOGS` (0 = entire chain) | Last `HISTORY_STATE` blocks (`0` = unlimited) |
| `HISTORY_TRANSACTIONS=0` | Full tx index | `eth_getTransaction*` from genesis | — |

Official `bor-mainnet-archive` packages use **hash** scheme. Do not restore a hash snapshot onto this path datadir (or the reverse). Changing `HISTORY_STATE` on an existing path DB prunes older state.

## Testnet (Amoy)

In `.env`, set `CHAIN=amoy` and the Amoy `BOOTNODES` / `DISCOVERY_DNS` values commented in `env.template`. Point `HEIMDALL_URL` at a synced **Amoy** Heimdall v2 (`heimdallv2-80002`). Use a separate datadir (`HOST_DATADIR=$HOME/polygon-bor-amoy-data`) — `./configure.sh` refuses Amoy if the path is still `$HOME/polygon-bor-data`. If mainnet is already bound on this host, also shift `HTTP_PORT` / `WS_PORT` / `P2P_PORT`.

Amoy snapshots are listed on the same All4nodes / PublicNode pages (pick **amoy bor**, pebble+path). Docs suggest ~1 TB disk.

## Host ports

Host network. Inbound P2P: **30304** TCP+UDP. HTTP/WS: localhost **8745** / **8746** (`RPC_BIND_ADDR`).

Docs: [Full node (Docker)](https://docs.polygon.technology/pos/how-to/full-node/full-node-docker) · [0xPolygon/bor](https://github.com/0xPolygon/bor)
