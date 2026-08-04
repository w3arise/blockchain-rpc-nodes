# Zircuit (l2-geth + op-node)

Mainnet OP Stack L2 replica (Zircuit `l2-geth`). Chain data: `$HOME/zircuit-l2-geth-data`, `$HOME/zircuit-op-node-data`.

**Pruning mode:** l2-geth **hash full** (`--gcmode=full`, `--state.scheme=hash`, `--txlookuplimit=0`) — full block, receipt, and log history; historical state is pruned. For historical `eth_call` / proofs, use `--gcmode=archive` and `OP_NODE_SYNCMODE=execution-layer` instead (much larger disk).

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON, and SEQUENCER_HTTP in .env
./create-jwt.sh
./restore-snapshot.sh   # optional; skip to sync from P2P (slow)
docker compose up -d
```

When L1 runs on the Docker host, `host.docker.internal` works for L1 URLs (compose sets `extra_hosts`).

## Snapshot

Liquify lz4 tarballs (~300–400 GB compressed; growing). Restore into `$HOME/zircuit-l2-geth-data`:

```bash
./restore-snapshot.sh
docker compose up -d
```

Manual: [Run Zircuit — snapshots](https://docs.zircuit.com/build/start/run-zircuit#snapshots) · `https://zircuit-snapshot.liquify.com/files/mainnet/`

Staging uses `$HOME/zircuit-snapshot-tmp` (override with `SNAPSHOT_TMPDIR`). Requires `lz4`; `aria2c` strongly recommended.

## Testnet (Garfield)

Chain ID **48898**. Refresh image tags from [Zircuit docs](https://docs.zircuit.com/build/start/run-zircuit), set `OP_NODE_NETWORK` / `ZIRCUIT_NETWORK` to `garfield-testnet`, point L1 at Sepolia, and use `SNAPSHOT_BASE=https://zircuit-snapshot.liquify.com/files/garfield-testnet`.

## Host ports

When running a public replica, allow inbound P2P on **TCP + UDP** for `OP_NODE_P2P_PORT` (default **18688**). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`). l2-geth uses `--nodiscover` (no execution-layer P2P).

Docs: [Run Zircuit](https://docs.zircuit.com/build/start/run-zircuit) · [zircuit-labs/l2-geth-public](https://github.com/zircuit-labs/l2-geth-public)
