# Hedera (JSON-RPC Relay + Mirror Node)

Mainnet EVM JSON-RPC endpoint backed by the Hiero JSON-RPC Relay and a self-hosted Mirror Node. Data is stored in `$HOME/hedera-postgres-data`; bootstrap files and logs are stored in `$HOME/hedera-bootstrap-data`.

This is not a Hedera consensus node. Reads are served from the local Mirror Node, while `eth_sendRawTransaction` submits to Hedera consensus nodes using the configured relay operator account.

## Contents

- [Start](#start)
  - [1. Install prerequisites](#1-install-prerequisites)
  - [2. Create configuration and secrets](#2-create-configuration-and-secrets)
  - [3. Download the minimal mainnet database](#3-download-the-minimal-mainnet-database)
  - [4. Initialize PostgreSQL and import the export](#4-initialize-postgresql-and-import-the-export)
  - [5. Start the Mirror Node](#5-start-the-mirror-node)
  - [6. Start HTTP and WebSocket RPC](#6-start-http-and-websocket-rpc)
- [Stop and restart](#stop-and-restart)
- [Database bootstrap (reference)](#database-bootstrap-reference)
- [State retention](#state-retention)
- [Upgrade](#upgrade)

## Start

### 1. Install prerequisites

Install Docker, `gcloud`, `jq`, and `gzip`. Authenticate a GCP project with billing enabled:

```bash
gcloud auth login
```

Create GCP HMAC credentials for the live importer as described in the [GCS mirror-node guide](https://docs.hedera.com/operators/mirror-node/run-your-own/gcs).

### 2. Create configuration and secrets

```bash
./configure.sh
```

Then edit `.env` and rerun `./configure.sh`:

- Set `GCP_PROJECT_ID`, `GCP_ACCESS_KEY`, and `GCP_SECRET_KEY` (required for download + live importer).
- To allow `eth_sendRawTransaction`: set a funded `OPERATOR_ID_MAIN` and `OPERATOR_KEY_MAIN` (relay submits via that Hedera account).
- Read-only RPC (no TX send): set `READ_ONLY=true` instead.

What `configure.sh` also does:

- Generates PostgreSQL role passwords once (replaces `GENERATE` in `.env`).
- Fetches stock `config/init.sh` for `MIRROR_NODE_VERSION` from the matching Hiero Mirror Node tag (gitignored).
- When new secrets are generated: copies `.env` to `secrets-backups/` and pauses for confirmation.

Those DB passwords are written into Postgres on **first** start (`init.sh` via `docker-entrypoint-initdb.d`). If `.env` is lost and `configure.sh` regenerates new passwords later, they will **not** match the existing database — restore a backup, reset roles manually, or wipe and re-bootstrap. Copy the backup file to secure offline storage before continuing.

### 3. Download the minimal mainnet database

Confirm the available export and version (see [Database bootstrap (reference)](#database-bootstrap-reference) for Atma vs full export, sizing, and size-check commands):

```bash
./bootstrap.sh list
./bootstrap.sh download
```

`MIRROR_NODE_VERSION` must match the selected export's `MIRRORNODE_VERSION.gz`. The initial importer must run that same version.

If you cannot store the minimal export, use [Partial history](#partial-history-skip-the-backfill) instead (`./bootstrap.sh download-schema` — sync from ~now, no CSV backfill).

### 4. Initialize PostgreSQL and import the export

```bash
./bootstrap.sh init
./bootstrap.sh import
./bootstrap.sh status
```

`init` starts Postgres (first boot runs `config/init.sh` inside the DB container to create roles), then applies `schema.sql`. The import is resumable: rerun `import` after an interruption. Run `./bootstrap.sh watch` in another terminal for live progress.

During a large import, Postgres may log `checkpoints are occurring too frequently` and thrash the disk. Steady-state `max_wal_size=24GB` is already set via compose (`PG_*` in `.env`); only if checkpoints are still a problem, temporarily raise WAL with `ALTER SYSTEM` (needs free space on the DB volume — try 64GB or higher, up to about 512GB per Hedera's restore guide):

```bash
docker exec -i hedera-mirror-db psql -U postgres -c "ALTER SYSTEM SET max_wal_size = '64GB';"
docker exec -i hedera-mirror-db psql -U postgres -c "ALTER SYSTEM SET checkpoint_timeout = '30min';"
docker exec -i hedera-mirror-db psql -U postgres -c "SELECT pg_reload_conf();"
```

**If you ran those `ALTER SYSTEM` commands**, undo them after import so compose `-c` flags take effect again (`ALTER SYSTEM` writes `postgresql.auto.conf`, which overrides compose even after container restart):

```bash
docker exec -i hedera-mirror-db psql -U postgres -c "ALTER SYSTEM RESET max_wal_size;"
docker exec -i hedera-mirror-db psql -U postgres -c "SELECT pg_reload_conf();"
```

**If you never raised WAL during import**, skip the reset — compose already applies `max_wal_size=24GB`.

`docker-entrypoint-initdb.d` only runs on an **empty** datadir. After a failed or partial first start, wipe and retry:

```bash
docker compose down
rm -rf "$HOME/hedera-postgres-data"/* "$HOME/hedera-bootstrap-data/bootstrap-logs/SKIP_DB_INIT"
./bootstrap.sh init
```

### 5. Start the Mirror Node

Only after every bootstrap file is imported:

```bash
./bootstrap.sh start-mirror
curl -s http://127.0.0.1:8080/api/v1/blocks?limit=1
docker compose logs -f importer
```

### 6. Start HTTP and WebSocket RPC

Once the importer is catching up successfully:

```bash
./bootstrap.sh start-relay
curl -s http://127.0.0.1:7546 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

HTTP RPC is `127.0.0.1:7546`, WebSocket RPC is `127.0.0.1:8546`, and the local Mirror REST API is `127.0.0.1:8080`.

## Stop and restart

After the first bootstrap, use Docker Compose for day-to-day stop/start. `./bootstrap.sh` is only for download, init, import, and the first start — not for normal restarts.

Mirror and relay services use Compose **profiles**. Always pass the same profiles you started with; a bare `docker compose up -d` starts only **`db`**.

**Mirror + JSON-RPC relay** (typical):

```bash
docker compose --profile mirror --profile relay down
docker compose --profile mirror --profile relay up -d
```

**Mirror only** (no Ethereum RPC):

```bash
docker compose --profile mirror down
docker compose --profile mirror up -d
```

Data stays on the host (`$HOME/hedera-postgres-data`, Redis dirs, etc.). The importer resumes catch-up after restart. Let `down` finish — Postgres has a 2-minute graceful shutdown.

```bash
docker compose ps
docker compose logs -f importer
```

## Database bootstrap (reference)

Extended detail for [Start](#start) steps 3–4: export modes (minimal / full / schema-only), sizing, hardware, and alternatives. Follow the Start steps to run bootstrap; use this section when choosing an export or planning disk.

### Source

Requester-pays export: `gs://mirrornode-db-export/MAINNET/<version>/`.

Downloads go under `$HOME/hedera-bootstrap-data` — never `/tmp`.

### Minimal vs full export (Atma)

This setup’s `./bootstrap.sh download` uses the **minimal** mainnet export: it skips `*_atma.csv.gz`.

**What is Atma?** [atma.io](https://hedera.com/blog/avery-dennisons-atma-io-connected-product-cloud-to-utilize-the-hedera-network-to-account-for-carbon-emissions-of-billions-of-unique-items/) (Avery Dennison) — connected-product / carbon-accounting traffic on Hedera, a very large share of mainnet volume. Hedera splits that history into separate `*_atma.csv.gz` files so operators can bootstrap without those rows.

| Mode | How | History | What’s missing | Compressed download (approx.) | After Postgres import |
| --- | --- | --- | --- | --- | --- |
| **Minimal (default)** | `./bootstrap.sh download` | Full timeline of non-Atma txs / receipts / logs | Atma bulk rows only | **~1.18 TiB** compressed on GCS for `0.156.0` | Often ~2–4+ TiB; leave headroom — larger than the `.csv.gz` download (indexes, WAL) |
| **Full (with Atma)** | `./bootstrap.sh download-full` | Complete mainnet history including Atma | Nothing from the export | **~13.59 TiB** compressed on GCS for `0.156.0` | Can approach the upstream ~tens of TiB / ~50 TiB class |
| **Schema-only** | `./bootstrap.sh download-schema` | From ~now forward only | All history before start | Kilobytes | Small; grows with live catch-up |

Minimal is still **full history without Atma** — not a tip-only snapshot. Enough for typical EVM / log RPC. Use `./bootstrap.sh download-full` (alias `download-atma`) only if you need Atma’s historical records; use schema-only only if you cannot store the minimal download.

Import uses `manifest.minimal.csv` after `./bootstrap.sh download` (Atma rows stripped from `manifest.csv`). Full download uses `manifest.csv`. If `start-mirror` reports `FAILED_TO_IMPORT` on `*_atma.csv.gz` files after a minimal import, run `./bootstrap.sh repair-minimal-tracking` (or pull the latest `bootstrap.sh`, which fixes this automatically when only Atma files failed).

### Hardware (upstream guide)

For a busy Mirror Node: PostgreSQL 16+, ~10 vCPU, ~40 GiB RAM. Disk **1–55 TiB** depending on retention; complete mainnet (with Atma-scale data) can approach ~50 TiB. Skipping Atma puts you on the **low end** of that band, but still plan **several TiB** free for the DB volume after a minimal import — not just the ~1.18 TiB GCS download.

Steady-state Postgres tuning from the [Mirror Node database guide](https://github.com/hiero-ledger/hiero-mirror-node/blob/v0.156.0/docs/database/README.md) lives in `config/postgresql.conf` and is applied by the `db` service in `docker-compose.yml` (`max_wal_size=24GB`, `checkpoint_timeout=30min`, etc.). Recreate the DB container to pick up changes (`docker compose up -d db`). Temporary import-time WAL bumps stay manual — see [step 4](#4-initialize-postgresql-and-import-the-export).

### Check export size before download

Measured with `gcloud storage du -s -r --readable-sizes` on `0.156.0` (2026-08-22):

| Export | GCS compressed size |
| --- | --- |
| Full (with Atma) | **13.59 TiB** — `gs://mirrornode-db-export/MAINNET/0.156.0/` |
| Minimal (non-Atma) | **1.18 TiB** — same prefix, `--exclude-name-pattern='*_atma.csv.gz'` |

Re-run for other versions before downloading:

**Full export** (includes Atma — for `download-full`):

```bash
gcloud storage du -s -r --readable-sizes --billing-project=<GCP_PROJECT_ID> \
  gs://mirrornode-db-export/MAINNET/<version>/
```

**Minimal export** (what `./bootstrap.sh download` pulls — excludes `*_atma.csv.gz`):

```bash
gcloud storage du -s -r --readable-sizes --billing-project=<GCP_PROJECT_ID> \
  --exclude-name-pattern='*_atma.csv.gz' \
  gs://mirrornode-db-export/MAINNET/<version>/
```

Example for `0.156.0`:

```bash
gcloud storage du -s -r --readable-sizes --billing-project=e2s-misc \
  --exclude-name-pattern='*_atma.csv.gz' \
  gs://mirrornode-db-export/MAINNET/0.156.0/
```

### Partial history (skip the backfill)

If you cannot store the minimal export, skip historical CSV import and sync forward from ~now. You lose this repo’s usual genesis-history logs goal.

```bash
./bootstrap.sh download-schema   # schema.sql.gz + MIRRORNODE_VERSION.gz only
./bootstrap.sh init
./bootstrap.sh start-mirror      # no import — empty DB, catch up from live streams
```

`hiero.mirror.importer.startDate` defaults to “now” when unset and the DB is empty. Skip `import` / `status` / `watch`; `start-mirror` / `start-relay` detect schema-only mode automatically.

## State retention

Importer retention is disabled, so imported non-Atma receipts and logs are not intentionally pruned. Enabling `hiero.mirror.importer.retention.enabled` deletes old transaction and balance data and conflicts with this repository's historical-log goal.

The relay limits a single `eth_getLogs` request to 10,000 blocks by default in `.env`; paginate larger ranges.

## Upgrade

Bootstrap and first-start the importer with the version recorded in `MIRRORNODE_VERSION.gz`. After it starts cleanly and catches up, upgrade `MIRROR_NODE_VERSION` separately so database migrations run from the known-compatible schema. Do not point a newer importer at a fresh older export before the version-matched first start.

Check upstream releases against your pin (and running containers, if up):

```bash
./check-upgrade.sh
```

After bumping mirror images, restart the API proxy so nginx picks up new `rest` / `rest-java` container addresses:

```bash
docker compose restart api-proxy
```

Relay **0.78+** images use a single `dist/index.js` binary; the WebSocket container sets `RPC_WS_ENABLED=true` (the old `packages/ws-server/dist/index.js` path no longer exists).

**Block streams cutover (2026):** Hedera mainnet is replacing record streams with block streams by September 2026 (consensus node v0.77). Mirror Node operators must be running v0.160.0 or later before that date, or ingestion stops at cutover — see the [block streams announcement](https://hedera.com/blog/block-streams-replace-the-record-stream-by-default-starting-september-2026-action-required-by-mirror-node-operators/). Watch `gs://mirrornode-db-export/MAINNET/` for a `0.160.0`+ export and plan the upgrade well before the deadline.

Docs: [Mirror Node bootstrap](https://github.com/hiero-ledger/hiero-mirror-node/blob/main/docs/database/bootstrap.md) · [Mirror Node GCS setup](https://docs.hedera.com/operators/mirror-node/run-your-own/gcs) · [JSON-RPC Relay](https://github.com/hiero-ledger/hiero-json-rpc-relay)
