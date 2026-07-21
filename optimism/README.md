# Optimism (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/optimism-op-reth-data`, `$HOME/optimism-op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

## Snapshot

Archive nodes benefit from a pre-synced op-reth datadir. See [Optimism snapshots](https://docs.optimism.io/node-operators/guides/management/snapshots). Restore into `$HOME/optimism-op-reth-data`, then start as above (skip fresh sync).

Snap sync (`OP_NODE_SYNCMODE=execution-layer`) works without a snapshot but is slower for archive use.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default `30303`) and `OP_NODE_P2P_PORT` (op-node, default `9222`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

## Testnet

For OP Sepolia, edit `docker-compose.yml` (`--chain=optimism-sepolia`, sequencer/historical RPC URLs) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration) · [Run a node with Docker](https://docs.optimism.io/node-operators/tutorials/node-from-docker) · [ethereum-optimism/optimism](https://github.com/ethereum-optimism/optimism)
