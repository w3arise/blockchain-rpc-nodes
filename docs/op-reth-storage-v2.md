# OP Stack L2 — op-reth storage v2 and pruning

Operator notes for **op-reth** nodes on OP Stack L2s (including Conduit-hosted chains). Covers storage layout, Conduit snapshot behavior, required prune flags, diagnostics, and recovery.

Applies to op-reth **v2.x** with **storage v2** enabled (default). Tested during Mode mainnet troubleshooting; patterns apply to other Conduit OP Stack snapshots with similar prune layouts.

## Architecture

```
L1 (Ethereum) ──► op-node ──► Engine API (JWT) ──► op-reth ──► JSON-RPC
```

op-reth persists chain data in **three layers**:

| Layer | Typical path | Holds |
| --- | --- | --- |
| **Static files** | `$DATADIR/static_files/` | Headers, transaction bodies, receipts, account/storage changesets, (optionally) transaction senders |
| **MDBX** | `$DATADIR/db/` | Block/tx indices, live state tries, stage checkpoints, prune checkpoints |
| **RocksDB** | under `$DATADIR/` | Transaction hash → tx number index, some history indexes |

Many MDBX tables show **0 entries** on storage v2 nodes because data moved to static files or RocksDB. Empty MDBX tables are normal when the corresponding static-file or RocksDB segment is populated.

### Sync pipeline (simplified)

```
Headers → Bodies → SenderRecovery → Execution → (hashing / merkle / index / prune) → TransactionLookup → Finish
```

Stage progress is stored in MDBX `StageCheckpoints`. Prune state is stored separately in `PruneCheckpoints`.

---

## Pruned full node vs archive

| Type | Flags | RPC capability |
| --- | --- | --- |
| **Archive** | No `--prune.*` flags | Full historical state, receipts, tx-by-hash from genesis |
| **Pruned full** | `--full` + segment prune flags | Block bodies from genesis; receipts/state/tx-hash within retention windows |

Conduit GCS snapshots are **pruned full nodes**, not archives. Do not expect genesis-wide receipts, logs, historical state, or tx-by-hash unless you run an archive sync from scratch.

Official reference: [Optimism — Running an archive node](https://docs.optimism.io/node-operators/guides/management/archive-node) · [Pruning op-reth](https://docs.optimism.io/node-operators/guides/management/archive-node#pruning-op-reth)

---

## Conduit snapshot layout

After restoring a Conduit OP Stack snapshot (`gs://conduit-networks-snapshots/<network>/latest.tar` into the op-reth datadir):

### Static files (typical)

| Segment | Block range | Notes |
| --- | --- | --- |
| Headers | `0 … tip` | Full chain |
| Transactions | `0 … tip` | Full tx bodies |
| Receipts | `~42_000_000 … tip` | Fixed snapshot floor, not genesis |
| AccountChangeSets | `~42_000_000 … tip` | Same floor as receipts |
| StorageChangeSets | `~42_000_000 … tip` | Same floor as receipts |
| TransactionSenders | **absent** | Fully pruned in snapshot |

The **~42M block floor** is a round boundary baked into Conduit pruned snapshots. Receipts and logs are unavailable below it regardless of `distance = 10064` in config.

### MDBX (typical)

| Table | Expected |
| --- | --- |
| `HeaderNumbers`, `BlockBodyIndices`, `TransactionBlocks` | ~tip entries |
| `HashedAccounts`, `HashedStorages`, `AccountsTrie`, `StoragesTrie` | Live state at execution tip |
| `Headers`, `Transactions`, `Receipts`, `TransactionSenders` | **0** (in static files or pruned) |
| `StageCheckpoints`, `PruneCheckpoints` | Pipeline + prune metadata |

### RocksDB (typical)

| Table | Expected |
| --- | --- |
| `TransactionHashNumbers` | Large (~146M entries on a mature chain) from snapshot, but may be **stale or gated** if `transaction_lookup = full` |
| `AccountsHistory`, `StoragesHistory` | Small (recent window only) |

### Prune checkpoints (typical)

| Segment | Mode | Notes |
| --- | --- | --- |
| SenderRecovery | **Full** | All stored senders removed |
| Receipts / ContractLogs | Distance(10064) | Checkpoint may sit at snapshot floor (~42M − 1) |
| AccountHistory / StorageHistory | Distance(10064) | Rolling window: `tip − 10064` |

**Critical:** snapshot MDBX prune checkpoints must match runtime CLI / `reth.toml`. A mismatch causes startup failures or broken RPC.

---

## Required flags for Conduit pruned snapshots

Add these to `op-reth` in `docker-compose.yml` (and keep them after first start):

```yaml
- --full
- --prune.sender-recovery.full
- --prune.transaction-lookup.distance=10064
- --prune.receipts.distance=10064
- --prune.account-history.distance=10064
- --prune.storage-history.distance=10064
```

### Why each flag

| Flag | Reason |
| --- | --- |
| `--full` | Pruned full node (not archive). Required context for prune flags. |
| `--prune.sender-recovery.full` | Snapshot has **Full** sender prune checkpoint and no `TransactionSenders` static files. Distance mode crashes on resume (see below). |
| `--prune.transaction-lookup.distance=10064` | **`transaction_lookup.full` breaks `eth_getTransactionByHash`** even for recent blocks. Use distance to maintain a rolling hash index. |
| `--prune.receipts/account/storage-history.distance=10064` | Matches Conduit snapshot retention. |

op-reth writes the effective config to **`$DATADIR/reth.toml`** on startup:

```toml
[prune.segments]
sender_recovery = "full"
transaction_lookup = { distance = 10064 }

[prune.segments.receipts]
distance = 10064

[prune.segments.account_history]
distance = 10064

[prune.segments.storage_history]
distance = 10064

[prune.segments.bodies_history]
before = 0
```

Keep flags in compose **even when `reth.toml` exists** — fresh snapshot restores have no correct `reth.toml` until first start with the right flags.

`bodies_history.before = 0` means **keep all block bodies** (OP Stack requirement). Do not use `--minimal` on op-node L2 setups.

---

## Known failure: SenderRecovery crash after snapshot

### Symptom

```
ERROR Stage encountered a fatal error: database integrity error occurred:
  trying to append data to TransactionSenders as block #0 but expected block #42000000
  stage=SenderRecovery
```

Often after restoring a Conduit snapshot and starting op-reth **without** explicit prune flags.

### Cause

1. Snapshot datadir: `SenderRecovery` prune checkpoint = **Full**, no `TransactionSenders` static files, receipt floor at ~42M.
2. Runtime defaults / `reth.toml`: `sender_recovery = Distance(10064)`.
3. On resume, `SenderRecovery` tries to write senders to static files starting at block 0; prune boundary expects ~42M → fatal error.

This is a known op-reth / reth issue with **distance-pruned senders + storage v2 + snapshot resume**. Upstream: [reth #23463](https://github.com/paradigmxyz/reth/issues/23463). Fix PR [#25066](https://github.com/paradigmxyz/reth/pull/25066) was closed without merge as of mid-2026.

### Fix (no wipe)

Align runtime with the snapshot — use `--prune.sender-recovery.full` (and other flags above). **Do not wipe** if headers/bodies/state are intact.

Changing flags alone may not heal a datadir that already entered a crash loop with wrong config; a wipe + re-restore is the fallback.

---

## Known failure: eth_getTransactionByHash returns null

### Symptom

- `eth_getBlockByNumber` works for recent blocks (tx count > 0).
- `eth_getTransactionByHash` returns null for txs in those same blocks.
- Public RPC finds the tx.

### Cause

`transaction_lookup = full` in runtime config or `reth.toml`. The node does not maintain a hash → tx number index for RPC. `TransactionLookup` stage checkpoint may show `block_number` at tip with `stage_checkpoint: None` while only a small recent window is actually indexed.

### Fix

1. Change to distance (not full):

   ```toml
   [prune.segments.transaction_lookup]
   distance = 10064
   ```

   Or CLI: `--prune.transaction-lookup.distance=10064` (remove `--prune.transaction-lookup.full`).

2. Restart op-reth. The pipeline indexes forward; the ~10k-block window fills over time.

3. For faster recovery, run an offline rebuild (see below).

---

## Expected RPC behavior (pruned Conduit node)

At tip *T* with the recommended flags:

| Method | Coverage |
| --- | --- |
| `eth_getBlockByNumber` | Genesis → tip |
| `eth_getTransactionByHash` | Last ~10_064 blocks (`T − 10064 … T`) after index is built |
| `eth_getBlockReceipts` / logs | ~42_000_000 → tip (snapshot floor, not genesis) |
| `eth_getLogs` | Same as receipts; many blocks return `[]` (no events) — that is normal |
| Historical state (`eth_getStorageAt` at old block) | Last ~10_064 blocks |

```
Block bodies:     genesis ─────────────────────────────────────► tip   FULL

Receipts/logs:              ~42_000_000 ─────────────────────► tip   partial (snapshot floor)

Tx hash index:                              T−10064 ───────────► tip   rolling window

Historical state:                           T−10064 ───────────► tip   rolling window
```

Pruning detection scripts that treat RPC `200` + empty `[]` as “full from genesis” will **over-report** capabilities. Trust per-block probes, not summary labels.

---

## Diagnostics

All commands assume chain preset `mode` or your chain’s built-in name, datadir `/data` in container, `$HOME/<chain>-op-reth-data` on host.

### Static files + table sizes

```bash
docker exec <op-reth-container> op-reth db stats \
  --datadir /data --chain <chain> --skip-consistency-checks
```

Sections: static file segments, MDBX tables, RocksDB tables.

**Read static files first.** Missing `TransactionSenders` with Full sender prune is expected. Receipts/changesets starting at ~42M confirm a Conduit pruned snapshot.

### Stage checkpoints

```bash
docker exec <op-reth-container> op-reth db stage-checkpoints get \
  --datadir /data --chain <chain>
```

Single stage:

```bash
docker exec <op-reth-container> op-reth db stage-checkpoints get \
  --datadir /data --chain <chain> --stage transaction-lookup
```

Compare `Headers` / `Bodies` block_number to other stages. A gap (e.g. 38 blocks) means the pipeline stalled mid-sync.

### Prune checkpoints

```bash
docker exec <op-reth-container> op-reth db prune-checkpoints get \
  --datadir /data --chain <chain>
```

Compare **Prune Mode** column to compose flags and `reth.toml`. Mismatch → fix flags before restart.

### On-disk config

```bash
cat $HOME/<chain>-op-reth-data/reth.toml
```

Written/updated by op-reth on startup from effective CLI + defaults.

### Quick RPC checks

```bash
# Block history (should work from genesis)
curl -s http://127.0.0.1:<HTTP_PORT> -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x1", false],"id":1}'

# Receipts below snapshot floor (expect empty or error)
curl -s http://127.0.0.1:<HTTP_PORT> -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockReceipts","params":["0x142A708"],"id":1}'

# Receipts above floor (expect data for non-empty blocks)
curl -s http://127.0.0.1:<HTTP_PORT> -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockReceipts","params":["0x28F52C0"],"id":1}'
```

---

## Offline transaction lookup rebuild

Use when `transaction_lookup` was `full` and hash lookups fail for recent blocks.

**Stop op-reth and op-node first** (DB lock).

### Rebuild last 10k blocks (recommended)

```bash
FROM=$((TIP - 10064))
TO=$TIP

docker compose run --rm --entrypoint op-reth <op-reth-service> \
  stage run tx-lookup \
  --chain <chain> \
  --datadir /data \
  --config /data/reth.toml \
  --from "$FROM" \
  --to "$TO" \
  --commit \
  --checkpoints \
  --skip-unwind
```

Replace `$TIP` with current head from `stage-checkpoints get --stage headers`.

### Full rebuild (genesis → tip)

Only if you need hash lookup for all txs in static files. **Many hours** (~146M txs on a mature chain).

```bash
# Reset checkpoint (node stopped)
docker compose run --rm --entrypoint op-reth <op-reth-service> \
  db stage-checkpoints set \
  --chain <chain> --datadir /data \
  --stage transaction-lookup --block-number 0 --clear-stage-unit

docker compose run --rm --entrypoint op-reth <op-reth-service> \
  stage run tx-lookup \
  --chain <chain> --datadir /data --config /data/reth.toml \
  --from 0 --to "$TIP" \
  --commit --checkpoints --skip-unwind
```

With `distance = 10064`, the pruner eventually trims entries outside the window even after a full rebuild.

| Flag | Purpose |
| --- | --- |
| `--commit` | Write to RocksDB (required) |
| `--checkpoints` | Update stage checkpoint during run |
| `--skip-unwind` | Skip unwind when re-indexing an incomplete range |

---

## Enabling tx indexing on an existing pruned node

| Goal | Approach |
| --- | --- |
| Rolling tx-by-hash (~10k blocks) | Change `transaction_lookup` from `full` to `distance = 10064`; restart or offline `stage run tx-lookup` |
| Full tx-by-hash from genesis | Rebuild lookup from static tx files (slow) **or** archive resync without lookup prune |
| Receipts/logs from genesis | Not possible on pruned Conduit snapshot; need archive node |
| Historical state from genesis | Not possible on pruned node; need archive node |

You **cannot** turn a pruned Conduit snapshot into a full archive with a config change alone.

---

## db stats cheat sheet

### Static files

| Segment | Full chain? | Meaning if truncated |
| --- | --- | --- |
| Headers / Transactions | Yes | Should reach tip; if not, sync incomplete |
| Receipts / ChangeSets | Often from ~42M | Conduit snapshot floor |
| TransactionSenders | Often **missing** | Expected with `sender_recovery.full` |

### MDBX tables (storage v2)

| Table | Non-zero? | Role |
| --- | --- | --- |
| `HeaderNumbers`, `BlockBodyIndices`, `TransactionBlocks` | Yes (~tip) | Block/tx mapping |
| `HashedAccounts`, `HashedStorages`, tries | Yes | Live state |
| `Headers`, `Transactions`, `Receipts`, `TransactionSenders` | Usually 0 | Data in static files or pruned |
| `StageCheckpoints` | 15 entries | Pipeline progress |
| `PruneCheckpoints` | ~5 entries | Prune metadata |

### Stage checkpoint interpretation

| Pattern | Meaning |
| --- | --- |
| Headers/Bodies at tip; others behind | Pipeline stuck mid-sync (check logs for stage errors) |
| `TransactionLookup` at tip, `stage_checkpoint: None` | Stage passed tip but entity progress not tracked — verify index with RPC |
| `TransactionLookup` `processed: 0 / total: N` | Lookup never completed after snapshot |

---

## Checklist: new Conduit OP Stack chain in this repo

1. Pin op-reth / op-node images in `env.template`.
2. Add prune flags above to `docker-compose.yml` (not just `reth.toml`).
3. Document Conduit snapshot restore in `<chain>/README.md` (extract into datadir root, not nested paths).
4. Document that the node is a **pruned full** replica, not archive.
5. After first start, verify with `db stats --skip-consistency-checks` and `stage-checkpoints get`.
6. Test `eth_getTransactionByHash` on a recent block tx — not just `eth_getBlockByNumber`.

---

## References

- [Optimism — archive node and pruning](https://docs.optimism.io/node-operators/guides/management/archive-node)
- [Conduit — OP Stack nodes](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes)
- [reth — configure pruning](https://reth.rs/run/configuration/)
- [reth #23463 — SenderRecovery static file / distance prune crash](https://github.com/paradigmxyz/reth/issues/23463)
- [reth PR #25066 — prune checkpoint consistency fix (unmerged)](https://github.com/paradigmxyz/reth/pull/25066)
- [reth — stage run tx-lookup](https://reth.rs/cli/reth/stage/run/)
- [reth — db stage-checkpoints / prune-checkpoints](https://reth.rs/cli/reth/db/stage-checkpoints/get/)

Related repo docs: [`AGENTS.md`](../AGENTS.md) (OP Stack architecture, ports, JWT, Conduit bootnodes).
