# OP-Geth catch-up recovery (expired L1 blobs)

When the node was offline (or restored from an old snapshot) long enough that **B² Hub** pruned the EIP-4844 blobs covering the gap, `op-node` may deadlock on CL sync:

```
failed to fetch blobs: ... no block roots at slot ...
```

`op-node` sees a `finalized` block already in the datadir, skips EL-sync, and needs those expired blobs. Engine API also ignores a zero `finalizedBlockHash`, so a stale `finalized` label can stick.

**Fix:** stop `op-node`, drive op-geth via Engine API from a public peer, advance `safe`/`finalized` near tip, then restart `op-node`.

Upstream: [OP-Geth Catch-Up & Recovery Runbook](https://docs.bsquared.network/for-developers/b2_op-geth_catchup_recovery) · scripts from [b2network/docs](https://github.com/b2network/docs/tree/main/nodes).

Run all commands from the `b2/` directory unless noted.

## Symptoms

- `op-node` stuck on blob retrieval / CL sync
- `eth_getBlockByNumber("finalized")` much older than `"latest"`
- Local head not advancing while public tip is far ahead

## Prerequisites

- Python 3 on the host
- `../config/jwt.hex` present relative to this folder (same JWT op-geth was started with)
- Network reachability to `https://b2-mainnet.alt.technology`
- **`op-node` stopped for the entire procedure** — it races with the scripts on `engine_forkchoiceUpdated`

Defaults in the scripts (override with env if needed):

| Var | Default |
| --- | --- |
| `JWT_PATH` | `../config/jwt.hex` (next to this folder) |
| `ENGINE` | `http://127.0.0.1:8551` |
| `LOCAL_RPC` | `http://127.0.0.1:8223` |
| `PUBLIC_RPC` | `https://b2-mainnet.alt.technology` (`drive_sync.py` only) |
| `FINALIZED_LAG` | `2000` (~1.1h; `set_labels.py` only) |

Engine is **not** published in the normal compose file. Use `docker-compose.recovery.yml` only for this procedure.

## Procedure

### 0 — Stop op-node

```bash
docker compose stop b2-op-node
```

Confirm nothing else is calling forkchoice on this geth.

### 1 — Publish Engine API on localhost

```bash
docker compose -f docker-compose.yml -f catchup-recovery/docker-compose.recovery.yml up -d b2-op-geth
```

### 2 — Drive beacon sync

```bash
python3 catchup-recovery/drive_sync.py
```

`SYNCING` is expected. `INVALID` is fatal — check JWT / endpoints, then stop.

Re-run until local head is close to the network tip (`local head=` / `behind=` in the script output, or compare `eth_blockNumber` to the public RPC).

If geth has too few peers:

```bash
docker compose exec b2-op-geth geth attach --datadir=/data --exec 'admin.peers.length'
# re-dial bootnodes if needed, then re-run drive_sync.py
```

### 3 — Advance safe / finalized labels

Only after head has caught up:

```bash
python3 catchup-recovery/set_labels.py
```

Expect `VALID` and recent `safe` / `finalized` numbers. Do not set `FINALIZED_LAG` to `0`.

### 4 — Drop recovery port and start op-node

```bash
docker compose up -d
```

That recreates `b2-op-geth` without the localhost Engine publish and starts `b2-op-node`.

## Verification

- `eth_getBlockByNumber("finalized")` / `("safe")` are recent (not the pre-outage label)
- `op-node` derives new L2 blocks instead of stalling on blobs
- Local `latest` keeps advancing with the network

## Safety

- Never run `op-node` concurrently with `drive_sync.py` or `set_labels.py`
- Do not leave the recovery compose override attached after recovery (Engine stays Docker-internal in normal operation)
- If you accidentally ran them together: stop everything, re-check labels, restart from step 0
