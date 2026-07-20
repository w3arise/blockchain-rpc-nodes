# Celo (op-geth + op-node + EigenDA)

Deprecated L2 setup kept for historical / pre-migration needs. Prefer [`celo/`](../celo/) (op-reth) for new nodes. Chain data: `../.celo/op-geth`, `../.celo/shared`, `../.celo/eigenda-data` (relative to this directory).

## Start

```bash
cp mainnet.env .env    # set OP_NODE__RPC_ENDPOINT, OP_NODE__L1_BEACON, OP_NODE__P2P_ADVERTISE_IP
docker compose up -d
```

RPC defaults in `mainnet.env`: `http://127.0.0.1:7545` (HTTP), `ws://127.0.0.1:7546` (WS).

## Snapshot / migrated datadir

Snap sync (`OP_GETH__SYNCMODE` empty / default for `NODE_TYPE=full`) needs no migrated datadir. Full sync / archive needs a migrated L1 full-node datadir — download or run `./migrate.sh` per [Migrating a Celo L1 node](https://docs.celo.org/cel2/operators/migrate-node).

## Pre-L2 history

Set `OP_GETH__HISTORICAL_RPC` or `HISTORICAL_RPC_DATADIR_PATH` in `.env` so op-geth can proxy pre-hardfork state to a legacy archive.

## Testnet

```bash
cp alfajores.env .env   # or baklava.env
docker compose up -d
```

Docs: [Run a node](https://docs.celo.org/infra-partners/operators/run-node) · [op-geth deprecation](https://docs.celo.org/infra-partners/notices/op-geth-deprecation) · [celo-l2-node-docker-compose](https://github.com/celo-org/celo-l2-node-docker-compose)
