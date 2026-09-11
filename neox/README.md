# Neo X (bane-labs geth)

Mainnet seed/RPC node. Chain data: `$HOME/neox-data`.

## Start

```bash
./configure.sh
docker compose build
./init-database.sh
docker compose up -d
```

Same-series `v0.6.*` binaries are **tag-only**. After a pin PR merges, apply rebuilds the local image:

```bash
./scripts/apply-tag-only.sh neox
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

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (default `30301`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Run a Neo X Node](https://xdocs.ngd.network/development/run-a-neo-x-node)
