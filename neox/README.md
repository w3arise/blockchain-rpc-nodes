# Neo X (bane-labs geth)

Mainnet seed/RPC node. Chain data: `$HOME/neox-data`.

## Start

```bash
./configure.sh
docker compose build
./init-database.sh
docker compose up -d
```

## Snapshot

Restore snapshot data into `$HOME/neox-data`, then skip `init-database.sh`:

```bash
./configure.sh              # .env + EXT_IP (skip if .env already set)
docker compose build
docker compose up -d
```

## Testnet

```bash
./init-database.sh testnet
```

Set `NETWORK_ID=12227332` and testnet bootnodes in `.env` before starting.

Docs: [Run a Neo X Node](https://xdocs.ngd.network/development/run-a-neo-x-node)
