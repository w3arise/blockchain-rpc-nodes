# Mova (movad)

Mainnet EVM RPC on chain ID **61901** (`movad` + `movacli`). Chain data: `$HOME/mova-data`.

Default mode: **syncable** — full blocks, receipts, and logs; app state pruned (last 100 states plus every 10,000th). Sync is from **genesis** on the creation binary.

Image: `movachain/movan-syncnode:v0.0.1` (linux/amd64). Commit `6f0cc05`. That is the only published tag, and live `web3_clientVersion` is `mova/0.0.1+6f0cc05`.

**Not chain 61900** — `movachain/mainnet-syncnode`, `rpc.movachain.com`, and `node-snap.movachain.com` are a different network. There is no separate official node-run doc in this repo for 61901 beyond the published image, explorer, and snapshot host below.

## Start

```bash
./configure.sh            # .env + EXT_IP + BUILD_UID/GID
./init-database.sh        # movad init + chain 61901 genesis (checksum)
./patch-config.sh         # pruning, peers, packet size, gas cap, log caps
docker compose up -d
```

`movad init` writes **`config.toml`** and **`app.toml`**. Those files are kept (Tendermint/CometBFT standard). **`patch-config.sh`** is **idempotent** and edits them: `pruning = "syncable"`, `indexer = "kv"`, `persistent_peers`, P2P listen/advertise, `max_packet_msg_payload_size` (from `MAX_PACKET_MSG_PAYLOAD_SIZE`), `logs_cap` / `block_range_cap = 100000`, and `rpc_gas_limit = 600000000`. Init’s payload size is **1024**, which drops peers that send larger amino packets (`Read overflow`, maxSize 1047). **`pex`** and **`max_num_inbound_peers`** stay at init defaults unless you add them after testing.

Init’s local genesis is **replaced** with the chain 61901 genesis (downloaded at init, sha256-checked in `init-database.sh` — not committed; gentx memos can contain operator IPs). **`noderpc.toml`** is installed only when init did not create it (gas/log caps live there, not geth `--rpc.gascap`).

If patch fails on a **missing key**, `movad init` on v0.0.1 did not emit that key — add only the needed field after checking the generated file on **linux/amd64**, do not drop in a full copied config. Start uses `--home /data`.

The vendor image's supervisord passes `--pruning=nothing` (archive). This compose file overrides that with `PRUNING`.

RPC: `http://127.0.0.1:8545` · WS: `ws://127.0.0.1:8546`

Those host ports map to **movad** JSON-RPC inside the container (`9545` / `9546`). `movacli` still listens on `8545` / `8546` and is not published. Its `eth_getLogs` re-encodes the `latest` tag and the node returns `hex string without 0x prefix`. `earliest`, a hex block, and an omitted `toBlock` are unaffected. `safe` and `finalized` are rejected by this client on every method.

## Upgrade

Stop the stack, copy `MOVA_VERSION` from `env.template` into `.env`, `docker compose pull`, recreate.

Genesis sync has to use the binary the chain was created with. `v0.0.1` is that image. There are no upstream release notes naming a later genesis binary. Do not start a fresh datadir on a newer tag unless that tag's release notes say it can sync from height 0.

## Snapshot

This setup syncs from genesis. A daily tarball is published at [node-snap.movan.movachain.com/snapshot/](https://node-snap.movan.movachain.com/snapshot/) (`node-YYYYMMDD.tar.gz`, about 52 GiB). Do not unpack it into this datadir.

Do not use `node-snap.movachain.com` — that host is chain 61900.

## Pruning Mode

| `pruning` | Role |
| --- | --- |
| `syncable` (this setup) | Full RPC — blocks/receipts/logs; state pruned |
| `nothing` | Archive — full state history. The vendor image defaults to this |
| `everything` | Tip state only — avoid for historical log RPC |

`movad` refuses to change pruning on an initialized store. Set it before the first start. Do not switch an archive datadir to `syncable` unless you intend to discard state history.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 8545 | localhost | EVM JSON-RPC HTTP (container `9545`, movad) |
| 8546 | localhost | EVM JSON-RPC WS (container `9546`, movad) |
| 26657 | localhost | CometBFT RPC |
| 26656 | public TCP+UDP | P2P |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN access to RPC. Open inbound **26656/tcp** and **26656/udp** for peers. Persistent peers are patched from `PERSISTENT_PEERS` in `.env`.

## Health

`eth_syncing` may return an object with `currentBlock` even when the node is caught up. Prefer **block head advancing** / block time over `result === false` alone.

Docs: [movachain/movan-syncnode](https://hub.docker.com/r/movachain/movan-syncnode) · [Explorer](https://scan.movan.movachain.com/)
