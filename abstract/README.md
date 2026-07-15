# Abstract (ZK Stack external node)

Mainnet external node (matterlabs/external-node + PostgreSQL). Chain data: `$HOME/abstract-postgres-data`, `$HOME/abstract-rocksdb-data`. Monitoring: `$HOME/abstract-prometheus-data`, `$HOME/abstract-grafana-data`.

## Start

```bash
./configure.sh
# edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD
mkdir -p "$HOME/abstract-prometheus-data" "$HOME/abstract-grafana-data"
sudo chown -R 65534:65534 "$HOME/abstract-prometheus-data"   # prom/prometheus runs as nobody (UID 65534)
sudo chown -R 472:0 "$HOME/abstract-grafana-data"              # grafana/grafana runs as grafana (UID 472)
docker compose up -d
```

First run downloads a snapshot from GCS (`EN_SNAPSHOTS_RECOVERY_ENABLED=true`). RPC is unavailable until recovery completes.

If the external node fails with `Too many open files` during RocksDB catch-up, recreate it so the compose `ulimits` apply: `docker compose up -d --force-recreate external-node`.

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
