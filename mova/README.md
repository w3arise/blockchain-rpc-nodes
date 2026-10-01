# Mova (movad)

Mainnet EVM RPC on chain ID **61901** (`movad` + `movacli`). Chain data: `$HOME/mova-data`.

Default mode: **syncable** — full blocks, receipts, and logs; app state pruned (last 100 states plus every 10,000th). Sync is from **genesis** on the creation binary.

Image: `movachain/movan-syncnode:v0.0.1` (linux/amd64). Commit `6f0cc05`. That is the only published tag, and live `web3_clientVersion` is `mova/0.0.1+6f0cc05`. Chain 61900 (`movachain/mainnet-syncnode`) is a different network.

## Start

```bash
./configure.sh            # .env + EXT_IP + BUILD_UID/GID
./init-database.sh        # movad init + genesis (chain_id 61901)
./patch-config.sh         # pruning, peers, gas cap, log caps
docker compose up -d
```

`patch-config.sh` is **idempotent**. It sets `pruning = "syncable"`, `indexer = "kv"`, the mainnet persistent peers, `logs_cap` / `block_range_cap = 100000`, and `rpc_gas_limit = 600000000`. Start uses `--home /data`.

The vendor image's supervisord passes `--pruning=nothing` (archive). This compose file overrides that with `PRUNING`.

RPC: `http://127.0.0.1:8545` · WS: `ws://127.0.0.1:8546`

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
| 8545 | localhost | EVM JSON-RPC HTTP (`movacli`) |
| 8546 | localhost | EVM JSON-RPC WS |
| 26657 | localhost | CometBFT RPC |
| 26656 | public TCP+UDP | P2P |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN access to RPC. Open inbound **26656/tcp** and **26656/udp** for peers. Shipped `config.toml` sets `pex = false` and `max_num_inbound_peers = 0`; the node dials the three `p2p.movan.movachain.com` peers.

Docs: [CryptoManufaktur-io/mova-docker](https://github.com/CryptoManufaktur-io/mova-docker) · [movachain/movan-syncnode](https://hub.docker.com/r/movachain/movan-syncnode) · [Explorer](https://scan.movan.movachain.com/)
