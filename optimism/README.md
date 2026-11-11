# Optimism (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/optimism-op-reth-data`, `$HOME/optimism-op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
./restore-snapshot.sh   # optional archive snapshot; skip to sync from peers
docker compose up -d
```

Same-series Superchain patches are **tag-only**: `./scripts/apply-tag-only.sh optimism`

## Snapshot

`./restore-snapshot.sh` downloads the newest OP Mainnet op-reth archive (`op-mainnet-reth-archive-storage-v2-*.tar.zst`) from [datadirs.optimism.io](https://datadirs.optimism.io/), checks sha256, and moves it into `$HOME/optimism-op-reth-data`. An existing `db/` skips both the download and the extract. Set `SNAPSHOT_URL` to pin one tarball. Staging is `$HOME/optimism-snapshot-tmp` (`SNAPSHOT_TMPDIR`); the archive is kept.

Peer sync (`OP_NODE_SYNCMODE=execution-layer`) works without a snapshot. See [Optimism snapshots](https://docs.optimism.io/node-operators/guides/management/snapshots).

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, `23407`) and `OP_NODE_P2P_PORT` (op-node, `9222`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

## Testnet

For OP Sepolia, edit `docker-compose.yml` (`--chain=optimism-sepolia`, sequencer/historical RPC URLs) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration) · [Run a node with Docker](https://docs.optimism.io/node-operators/tutorials/node-from-docker) · [ethereum-optimism/optimism](https://github.com/ethereum-optimism/optimism)
