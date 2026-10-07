# Celo (celo-op-reth + op-node + EigenDA)

Mainnet L2 archive node (default). Chain data: `$HOME/celo-op-reth-data`, `$HOME/celo-op-node-data`, `$HOME/celo-eigenda-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

RPC: `http://127.0.0.1:7545` (HTTP), `ws://127.0.0.1:7546` (WS).

## Snapshot

With `OP_RETH_SNAPSHOT=true` (default), an empty `$HOME/celo-op-reth-data` is bootstrapped from [snapshots.celo.org](https://snapshots.celo.org/) via `celo-reth download` on first start (`NODE_TYPE` selects minimal / full / archive). Skipped once `db/` exists. Mainnet **full** tier ≈ 215 GB download / ≈ 355 GB on disk; **archive** is larger. op-geth datadirs cannot be reused.

Image pins follow [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose) (`celo-v1.0.5` op-reth, `celo-v2.2.1` op-node, EigenDA **v2.6.0**). After a pin bump, `docker compose pull` and recreate **op-reth** (and op-node if its tag changed).

## State retention

**Policy:** Default archive, no extra prune flags. Optional state window: edit `$DATADIR/reth.toml` → offline `celo-reth prune` (node stopped) → start `node` with the same segment config; do not rely on live prune alone to shrink an archive datadir.

Default `NODE_TYPE=archive` downloads the **archive** snapshot and starts op-reth **without** `--full` or `--minimal`, matching [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose). Post-L2 historical **state** RPC is served from the local datadir.

This setup does **not** pass `--prune.account-history.distance` / `--prune.storage-history.distance`. Those flags only shrink **state** history; on an **archive** snapshot they force the live Prune pipeline to delete terabytes of imported history, block the head until Prune catches up, and on some builds stall with repeated “more data to prune” logs. Fix is matching **snapshot tier to runtime** (use `NODE_TYPE=full` or `minimal` for a pruned node), not distance overrides on archive.

**Archive + state-prune config** (`--prune.account-history.distance` / `--prune.storage-history.distance` or the same segments in `reth.toml`) is **only** for **sync from scratch** (`OP_RETH_SNAPSHOT=false`, empty datadir, execute from genesis — e.g. Celo Sepolia). Do **not** combine that with an **archive** snapshot download on first start.

| `NODE_TYPE` | Snapshot | Runtime | Typical use |
| --- | --- | --- | --- |
| `archive` (default) | archive | no `--full` / `--minimal` | Full post-L2 state + receipts; largest disk |
| `full` | full | `--full` | Smaller footprint; Reth prunes receipts/state windows |
| `minimal` | minimal | `--minimal` | Smallest disk; least historical RPC |

If the datadir was initialized with different `NODE_TYPE` or custom prune flags, wipe and re-bootstrap — do not change tier on a populated DB casually.

Offline prune reads `$DATADIR/reth.toml` only (`celo-reth prune --chain=celo --datadir=/data --storage.v2=true`). State-only example in TOML: `[prune.segments.account_history]` and `[prune.segments.storage_history]` with `distance = 10064` (≥ 10064; do not use on live `node` to shrink a fresh archive import).

## Pre-L2 history

Pre-migration Celo L1 state is not in the op-reth datadir (migrated op-geth data cannot be reused). Set `OP_RETH_HISTORICAL_RPC` in `.env` to a legacy Celo L1 archive; op-reth proxies pre-L2 requests there. To reach a node on the Docker host, use `http://host.docker.internal:<port>` (not `127.0.0.1`). See [Running an archive node](https://docs.celo.org/operate/operators/archive-node).

op-reth does **not** forward `eth_getLogs` (it returns `[]`), and older builds return `null` for `eth_getBlockReceipts`. Query pre-L2 logs on the legacy node directly — e.g. [`celo-geth/`](../celo-geth/) — see [op-reth historical RPC](../AGENTS.md#op-reth-historical-rpc---rolluphistoricalrpc).

## Testnet

For Celo Sepolia, set `OP_RETH_CHAIN=celo-sepolia`, `OP_NODE_NETWORK=celo-sepolia`, Sepolia L1 endpoints, and the Sepolia EigenDA / bootnode values commented in `env.template`. Use separate `$HOME` datadir mounts.

## Upgrade

Stop services, copy `OP_RETH_IMAGE`, `OP_NODE_IMAGE`, and `EIGENDA_PROXY_IMAGE` from `env.template` into `.env`, then `docker compose pull` and recreate containers. Compare pins to [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose) before bumping. Same-series **op-reth** tags (`celo-v1.0.*`) may use `./scripts/apply-tag-only.sh celo` after merge; **op-node** and **EigenDA** stay manual (not in the same auto feed).

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `RETH_PORT` (op-reth, default `10401`) and `OP_NODE_P2P_PORT` (default `10422`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Run a node](https://docs.celo.org/infra-partners/operators/run-node) · [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose) · [snapshots.celo.org](https://snapshots.celo.org/)
