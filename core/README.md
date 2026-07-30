# Core (core-chain geth)

Mainnet RPC node — **hash-full** (`--state.scheme=hash --gcmode=full`): full blocks/receipts/logs, pruned state. Chain data: `$HOME/core-data`.

## Start

```bash
./configure.sh
docker compose build
./restore-snapshot.sh    # preferred; or ./init-database.sh for genesis sync
docker compose up -d
```

## Snapshot

Official **pruned (state)** mainnet tarball from [core-snapshots](https://github.com/coredao-org/core-snapshots) (~136 GB download; plan **≥2 TB** disk). `./restore-snapshot.sh` downloads it (URL/MD5 in `.env`). Skip `init-database.sh` after restore.

Do **not** enable `--pruneancient` — that drops ancient blocks/receipts.

## Pruning Mode

| Mode | Flags | Receipts / logs | State |
| --- | --- | --- | --- |
| **Hash full (this setup)** | `STATE_SCHEME=hash` `GCMODE=full` `HISTORY_TRANSACTIONS=0` | Full | Recent only |
| Hash archive | `GCMODE=archive` (forces hash) | Full | Full (much heavier; ≥5 TB) |

Offline state prune is possible later (`geth snapshot prune-state`); never prune an archive datadir you still need.

## Host ports

Inbound P2P: **35021** TCP+UDP (official `config.toml` default; not a hard docs requirement). HTTP/WS: localhost **8575** / **8576** (8575 is the docs RPC default).

Docs: [RPC node](https://docs.coredao.org/docs/Node/config/rpc-node-config) · [core-chain](https://github.com/coredao-org/core-chain)
