# Unichain (op-reth + op-node)

Mainnet OP Stack L2 (chain ID 130). Chain data: `$HOME/unichain-op-reth-data`, `$HOME/unichain-op-node-data`.

Signed transactions are forwarded to `https://mainnet-sequencer.unichain.org`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

RPC: `http://127.0.0.1:9541` · WS: `ws://127.0.0.1:9542`

## Snapshot

No official datadir snapshot. Sync from genesis with `OP_NODE_SYNCMODE=execution-layer`. Peer bootstrap uses `OP_RETH_BOOTNODES` from `env.template`.

## State retention

Archive op-reth (no `--full` or `--minimal`). Receipts and logs are kept from genesis. Account and storage history stay in the datadir.

To shrink state only, stop op-reth, set `[prune.segments.account_history]` and `[prune.segments.storage_history]` in `$HOME/unichain-op-reth-data/reth.toml` (`distance` ≥ 10064), run offline `op-reth prune --chain=unichain --datadir=/data --storage.v2=true`, then start `node` with the same segments. `--full` also windows receipts and logs.

## Upgrade

Stop the stack, copy `OP_RETH_IMAGE` and `OP_NODE_IMAGE` from `env.template` into `.env`, then `docker compose pull && docker compose up -d`. Same-series Superchain patches are tag-only. After the pin PR merges, from the repo root:

```bash
./scripts/apply-tag-only.sh unichain
```

See [op-reth releases](https://docs.optimism.io/releases/op-reth) and [op-node releases](https://docs.optimism.io/releases/op-node).

## Host ports

RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`). Inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default `10405`) and `OP_NODE_P2P_PORT` (op-node, default `9230`).

## Testnet

For Unichain Sepolia (chain ID 1301), edit `docker-compose.yml` (`--chain=unichain-sepolia`, sequencer `https://sepolia-sequencer.unichain.org`) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [Set up a node](https://developers.uniswap.org/docs/unichain/getting-started/set-up-a-node) · [Uniswap/unichain-node](https://github.com/Uniswap/unichain-node) · [Optimism node operators](https://docs.optimism.io/node-operators/tutorials/node-from-docker)
