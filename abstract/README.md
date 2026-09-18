# Abstract (ZK Stack external node)

Mainnet external node (matterlabs/external-node + PostgreSQL). Chain data: `$HOME/abstract-postgres-data`, `$HOME/abstract-rocksdb-data`.

## Start

```bash
./configure.sh
# edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD
docker compose up -d
```

First run downloads a snapshot from GCS (`EN_SNAPSHOTS_RECOVERY_ENABLED=true`). RPC is unavailable until recovery completes.

If the external node fails with `Too many open files` during RocksDB catch-up, recreate it so the compose `ulimits` apply: `docker compose up -d --force-recreate external-node`. The same recreate is needed after compose changes to **`stop_signal: SIGINT`** (the EN ignores Docker’s default SIGTERM).

## Monitoring (optional)

Prometheus and Grafana are in the **`monitoring` compose profile** — they do not start with the default `docker compose up -d`.

```bash
mkdir -p "$HOME/abstract-prometheus-data" "$HOME/abstract-grafana-data"
sudo chown -R 65534:65534 "$HOME/abstract-prometheus-data"   # prom/prometheus runs as nobody (UID 65534)
sudo chown -R 472:0 "$HOME/abstract-grafana-data"              # grafana/grafana runs as grafana (UID 472)
docker compose --profile monitoring up -d
```

Grafana: `http://127.0.0.1:8300` · External-node metrics: `http://127.0.0.1:3322/metrics`

## Testnet

```bash
./configure.sh testnet
# edit .env — set EN_ETH_CLIENT_URL (Sepolia)
docker compose up -d
```

## Upgrade

Pin is Abstract helm `image.tag` + `image.digest` (not `.env.mainnet`, not Docker Hub latest). Copy `EN_VERSION` and `EN_DIGEST` into an existing `.env` — do not recopy the whole template.

Same-series SHA bumps on an already-v31 datadir: `docker compose pull && docker compose up -d`. Protocol-major jumps (EN v29 → v31) need a Reset first.

## Reset

```bash
docker compose down
# remove $HOME/abstract-postgres-data and $HOME/abstract-rocksdb-data to resync from scratch
```

## `en_getInteropFee` 403

The EN polls `EN_MAIN_NODE_URL` (`https://api.mainnet.abs.xyz`) for `en_getInteropFee`. Abstract’s public proxy does not whitelist that method, so the log repeats:

```
WARN ... Request `en_getInteropFee` failed with HTTP error ... status=403
```

Ignore it. Sync and `eth_*` RPC are unaffected; the EN keeps the interop-fee fallback (zero). The WARN stops if Abstract exposes the method or a later EN image treats HTTP 403 as “method unavailable”.

Docs: [Running a node](https://docs.abs.xyz/infrastructure/nodes/running-a-node) · [Abstract-Foundation/abstract-node](https://github.com/Abstract-Foundation/abstract-node)
