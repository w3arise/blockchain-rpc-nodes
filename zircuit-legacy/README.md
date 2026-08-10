# Zircuit legacy (l2-geth + op-node)

Pre-Conduit mainnet OP Stack L2 (**chain ID 48900**) on **`zircuit1/l2-geth`** + **`zircuit1/op-node`**. Chain data: `$HOME/zircuit-data`.

**Deprecated for current mainnet.** Zircuit migrated to Conduit in Aug 2026 — use [`../zircuit/`](../zircuit/) for new mainnet nodes. Keep this setup only if you already have a legacy l2-geth datadir or Liquify snapshot.

**Pruning mode:** l2-geth **hash full** (`--gcmode=full`, `--state.scheme=hash`, `--txlookuplimit=0`) — full block, receipt, and log history; pruned historical state.

## Start

```bash
./configure.sh
# restore external snapshot into $HOME/zircuit-data — see Snapshot
docker compose up -d
```

When L1 runs on the Docker host, `host.docker.internal` works for L1 URLs (compose sets `extra_hosts`).

## Snapshot

This setup expects an **external Liquify lz4 snapshot** restored into `$HOME/zircuit-data` before first start. Conduit op-reth snapshots are **not** compatible.

Latest mainnet snapshot name:

```bash
curl -sS https://zircuit-snapshot.liquify.com/files/mainnet/latest_compressed_zircuit.txt
```

Download from `https://zircuit-snapshot.liquify.com/files/mainnet/<snapshot>.tar.lz4` (verify with the matching `.sha256`). Extract/decompress into `$HOME/zircuit-data` using the layout expected by l2-geth.

Docs: [Run Zircuit](https://docs.zircuit.com/build/start/run-zircuit).

## Host ports

RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`): HTTP **11585**, WS **11586**. For a public replica, allow inbound op-node P2P (TCP + UDP): **18688** (`OP_NODE_P2P_PORT`). l2-geth runs with `--nodiscover` (no execution-layer P2P).

Docs: [Run Zircuit](https://docs.zircuit.com/build/start/run-zircuit) · [l2-geth-public](https://github.com/zircuit-labs/l2-geth-public) · [current Conduit setup](../zircuit/README.md)
