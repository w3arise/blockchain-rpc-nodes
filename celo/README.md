# Celo (celo-op-reth + op-node + EigenDA)

Mainnet L2 full node. Chain data: `$HOME/celo-op-reth-data`, `$HOME/celo-op-node-data`, `$HOME/celo-eigenda-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

RPC: `http://127.0.0.1:8441` (HTTP), `ws://127.0.0.1:8442` (WS).

## Snapshot

With `OP_RETH_SNAPSHOT=true` (default), an empty `$HOME/celo-op-reth-data` is bootstrapped from [snapshots.celo.org](https://snapshots.celo.org/) via `celo-reth download` on first start (`NODE_TYPE` selects minimal / full / archive). Skipped once `db/` exists. Mainnet full ≈ 215 GB download / ≈ 355 GB on disk. op-geth datadirs cannot be reused.

## Testnet

For Celo Sepolia, set `OP_RETH_CHAIN=celo-sepolia`, `OP_NODE_NETWORK=celo-sepolia`, Sepolia L1 endpoints, and the Sepolia EigenDA / bootnode values commented in `env.template`. Use separate `$HOME` datadir mounts.

Docs: [Run a node](https://docs.celo.org/infra-partners/operators/run-node) · [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose) · [snapshots.celo.org](https://snapshots.celo.org/)
