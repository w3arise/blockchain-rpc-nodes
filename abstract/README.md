# Abstract (ZK Stack external node)

Mainnet external node (matterlabs/external-node + PostgreSQL). Chain data: `$HOME/abstract-postgres-data`, `$HOME/abstract-rocksdb-data`.

## Start

```bash
./configure.sh
# edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD
docker compose up -d
```

First run downloads a snapshot from GCS (`EN_SNAPSHOTS_RECOVERY_ENABLED=true`). RPC is unavailable until recovery completes.

## Testnet

```bash
./configure.sh testnet
# edit .env — set EN_ETH_CLIENT_URL (Sepolia)
docker compose up -d
```

## Reset

```bash
docker compose down
# remove $HOME/abstract-postgres-data and $HOME/abstract-rocksdb-data to resync from scratch
```

Docs: [Running a node](https://docs.abs.xyz/infrastructure/nodes/running-a-node) · [Abstract-Foundation/abstract-node](https://github.com/Abstract-Foundation/abstract-node)
