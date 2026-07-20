# AB Core (abcore geth)

Mainnet full RPC node (PoA / Clique). Chain data: `$HOME/ab-data`.

## Start

```bash
./configure.sh
docker compose build
./init-database.sh
docker compose up -d
```

## Snapshot

No official chaindata snapshot is documented. Sync from genesis via P2P after `init-database.sh`.

## State retention

Full node with `--history.state=90000` (~75 hours at 3s blocks), matching [ab-deploy](https://github.com/ABFoundationGlobal/ab-deploy) defaults. This is not an archive node.

## Testnet

```bash
./init-database.sh testnet
```

Set `NETWORK_ID=26888`, `MAX_PEERS=50`, and testnet bootnodes from `ab-deploy` `abcore/testnet/conf/node.toml` in `.env` before starting.

Docs: [AB Core technical info](https://docs.ab.org/docs/) · [Node deployment](https://github.com/ABFoundationGlobal/ab-deploy)
