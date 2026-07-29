# Aptos (aptos-node)

Mainnet public fullnode (PFN). Chain data: `$HOME/aptos-data`.

## Start

```bash
./configure.sh         # .env + datadir; genesis.blob and waypoint.txt live in config/
docker compose up -d
```

Mainnet `config/genesis.blob` and `config/waypoint.txt` are committed (from [aptos-networks](https://github.com/aptos-labs/aptos-networks/tree/main/mainnet)). **The node will not start without them** — `fullnode.yaml` loads both at startup. Refresh them from upstream when Aptos publishes new mainnet artifacts.

REST API: `http://127.0.0.1:8080/v1` · Metrics: `http://127.0.0.1:9101/metrics`

Pin the node version with `APTOS_IMAGE` in `.env` (see [releases](https://github.com/aptos-labs/aptos-core/releases)).

## Snapshot

Prefer official backups over community tarballs on mainnet. Restore with the Aptos CLI, then point `HOST_DATADIR` at the restored DB directory (see [bootstrap from backup](https://aptos.dev/network/nodes/bootstrap-fullnode/aptos-db-restore)). Skip a fresh state-sync only if the restored layout matches `data_dir` in `config/fullnode.yaml`.

Community snapshot files (testnet-oriented guidance): [bootstrap from snapshot](https://aptos.dev/network/nodes/bootstrap-fullnode/bootstrap-fullnode).

## State retention

Default sync uses `DownloadLatestStates` (no full ledger history from genesis). For archive-style history, use `aptos node bootstrap-db` with `--ledger-history-start-version 0` and disable the ledger pruner per [Aptos docs](https://aptos.dev/network/nodes/configure/data-pruning).

## Host ports

| Port (default) | Bind | Role |
| --- | --- | --- |
| 8080 | `RPC_BIND_ADDR` (127.0.0.1) | REST API |
| 9101 | `RPC_BIND_ADDR` | Prometheus metrics |
| 6182 | all interfaces | Public PFN P2P (TCP) |

Open **6182/tcp** inbound on the host firewall when running a public replica.

Docs: [Run a PFN with Docker](https://aptos.dev/network/nodes/full-node/deployments/using-docker) · [Mainnet node files](https://aptos.dev/network/nodes/configure/node-files-all-networks/node-files-mainnet)
