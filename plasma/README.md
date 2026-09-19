# Plasma (reth + plasma-consensus)

Mainnet observer / RPC node. Chain data: `$HOME/plasma-reth-data`, `$HOME/plasma-consensus-data`.

Reth archive (no `--full`): full receipts and logs. Consensus is the public observer image from [node-templates v1.1.0](https://github.com/PlasmaLaboratories/node-templates/releases/tag/v1.1.0).

## Start

```bash
./configure.sh          # create .env, set EXT_IP, mkdir datadirs
./create-jwt.sh
./restore-snapshot.sh   # requester-pays S3; skip and use ./init-database.sh to sync from genesis
docker compose up -d
```

RPC: `http://127.0.0.1:8945` · WS: `ws://127.0.0.1:8946`

## Snapshot

Official daily observer backups (consensus LMDB + Reth datadir) live in requester-pays S3: `s3://plasma-mainnet-db-backups/mainnet/observer-0/`. `./restore-snapshot.sh` downloads the newest date folder into `$HOME/plasma-snapshot-tmp` (override with `SNAPSHOT_TMPDIR` on the **same volume** as the datadirs), then `mv`s the unpacked DBs into the host paths. Archives are never deleted.

Needs AWS credentials. After restore, skip `./init-database.sh` unless the snapshot omitted the consensus identity file.

## Pruning Mode

Default Reth **archive** (no `--full`, no `--minimal`). That keeps historical receipts and logs. Do not add `--full` on this datadir — it drops receipt/log history to a short window. Consensus 1.1.0 can migrate a 0.15.0 observer DB in place; do not downgrade that volume.

Aquila committee settings live in `config/<network>/non-validator.toml`. Refresh those files from [node-templates](https://github.com/PlasmaLaboratories/node-templates) when Plasma publishes a new template release.

## Testnet

Set in `.env` before configure/restore (chain ID 9746):

```
NETWORK=testnet
HOST_DATADIR=$HOME/plasma-testnet-reth-data
HOST_CONSENSUS_DATADIR=$HOME/plasma-testnet-consensus-data
HTTP_PORT=8947
WS_PORT=8948
P2P_PORT=10304
CONSENSUS_P2P_PORT=34071
SNAPSHOT_BUCKET=plasma-testnet-db-backups
SNAPSHOT_PREFIX=testnet/observer-0/
```

Copy the testnet `EXECUTION_TRUSTED_PEERS` line from the comments in `env.template`. Then `./restore-snapshot.sh` (or `./init-database.sh`) and `docker compose up -d`.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 8945 | localhost | HTTP JSON-RPC |
| 8946 | localhost | WebSocket |
| 35070 | localhost | Consensus API |
| 10303 | public | Execution P2P (TCP + UDP) |
| 34070 | public | Consensus P2P (TCP) |

Change `RPC_BIND_ADDR` to `0.0.0.0` only when LAN access to RPC is intentional. Engine API stays on the Docker network (`8551`).

Docs: [Non-validator setup](https://www.plasma.org/docs/node-operators/setup-and-configuration/non-validator-node-setup) · [Upgrades](https://www.plasma.org/docs/node-operators/maintenance/upgrades) · [node-templates](https://github.com/PlasmaLaboratories/node-templates)
