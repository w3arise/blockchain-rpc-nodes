# Nanoreth on a recent anchor

> Start nanoreth at the EVM state hl-node already holds, then import only later blocks from `evm_block_and_receipts`. S3 stays a one-block fetch for the anchor, plus any hole after that height.

This is a candidate. It is not wired into `docker-compose.yml`, and it has not been run against this deploy. `nb-20261110` has no "keep 48 hours" flag. A plain `reth-hl node --s3` on an empty database downloads the chain from genesis.

## Contents

- [What a plain start does](#what-a-plain-start-does)
- [Target shape](#target-shape)
- [Pieces](#pieces)
- [Candidate procedure](#candidate-procedure)
- [After the anchor](#after-the-anchor)
- [Open checks](#open-checks)
- [Verify](#verify)

## What a plain start does

On an empty datadir the poller reads the last height in `data/evm_block_and_receipts` and announces it as the tip. Reth is still at genesis, so the pipeline requests every height up to that tip. Hours still in the hourly files are local. Every older height is one requester-pays `GetObject` on `s3://hl-mainnet-evm-blocks`.

`--local.fallback-threshold` (default 5 seconds) only delays that fetch at the live tip. It does not set a start height. `--debug-cutoff-height` stops import at a fixed height and does not follow the chain after it.

## Target shape

```text
hl-node P2P stream
        │
        ▼
evm_block_and_receipts/hourly/…     ← live feed, already on disk
        │
        │  heights after the anchor
        ▼
nanoreth reth DB  ──HTTP/WS──►  clients
        ▲
        │  one GetObject, the anchor block only
        │
S3 hl-mainnet-evm-blocks
```

| Height | Where it comes from |
| --- | --- |
| Below the anchor | Empty headers written locally by `init-state --without-evm`. No transactions, no receipts, no S3. |
| The anchor block | Header and account dump produced from the local ABCI state. Receipts for that one block come from S3. |
| After the anchor | `data/evm_block_and_receipts`, then S3 only when a height is missing from those files. |

Clients that want the latest head talk to nanoreth and are served from its database. That head is a block hl-node wrote after its gossip stream. `/evm` on hl-node stays the HyperCore-aware endpoint (`eth_getSystemTxsByBlock*`, latest read precompiles).

History inside nanoreth starts at the anchor and grows until prune caps it. An anchor taken from the **live** checkpoint does not contain the previous 48 hours. Those hours stay on hl-node until they age out. A 48-hour-old checkpoint would fill that window on day one, and the pruner is likely to have deleted it already. Start from the live checkpoint.

## Pieces

| Piece | Role |
| --- | --- |
| hl-node with `--serve-eth-rpc` and `--disable-output-file-buffering` | Writes `data/evm_block_and_receipts` as blocks are verified. This compose file does not pass the buffering flag today. |
| [sprites0/evm-init](https://github.com/sprites0/evm-init) | Reads a local ABCI `.rmp` and writes `<block>.jsonl` plus `<block>.rlp`. No README. Default bucket is the testnet bucket. |
| `reth-hl init-state --without-evm` | Loads that dump and sets the pipeline floor to that block. Documented for testnet in the [nanoreth README](https://github.com/hl-archive-node/nanoreth/blob/nb-20261110/README.md). |
| `reth-hl` `nb-20261110` | Follows the hourly files. `--s3` together with `--local-ingest-dir` is the wrapper that prefers the files. `--local` alone is a different reader and does not do this. |
| Reth prune on bodies and receipts | Stops the database growing past the window. Prune does not skip the genesis download; the anchor does. |

`evm-init` walks `exchange.hyper_evm` in the `.rmp`.

- In-memory EVM db: accounts are inside the file.
- File-backed db (`NoEvmDb`): accounts are read from a RocksDB directory next to the `.rmp`:

```text
<directory of the .rmp>/evm_db_hub_slow/checkpoint/<L1 height>/EvmState
```

The L1 height is `exchange.context.height` inside the file, not the EVM block number. `data/periodic_abci_states/{date}/{height}.rmp` does not sit next to that checkpoint. Point the tool at a `.rmp` whose parent directory actually contains `evm_db_hub_slow`, or stage a copy so the relative path resolves. Confirm the checkpoint is still on disk before starting. The pruner deletes files under `data/` and does not touch `hyperliquid_data/`.

## Candidate procedure

Do this on a datadir copy first. `init-state --without-evm` refuses to run correctly if blocks were already imported into that database.

1. Keep hl-node up with `--serve-eth-rpc` and `--disable-output-file-buffering`, so the hourly files are the live feed.
2. Take a current ABCI `.rmp` whose `evm_db_hub_slow` checkpoint is still present. Stop using a snapshot the pruner is about to delete.
3. Build the anchor. One S3 object, mainnet bucket:

```bash
# from a checkout of sprites0/evm-init
cargo run --release -- "$ABCI_RMP" \
  --bucket hl-mainnet-evm-blocks \
  --region ap-northeast-1
```

The tool prints `<block>.jsonl`, `<block>.rlp`, and a sample `init-state` line. That sample says `--chain testnet`. Use mainnet.

4. Open the JSONL. The tool writes `{"root":"0x000…0"}` on the first line. `init-state` expects that line to be the state root of the header in the `.rlp`. Replace the zero root with the header's state root before importing.
5. Initialize an empty nanoreth datadir:

```bash
reth-hl init-state --without-evm --chain mainnet \
  --header <block>.rlp \
  --header-hash <header hash printed by evm-init> \
  <block>.jsonl \
  --total-difficulty 0
```

6. Start nanoreth against the same datadir. `--s3` is the fallback; `--local-ingest-dir` is what makes the hourly files win:

```bash
reth-hl node \
  --chain mainnet \
  --datadir <nanoreth datadir> \
  --http --http.addr "${RPC_BIND_ADDR:-127.0.0.1}" --http.port <NANORETH_HTTP_PORT> \
  --http.api eth,ots,net,web3,debug \
  --ws --ws.addr "${RPC_BIND_ADDR:-127.0.0.1}" --ws.port <NANORETH_WS_PORT> \
  --ws.api eth,ots,net,web3 \
  --s3 \
  --local-ingest-dir "$HOST_DATADIR/data/evm_block_and_receipts" \
  --local.fallback-threshold 5000 \
  --hl-node-compliant \
  --forward-read-precompiles \
  --read-precompile-rpc-url "http://127.0.0.1:${HTTP_PORT}/evm"
```

`<NANORETH_HTTP_PORT>` must not be `HTTP_PORT`. hl-node already publishes that for `/evm` and `/info`.

## After the anchor

The pipeline asks only for heights above the anchor. Those should hit the hourly files. A missing height waits up to `--local.fallback-threshold`, then one `GetObject`. While the hourly file exists, the advertised tip is the file tip, so a one-minute peer loss freezes the head instead of pulling the public tip from S3.

Keep `evm_block_and_receipts` on disk until nanoreth has imported those heights. The pruner deletes `data/` files older than `PRUNE_RETENTION_HOURS` (48). A nanoreth that is caught up can live with that window. A nanoreth that is down longer than the window has to fetch the missed stretch from S3.

Cap growth with a prune distance on bodies and receipts, in blocks, equal to 48 hours at the rate this node applies blocks. Reth's minimum distance on some segments is 10064 blocks. Measure the rate and pick a distance above that. Pruning receipts inside the window deletes the logs this sidecar is here to serve. `reth prune` runs with the process stopped; the same distance belongs in the datadir `reth.toml` so a later start keeps the policy. Do not pass reth `--full`. That also windows receipts.

`--hl-node-compliant` hides system transactions so indexes match `/evm`. `--forward-read-precompiles` answers latest-block HyperCore reads from hl-node. Historical calls replay the reads recorded in the block.

## Open checks

These decide whether the candidate is usable. None of them have been run here.

| Check | Why it can fail |
| --- | --- |
| File-backed checkpoint path | Mainnet state is expected to be `NoEvmDb`. The relative `evm_db_hub_slow` path has to match this datadir. `src/bin/fix.rs` in evm-init exits on that layout. |
| JSONL state root | The generator writes a zero root. Import has to be retried with the header's real root. |
| Dummy header loop | `init-state --without-evm` writes one empty header per block from 1 to the anchor. Public node logs have shown applied heights past one billion ([hyperliquid-dex/node#156](https://github.com/hyperliquid-dex/node/issues/156)). That loop is local disk and time, not S3, and it can be large enough to drop the plan. |
| Account dump size | The JSONL is every account in the live EVM db. Size is unknown until the first run. |
| Header hash | Use the hash `evm-init` prints. `init-state` checks it against the `.rlp`. |
| Receipts on the anchor block | The anchor block itself is fetched from S3 so the header can carry receipts. Later blocks come from the hourly files. |

If the dummy-header loop is too big, this anchor is not the small setup. Filling holes in `/evm` stays on [`../evm-backfill.sh`](../evm-backfill.sh), which downloads only the missing heights into hl-node's RocksDB.

## Verify

After init, the database head should be the anchor block, and a request for an older height should return an empty block (header only, no transactions).

After `node` has followed for a few minutes:

- `eth_getBlockByNumber("latest")` on the nanoreth port moves when hl-node appends to the hourly file.
- `block_source.hl_node.fetched_from_hl_node` increases.
- `block_source.hl_node.fetched_from_fallback` stays flat except when a height was missing from the file.
- A stop of hl-node's stream peer freezes that latest height. It does not start a genesis sync.

S3 billing for the trial should be one `GetObject` for the anchor, plus one object per height the hourly file skipped after it.
