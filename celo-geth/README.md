# Celo (op-geth, frozen)

Mainnet historical RPC. Serves the existing op-geth datadir and does not follow the chain. The live node is [`celo/`](../celo/) (op-reth). Chain data: `HOST_DATADIR` (default `$HOME/celo-op-geth-data`).

## Start

```bash
./configure.sh                # creates .env or adds new keys; checks the datadir
docker compose up -d --remove-orphans
```

`--remove-orphans` stops a previously running op-node or eigenda-proxy. RPC: `http://127.0.0.1:8441`, `ws://127.0.0.1:8442` (`RPC_BIND_ADDR`, `HTTP_PORT`, `WS_PORT`).

## State retention

Serves whatever is already in `HOST_DATADIR`. There is no snapshot or sync; `./configure.sh` fails if the datadir is empty. `--gcmode=full` keeps block and receipt history; state is whatever that datadir still has. P2P is off (`--nodiscover --maxpeers=0`).

## Read-only

Writes are not supported. There is no sequencer forwarding and no `txpool` or `debug` API. `eth_sendRawTransaction` may return a hash, but the transaction is never broadcast or included. Send transactions through [`celo/`](../celo/).

## Upgrade

Stop the service, copy `OP_GETH_IMAGE` from `env.template` into `.env`, then `docker compose pull` and `docker compose up -d`. Verify `eth_chainId` returns `0xa4ec` (42220) and `eth_blockNumber` is unchanged. Bump only for security fixes; see [op-geth deprecation](https://docs.celo.org/infra-partners/notices/op-geth-deprecation).

Docs: [Run a node](https://docs.celo.org/infra-partners/operators/run-node) · [op-geth deprecation](https://docs.celo.org/infra-partners/notices/op-geth-deprecation)
