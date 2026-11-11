# Optimism (op-reth + op-node or kona-node)

Mainnet rollup node. Chain data: `$HOME/optimism-op-reth-data`, plus `$HOME/optimism-op-node-data` or `$HOME/optimism-kona-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
./restore-snapshot.sh   # optional archive snapshot; skip to sync from peers
docker compose up -d    # COMPOSE_PROFILES=op-node by default
```

Same-series Superchain patches for op-reth and op-node are **tag-only**: `./scripts/apply-tag-only.sh optimism`. The Kona image pin is separate.

## Rollup client

`COMPOSE_PROFILES` picks the rollup client. op-reth always starts. Only one rollup client runs.

| Value | Container | Datadir |
| --- | --- | --- |
| `op-node` (default) | `optimism-op-node` | `$HOME/optimism-op-node-data` |
| `kona` | `optimism-kona-node` | `$HOME/optimism-kona-data` |

`./configure.sh` prints the active value. To switch, stop the running rollup container, change `COMPOSE_PROFILES`, then start again:

```bash
docker stop optimism-op-node          # or optimism-kona-node
# edit .env — COMPOSE_PROFILES=kona   # or op-node
docker compose up -d
```

Kona is not the production rollup client. [OP Labs](https://docs.optimism.io/node-operators/kona-node/run/docker) says production deployments should use op-node. Kona v1.10.0 is the pin that matches op-reth v2.8.x. It verifies L1 block hashes; op-node in this setup trusts the L1 RPC (`OP_NODE_L1_TRUST_RPC=true`).

## Snapshot

`./restore-snapshot.sh` downloads the newest OP Mainnet op-reth archive (`op-mainnet-reth-archive-storage-v2-*.tar.zst`) from [datadirs.optimism.io](https://datadirs.optimism.io/), checks sha256, and moves it into `$HOME/optimism-op-reth-data`. An existing `db/` skips both the download and the extract. Set `SNAPSHOT_URL` to pin one tarball. Staging is `$HOME/optimism-snapshot-tmp` (`SNAPSHOT_TMPDIR`); the archive is kept.

Peer sync (`OP_NODE_SYNCMODE=execution-layer`) works without a snapshot. See [Optimism snapshots](https://docs.optimism.io/node-operators/guides/management/snapshots).

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, `23407`) and the active rollup port — `OP_NODE_P2P_PORT` (op-node, `9222`) or `KONA_P2P_PORT` (kona, `9223`). Rollup RPC is `OP_NODE_RPC_PORT` (`8993`) or `KONA_RPC_PORT` (`8994`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

## Testnet

For OP Sepolia, edit `docker-compose.yml` (`--chain=optimism-sepolia`, sequencer/historical RPC URLs) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration) · [Run a node with Docker](https://docs.optimism.io/node-operators/tutorials/node-from-docker) · [Kona node](https://docs.optimism.io/node-operators/kona-node/run/docker) · [ethereum-optimism/optimism](https://github.com/ethereum-optimism/optimism)
