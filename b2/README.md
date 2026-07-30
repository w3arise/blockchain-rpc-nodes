# B² Network (op-geth + op-node)

Mainnet OP Stack L2 (chain ID **223**). L1 is **B² Hub** (chain ID 213), not Ethereum. Chain data: `$HOME/b2-op-geth-data`, `$HOME/b2-op-node-data`.

## Start

```bash
./configure.sh
# L1 defaults to https://hub-rpc.bsquared.network + https://hub-cl-rpc.bsquared.network
./create-jwt.sh
./init-database.sh          # or ./restore-snapshot.sh
docker compose up -d
```

RPC: `http://127.0.0.1:8223` (HTTP), `ws://127.0.0.1:8224` (WS). op-node admin: `http://127.0.0.1:8225`.

## Host ports

Public P2P (TCP + UDP): op-geth `${P2P_PORT}` (default 30323), op-node `${HOST_OP_NODE_P2P_PORT}` (default 9233). `./configure.sh` sets `EXT_IP` / `OP_NODE_P2P_ADVERTISE_IP`.

## Snapshot

Official Tencent COS tarballs (prefer these over the recursive dir download in upstream docs):

| Kind | URL | Compressed size (approx.) |
| --- | --- | --- |
| Full | https://b2-download-1318671312.cos.ap-singapore.myqcloud.com/db.tar.gz | ~51 GiB |
| Archive | https://b2-download-1318671312.cos.ap-singapore.myqcloud.com/archive-data.tar.gz | ~946 GiB |

```bash
./configure.sh
./create-jwt.sh
./restore-snapshot.sh archive   # or: full
docker compose up -d
```

Skip `./init-database.sh` after restore. Match `GC_MODE` to the snapshot (`archive` vs `full`). Snapshots refresh Fridays per [upstream docs](https://docs.bsquared.network/for-developers/running_rollup_node); root tarballs may lag.

## State retention

Default is archive (`GC_MODE=archive`, `GETH_SYNC_MODE=full`) for historical state RPC. For a pruned full node (blocks / receipts / logs, no historical state), set `GC_MODE=full` on a fresh datadir only — do not flip `GC_MODE` on an existing archive DB.

Pinned client (`op-geth:v1.101315.2`) supports PathDB via `--state.scheme=path`, but official snapshots and `gcmode=archive` use **HashDB**; this setup initializes with `--state.scheme=hash`.

## Testnet

Not packaged. Upstream has a small `testnet/` prefix on the same COS bucket and [snap-sync from scratch](https://docs.bsquared.network/for-developers/deploy_a_node_from_scratch) notes.

Docs: [rollup node](https://docs.bsquared.network/for-developers/running_rollup_node) · [archive node](https://docs.bsquared.network/for-developers/running_rollup_archive_node) · [b2network/docs](https://github.com/b2network/docs)
