# Metis Andromeda (l1dtl + l2geth)

Mainnet replica RPC: **Data Transport Layer** + **l2geth** (Optimistic Rollup lineage, not OP Stack). Chain id **1088**.

Datadirs: `$HOME/metis-l1dtl-data`, `$HOME/metis-l2geth-data`.

## Start

```bash
./configure.sh
# edit .env — L1_ETH_RPC and L1_BEACON (MinIO memo creds are in config/l1dtl.env.template)
./configure.sh           # re-run after .env edits; renders config/l1dtl.env + l2geth.env
./restore-snapshot.sh    # follow AWS EBS snapshot steps if datadirs are empty
docker compose up -d
```

## Snapshot

No official HTTP chaindata tarball. Use public **AWS EBS snapshots** in **us-east-2** (`restore-snapshot.sh` prints snapshot IDs from [metis-ansible](https://github.com/MetisProtocol/metis-ansible#snapshots)). Plan ~750 GB for mainnet.

Fresh sync uses `ROLLUP_STATE_DUMP_PATH` (hosted genesis dump) plus L1 derivation via DTL — expect long catch-up; Metis documents `panic: Refund counter below zero` without snapshots.

## Pruning mode

Default **`GC_MODE=full`**: full blocks, receipts, and logs; pruned state. Official ansible uses **`archive`** if you need full state history — do not flip modes on a populated datadir casually.

## L1 requirements

- **`L1_ETH_RPC`**: Ethereum mainnet execution (not `andromeda.metis.io`).
- **`L1_BEACON`**: Ethereum consensus / beacon HTTP API.
- **`FP_BLOCK=22482000`**: blob batches after this L1 height use the beacon (see ansible FAQ on blob retention).
- **`SYNC_L1_BATCH=true`**: required for `eth_getBlockByNumber` with `"finalized"`; do not toggle without DTL resync.

Raise L1 geth **`--rpc.batch-response-max-size=50000000`** if DTL reports “response too large”.

## DTL defaults

| Variable | Default | Meaning |
| --- | --- | --- |
| `DTL_POLLING_INTERVAL_MS` | `15000` | Idle sleep between L1 loops (**milliseconds**, 15 s) |
| `DTL_LOGS_PER_POLL` | `100` | Max L1 block span per ingestion loop |
| `DTL_TXS_PER_POLL` | `100` | L2 tx batch size (only if `SYNC_FROM_L2=true`) |
| `URL` / `ADDRESSES_URL` | metis-networks `addresses.json` | Optional; `dtl.sh` can set AddressManager from URL |
| `L2_RPC_ENDPOINT` | `https://andromeda.metis.io` | Used when syncing from L2; kept for replica parity |
| `DTL_CATCH_ALL_ERRORS` | `true` | Log and retry on L1 ingestion errors instead of exiting |

## Host ports

- JSON-RPC / WS: `RPC_BIND_ADDR` + `HTTP_PORT` / `WS_PORT` (default `127.0.0.1:28555` / `28556`)
- l2geth P2P: `P2P_PORT` (default **30303**, TCP + UDP, public — bump in `.env` if it clashes with another node)
- DTL (`7878`) is Docker-internal only

## Writes

Non-sequencer nodes forward via `SEQ_BRIDGE_URL=https://andromeda.metis.io`.

## Upgrade

Stop compose, copy image pins from `env.template` into `.env`, `docker compose pull`, `./configure.sh`, `docker compose up -d`. Bump **dtl and l2geth together** when Metis publishes paired releases in [metis-ansible](https://github.com/MetisProtocol/metis-ansible).

Pins: `metisdao/dtl:v0.2.6`, `metisdao/l2geth:v0.3.9`.
