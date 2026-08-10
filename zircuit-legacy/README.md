# Zircuit historical RPC (l2-geth)

Frozen **pre-Conduit** mainnet history on **`zircuit1/l2-geth`** only (**chain ID 48900**). Chain data: `$HOME/zircuit-historical-data`.

**Not a live node.** No op-node, no L1, no P2P sync — serves RPC from a restored Liquify snapshot at a fixed head. For current mainnet, use [`../zircuit/`](../zircuit/).

**Pruning mode:** l2-geth **hash full** (`--gcmode=full`, `--state.scheme=hash`, `--txlookuplimit=0`) — full block, receipt, and log history in the snapshot; pruned historical state.

## Start

```bash
./configure.sh
# restore external snapshot into $HOME/zircuit-historical-data — see Snapshot
docker compose up -d
```

## Snapshot

Restore a **Liquify lz4 mainnet snapshot** into `$HOME/zircuit-historical-data` before first start. Conduit op-reth snapshots are **not** compatible.

Latest snapshot name:

```bash
curl -sS https://zircuit-snapshot.liquify.com/files/mainnet/latest_compressed_zircuit.txt
```

Download from `https://zircuit-snapshot.liquify.com/files/mainnet/<snapshot>.tar.lz4` (verify with the matching `.sha256`).

## RPC-only behavior

| Removed | Why |
| --- | --- |
| op-node | New blocks arrive only via Engine API from op-node; without it the head stays at the snapshot tip |
| L1 RPC / beacon | Only op-node reads L1 |
| JWT / Engine API | Only op-node talks to l2-geth over authrpc |
| P2P (`--maxpeers=0`, `--nodiscover`) | No execution-layer sync |

`GETH_ROLLUP_SEQUENCERHTTP` remains as an optional fallback when local data is incomplete.

Verify after start:

```bash
curl -s http://127.0.0.1:11565 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
curl -s http://127.0.0.1:11565 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

## Host ports

RPC only (`RPC_BIND_ADDR=127.0.0.1` by default): HTTP **11565**, WS **11566**.

Docs: [Run Zircuit](https://docs.zircuit.com/build/start/run-zircuit) · [l2-geth-public](https://github.com/zircuit-labs/l2-geth-public) · [current Conduit setup](../zircuit/README.md)
