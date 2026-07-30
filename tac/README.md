# Tac (tacchaind)

Mainnet CosmoseVM / Ethermint L1 RPC (`tacchain_239-1`). Chain data: `$HOME/tac-data`.

Default mode: **full** (`pruning=default`) — full block history for receipts/logs; app state pruned. Official HW: 8 CPU / 16 GB RAM (RPC) / 500 GB NVMe.

## Start

```bash
./configure.sh            # .env + EXT_IP + BUILD_UID/GID for the image
docker compose build      # image runs as your host user
./init-database.sh        # tacchaind init + genesis
./restore-snapshot.sh     # Ankr full (preferred); skip for genesis/P2P sync
./patch-config.sh         # config.toml + app.toml
docker compose up -d
```

`patch-config.sh` is **idempotent**. It sets `pruning = "default"`, `indexer = "kv"`, `minimum-gas-prices = "25000000000utac"`, `logs-cap` / `block-range-cap = 100000`, and `gas-cap = 600000000`. Start uses `--home /data` and `--json-rpc.enable`.

RPC: `http://127.0.0.1:8545` · WS: `ws://127.0.0.1:8546`

## Snapshot

Prefer official Ankr **full**, then **archive**. Staging uses `$HOME/tac-snapshot-tmp` (not `/tmp`).

```bash
./configure.sh
docker compose build
./init-database.sh
./restore-snapshot.sh              # SNAPSHOT_TYPE=full (default)
# SNAPSHOT_TYPE=archive ./restore-snapshot.sh   # full state history
./patch-config.sh                  # for archive: set PRUNING=nothing in .env first
docker compose up -d
```

| Source | Type | Notes |
| --- | --- | --- |
| Ankr `tac-mainnet-full-latest` | full (default) | Block history; matches `PRUNING=default` |
| Ankr `tac-mainnet-archive-latest` | archive | Full state; use `PRUNING=nothing` |
| [Polkachu](https://www.polkachu.com/tendermint_snapshots/tacchain) | pruned tip | Last resort (`pruning-keep-recent≈100`, often `indexer=null`) |

Skip `./init-database.sh` wipe after restore; keep `config/` + genesis.

## Pruning Mode

| `pruning` | Role |
| --- | --- |
| `default` (this setup) | Full RPC — blocks/receipts/logs; state pruned |
| `nothing` | Archive — full state history |
| `everything` / heavy custom | Validator-style tip — avoid for historical log RPC |

Match snapshot type to `PRUNING`. Do not switch an archive datadir to `default` unless you intend to discard state history.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 8545 | localhost | EVM JSON-RPC HTTP |
| 8546 | localhost | EVM JSON-RPC WS |
| 26657 | localhost | Tendermint RPC |
| 1317 | localhost | Cosmos REST API |
| 9090 | localhost | gRPC |
| 26656 | public TCP+UDP | CometBFT P2P |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN access to RPC. Open inbound **26656/tcp** and **26656/udp** for peers.

Docs: [NETWORKS.md](https://github.com/TacBuild/tacchain/blob/main/NETWORKS.md) · [TacBuild/tacchain](https://github.com/TacBuild/tacchain) · [docs.tac.build](https://docs.tac.build/)
