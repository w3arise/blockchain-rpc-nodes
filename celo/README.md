# Celo (celo-op-reth + op-node + EigenDA)

Mainnet L2 full node. Chain data: `$HOME/celo-op-reth-data`, `$HOME/celo-op-node-data`, `$HOME/celo-eigenda-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

RPC: `http://127.0.0.1:7545` (HTTP), `ws://127.0.0.1:7546` (WS).

## Snapshot

With `OP_RETH_SNAPSHOT=true` (default), an empty `$HOME/celo-op-reth-data` is bootstrapped from [snapshots.celo.org](https://snapshots.celo.org/) via `celo-reth download` on first start (`NODE_TYPE` selects minimal / full / archive). Skipped once `db/` exists. Mainnet full ≈ 215 GB download / ≈ 355 GB on disk. op-geth datadirs cannot be reused.

## Pre-L2 history

`NODE_TYPE=archive` keeps post-L2 history only. Pre-migration Celo L1 state is not in the op-reth datadir (migrated op-geth data cannot be reused). Set `OP_RETH_HISTORICAL_RPC` in `.env` to a legacy Celo L1 archive; op-reth proxies pre-L2 requests there. To reach a node on the Docker host, use `http://host.docker.internal:<port>` (not `127.0.0.1`).

## Testnet

For Celo Sepolia, set `OP_RETH_CHAIN=celo-sepolia`, `OP_NODE_NETWORK=celo-sepolia`, Sepolia L1 endpoints, and the Sepolia EigenDA / bootnode values commented in `env.template`. Use separate `$HOME` datadir mounts.

Docs: [Run a node](https://docs.celo.org/infra-partners/operators/run-node) · [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose) · [snapshots.celo.org](https://snapshots.celo.org/)
