# Sei (seid)

Mainnet historical RPC node (`pacific-1`, EVM chain ID 1329). **Option A:** full block + EVM receipt/log history going forward; state store pruned to recent ~100k versions. Chain data: `$HOME/sei-data`.

## Start

```bash
./configure.sh
./init-database.sh
./restore-snapshot.sh        # preferred — latest Polkachu snapshot
./patch-config.sh            # required after restore (min-retain-blocks=0)
docker compose up -d
```

RPC: `http://127.0.0.1:8545` · WS: `ws://127.0.0.1:8546`

## Snapshot

**Default (repo exception):** [Polkachu Sei snapshots](https://www.polkachu.com/tendermint_snapshots/sei). `./restore-snapshot.sh` resolves the latest download URL when `SNAPSHOT_URL` is unset.

Polkachu's snapshot server uses heavy app pruning (`pruning-keep-recent = 100`, `indexer = null`) — the restored datadir starts near chain tip, not from genesis. This repo accepts that tradeoff for Sei. `./patch-config.sh` sets `min-retain-blocks=0` after restore so blocks and receipts are retained from that point forward.

Other official providers: [Sei snapshot guide](https://docs.sei.io/node/snapshot) (Imperator, Stakeme, kjnodes). Set `SNAPSHOT_URL` in `.env` to override.

```bash
./configure.sh
./init-database.sh
./restore-snapshot.sh
./patch-config.sh
docker compose up -d
```

Keep existing `config/` after restore — do not re-run `init-database.sh`.

## Pruning Mode

| Setting | Value (Option A) | Retention |
| --- | --- | --- |
| `min-retain-blocks` | `0` | All blocks, block_results, EVM receipts (from restore height onward) |
| `ss-keep-recent` | `100000` (~28h) | Recent state only — no `eth_call` at ancient heights |
| SeiDB | `sc-enable` + `ss-enable` | Required for RPC |

Use **v6.4.2+** (`SEID_VERSION`) — v6.4.0–v6.4.1 incorrectly pruned receipts regardless of `min-retain-blocks`.

For full state history (Option B / archive), set `ss-keep-recent=0` and plan **10 TB+** storage.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 8545 | localhost | EVM JSON-RPC HTTP |
| 8546 | localhost | EVM JSON-RPC WS |
| 26657 | localhost | CometBFT RPC |
| 1317 | localhost | Cosmos REST API |
| 9090 | localhost | gRPC |
| 26656 | public TCP+UDP | CometBFT P2P |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN access to RPC. Open inbound **26656/tcp** and **26656/udp** for peers.

Docs: [Sei node operations](https://docs.sei.io/node) · [Node types & retention](https://docs.sei.io/node/node-types) · [sei-protocol/sei-chain](https://github.com/sei-protocol/sei-chain)
