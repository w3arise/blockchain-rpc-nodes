# Hyperliquid — backfilling missing HyperEVM blocks

Operator notes for **hl-node** non-validators serving HyperEVM JSON-RPC (`/evm`). Covers
holes in the node's local EVM history, how to find them, and how to backfill them from
Hyperliquid's official S3 block archive with
[`hyperliquid/evm-backfill.sh`](../hyperliquid/evm-backfill.sh).

## The problem

hl-node can have a **hole in the middle of its EVM history**. It serves block `N`,
fails for `N+1 … N+k`, then serves every block after again:

```
eth_getBlockByNumber(N+1)  →  {"error": {"message": "invalid block height: N+1"}}
eth_getLogs over a range touching N+1 … N+k  →  {"error": {"code": -32602, "message": "invalid block range"}}
```

The chain is fine: public RPCs return those blocks. Only this node's local RPC database
is missing them. Indexers and other clients that page through history with `eth_getLogs`
retry the same failing range and get stuck at the hole. Single-block queries just before
the hole still succeed, which makes it easy to misread as a range-size limit.

**A healthy head proves nothing about history.** The node keeps serving the latest
block while the hole exists.

### Why holes happen

hl-node is closed source, so this is an inference. After a stop, crash or restart, a
non-validator catches up from recent state instead of replaying every block it missed,
so blocks produced while it was down may never be written to its RPC DB. A hole
typically spans roughly the length of an outage.

**Every stop of the node, including the one needed for this fix, can create a new
hole.** Always scan after a restart.

Pruning is a separate thing: it removes history **below** the node's oldest kept block.
A hole above that floor stays until it is backfilled.

---

## Finding holes

```bash
cd hyperliquid
./evm-backfill.sh scan <START> <END>           # probes every block
./evm-backfill.sh scan <START> <END> 5000      # samples every 5000th block, bisects each edge
```

Output is one line per hole, e.g. `MISSING 1200001-1200500 (500 blocks)`. The scan is
read-only and safe while the node runs.

Sampled mode finds the exact edges of every hole longer than the step, but can miss a
hole shorter than the step that falls between two samples. Sweep the whole history
sampled, then re-scan any suspicious area at step 1. The RPC endpoint comes from
`RPC_BIND_ADDR` / `HTTP_PORT` in `.env` (override with `RPC=`).

---

## The data source: S3

Hyperliquid publishes every HyperEVM block
([Raw HyperEVM block data](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/raw-hyperevm-block-data)):

| | |
| --- | --- |
| Bucket | `s3://hl-mainnet-evm-blocks` (testnet: `s3://hl-testnet-evm-blocks`) |
| Region | `ap-northeast-1` |
| Access | **Requester pays**: every command needs `--request-payer requester`, and your AWS account pays for the transfer (cents for thousands of blocks) |
| Format | One file per block: MessagePack, then LZ4 frame |
| Layout | `{⌊(h−1)/10⁶⌋·10⁶}/{⌊(h−1)/10³⌋·10³}/{h}.rmp.lz4` |

The layout uses **`h − 1`**: folder `…/6000/` holds blocks **6001 – 7000**, and block
7000 is `0/6000/7000.rmp.lz4`, not `0/7000/…`. `evm-backfill.sh download` computes the
folders for you.

---

## The importer

[sprites0/block-importer](https://github.com/sprites0/block-importer) writes the S3 files
into hl-node's RPC database (RocksDB at `$HOST_DATADIR/hyperliquid_data/db_hub/Rpc`). For
each block it writes:

| Key | Value |
| --- | --- |
| `"Eb"` + block number (u64 big-endian) | The S3 file, decompressed, minus its first byte (msgpack 1-element array marker) |
| `"En"` + block hash | Block number |
| `"Et"` + tx hash | `[block number, tx index]` |

- Only adds keys; never deletes.
- Needs hl-node **stopped**, because RocksDB allows a single writer.
- Panics on a missing block file; blocks already written stay written.
- `--end-block` is inclusive. It prints the exclusive end (`Processing blocks A to B+1`).
- Upstream has no license file. The script clones and builds it on the host; nothing is
  vendored here.

**Pitfall:** `--db-dir` defaults to `~/hl`, and RocksDB **creates an empty database** at
a path that doesn't exist. Pointed at the wrong directory, the import "succeeds" and
fixes nothing. The script passes `HOST_DATADIR` and refuses to run unless
`…/db_hub/Rpc/CURRENT` exists.

### Format check

The importer assumes hl-node still stores exactly the bytes S3 publishes. Before
writing, the script compares a block the node **already has** (the blocks just outside
the range, `START−1` and `END+1`) with its S3 file, read-only on the backup copy:

```
block <START-1>: DB: <n> bytes, S3: <n> bytes | FORMAT MATCHES
```

On `DIFFERENT` the script stops and writes nothing. That means hl-node's storage format
has changed since the importer was written. Don't import.

---

## Setup (once per host)

**AWS access.** Create an IAM user (not root keys) with read access to the bucket, and
give it an access key for the CLI:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::hl-mainnet-evm-blocks", "arn:aws:s3:::hl-mainnet-evm-blocks/*"]
  }]
}
```

A billing alert is worth adding, since the bucket is requester pays.

**AWS CLI** (no sudo needed):

```bash
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip
unzip -q awscliv2.zip && ./aws/install -i ~/.local/aws-cli -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"            # add to ~/.bashrc
aws configure                                    # region: ap-northeast-1
aws s3 ls s3://hl-mainnet-evm-blocks/ --request-payer requester | head -3
```

**Build tools:** `build-essential clang libclang-dev` (RocksDB is compiled from source),
plus Rust: `curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal`.

**Importer and compare tool:**

```bash
cd hyperliquid
./evm-backfill.sh setup
```

This clones upstream into `~/hl-importer-upstream`, adds a small read-only compare tool
(`examples/compare.rs`), and builds both with `--locked`. Upstream's `Cargo.lock` pins
`serde` 1.0.219, and a newer serde breaks the `alloy-consensus` 0.12 that reth v1.3.0
needs.

---

## Backfill a hole

### Automated

```bash
cd hyperliquid
./evm-backfill.sh scan <START-100> <END+100>    # confirm the exact range
./evm-backfill.sh run  <START> <END>
```

`run`:

1. **`download`:** syncs the S3 folders covering `START−1 … END+1` into `~/evm-blocks`
   and checks that every file exists.
2. Records the node head, asks for confirmation, runs `docker compose stop` (node and
   pruner), and waits until no `hl-visor` / `hl-node` process remains.
3. **`import`:**
   1. refuses if hl is running or the DB path isn't a RocksDB database
   2. checks free space and copies the DB to `~/hl-Rpc-backup-<timestamp>`
   3. runs the format check
   4. imports
4. `docker compose start`, waits for the RPC (up to `WAIT_MAX`, default 30 min), then
   **`verify`**s every block in the range.
5. Prints the `scan` command to check for a new hole left by this restart.

### Step by step

The same steps can be run individually:

```bash
./evm-backfill.sh download <START> <END>
docker compose stop
./evm-backfill.sh import <START> <END>
docker compose start
./evm-backfill.sh verify <START> <END>          # once the RPC answers
```

Stop the **whole compose project**. Killing only `hl-node` doesn't work: `hl-visor`
restarts it and it takes the DB lock again. Never use `docker compose down -v`.

### Settings

`evm-backfill.sh` reads `HOST_DATADIR`, `HTTP_PORT` and `RPC_BIND_ADDR` from `.env`. Other
settings can be overridden with environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `HL_DATA` | `$HOST_DATADIR` | `--db-dir` (the directory containing `hyperliquid_data/`) |
| `RPC` | `http://$RPC_BIND_ADDR:$HTTP_PORT/evm` | Endpoint for `scan` / `verify` |
| `BLOCKS_DIR` | `~/evm-blocks` | S3 download staging; stable, so re-runs reuse files |
| `IMPORTER_DIR` | `~/hl-importer-upstream` | Importer checkout and build |
| `BACKUP_ROOT` | `~` | Where DB backups go (needs free space ≥ DB size) |
| `COMPOSE_DIR` | script directory | Compose project for `run` |
| `S3_BUCKET` / `AWS_REGION` | mainnet / `ap-northeast-1` | Use `s3://hl-testnet-evm-blocks` for testnet |
| `PARALLEL` | `16` | Concurrent RPC probes in `scan` / `verify` |
| `WAIT_MAX` | `1800` | Seconds `run` waits for the RPC after start |

---

## After the restart

hl-node takes several minutes to come up. These log lines are **normal** during startup:

- `error loading …/visor_abci_state.json: missing file`, repeated every 2 s until the
  node has loaded state
- `downloading new hl-node binary` / `restarting child`, once: the visor starting the
  current release
- `querying status @@ rpc_ip …`: fetching state from peers

Worrying: `n_restarts` climbing, or panics in
`$HOST_DATADIR/data/visor_child_stderr/{date}/{node_binary_index}`.

Once the RPC answers:

```bash
./evm-backfill.sh verify <START> <END>
./evm-backfill.sh scan <head before stop − 100> <current head>
```

If the scan finds a new hole, backfill it the same way.

---

## Rollback

If the imported range is still not served, or the node misbehaves after the import:

```bash
docker compose stop
./evm-backfill.sh restore ~/hl-Rpc-backup-<timestamp>
docker compose start
```

`restore` never deletes anything. The replaced DB is moved aside to
`Rpc.failed-<timestamp>`. Remove it, the backup and `~/evm-blocks` yourself once the node
has been healthy for a while.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Could not connect to the endpoint URL: https://hl-mainnet-evm-blocks.s3.<region>.amazonaws.com/…` | CLI region is invalid (e.g. `eu-west`). `aws configure set region ap-northeast-1` |
| `AccessDenied` | Missing `--request-payer requester`, or the IAM policy isn't attached |
| `[Errno 32] Broken pipe` after `aws s3 ls … \| head` | Harmless: `head` closed the pipe |
| Build: `'stddef.h' file not found` | `export BINDGEN_EXTRA_CLANG_ARGS="-I$(dirname $(find /usr/lib/gcc -name stddef.h \| head -1))"` (the script sets this) |
| Build: `cannot find __private in serde` | Built without `--locked`. Use `--locked` |
| `Failed to create RocksDB directory … File exists` | The DB path is a dangling symlink or a file, not a directory |
| hl-node comes back right after being killed | `hl-visor` restarted it. Stop the compose project |
| `pgrep -f hl-node` reports running when it isn't | `-f` matches any command line containing the text. Use `pgrep -x hl-node` / `pgrep -x hl-visor` (the script does) |

---

## Preventing holes from hurting clients

- **hl-node has no S3 fallback.** It serves only its local DB. Hyperliquid's docs suggest
  that builders merge local data with S3 data themselves.
- **Per-request failover proxy:** put a JSON-RPC proxy with per-request retry (e.g.
  eRPC) in front of `/evm`, with this node as primary and a second HyperEVM RPC as
  fallback on `invalid block height` / `invalid block range`. Holes and pruning then stay
  invisible to clients. Load balancers that fail over only on health checks don't help
  here, because the node's head stays healthy.
- **reth-hl (nanoreth):** a reth-based HyperEVM node that builds its chain from the S3
  archive and serves full history. It's a separate node to run.
- **Monitor history, not only the head:** run a sampled `scan` from the oldest kept block
  to the head periodically, and an exact `scan` after every restart.
