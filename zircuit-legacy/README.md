# Zircuit historical RPC (l2-geth)

Frozen **pre-Conduit** mainnet history on **`zircuit1/l2-geth`** only (**chain ID 48900**). Chain data: `$HOME/zircuit-historical-data`.

**Not a live node.** No op-node, no L1, no P2P sync — serves RPC from a restored Liquify snapshot at head **32956468**. For current mainnet, use [`../zircuit/`](../zircuit/).

**Pruning mode:** l2-geth **hash archive** (`--gcmode=archive`, `--state.scheme=hash`, `--txlookuplimit=0`) — full pre-fork history including state for proxied `eth_call` / traces.

**Chain spec:** uses built-in **`--network=mainnet`** (original pre-fork genesis, `bedrockBlock: 0`). Do **not** point this node at [`../zircuit/config/genesis.json`](../zircuit/config/genesis.json) — op-reth needs the Conduit genesis with `bedrockBlock: 32956468`.

**RPC APIs:** `debug` is required for pre-fork `debug_traceBlockByNumber` when op-reth forwards historical execution requests.

## Start

```bash
./configure.sh
# restore external snapshot into $HOME/zircuit-historical-data — see Snapshot
docker compose up -d
```

Set **`HISTORICAL_RPC=http://host.docker.internal:11565`** (or `http://172.17.0.1:11565`) in [`../zircuit/.env`](../zircuit/env.template) so Conduit op-reth proxies pre-fork queries here.

## Snapshot

Restore a **Liquify lz4 mainnet snapshot** into `$HOME/zircuit-historical-data` before first start. Must be a **full archive** through block **32956468**. Conduit op-reth snapshots are **not** compatible.

Latest snapshot name:

```bash
curl -sS https://zircuit-snapshot.liquify.com/files/mainnet/latest_compressed_zircuit.txt
```

Download from `https://zircuit-snapshot.liquify.com/files/mainnet/<snapshot>.tar.lz4` (verify with the matching `.sha256`).

## RPC-only behavior

| Removed | Why |
| --- | --- |
| op-node | Head stays at snapshot tip without Engine API driver |
| L1 RPC / beacon | Only op-node reads L1 |
| JWT / Engine API | Not used in RPC-only mode |
| P2P (`--maxpeers=0`, `--nodiscover`) | No execution-layer sync |

Verify legacy directly before testing through op-reth:

```bash
curl -s http://127.0.0.1:11565 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
curl -s http://127.0.0.1:11565 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x1000064", false],"id":1}'
```

## Host ports

RPC only (`RPC_BIND_ADDR=127.0.0.1` by default): HTTP **11565**, WS **11566**. op-reth must reach this over plain HTTP from its container network.

Docs: [Run Zircuit](https://docs.zircuit.com/build/start/run-zircuit) · [l2-geth-public](https://github.com/zircuit-labs/l2-geth-public) · [Conduit op-reth setup](../zircuit/README.md)
