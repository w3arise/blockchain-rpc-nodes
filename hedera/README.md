# Hedera (JSON-RPC Relay + Mirror Node)

Mainnet EVM JSON-RPC endpoint backed by the Hiero JSON-RPC Relay and a self-hosted Mirror Node. Data is stored in `$HOME/hedera-postgres-data`; bootstrap files and logs are stored in `$HOME/hedera-bootstrap-data`.

This is not a Hedera consensus node. Reads are served from the local Mirror Node, while `eth_sendRawTransaction` submits to Hedera consensus nodes using the configured relay operator account.

## Start

1. Install Docker, `gcloud`, `jq`, and `gzip`. Authenticate a GCP project with billing enabled:

   ```bash
   gcloud auth login
   ```

   Create GCP HMAC credentials for the live importer as described in the [GCS mirror-node guide](https://docs.hedera.com/operators/mirror-node/run-your-own/gcs).

2. Create configuration and secrets:

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

3. Confirm the available export and version, then download the minimal mainnet database (see [Database bootstrap](#database-bootstrap) for Atma vs full export, sizing, and size-check commands):

   ```bash
   ./bootstrap.sh list
   ./bootstrap.sh download
   ```

   `MIRROR_NODE_VERSION` must match the selected export's `MIRRORNODE_VERSION.gz`. The initial importer must run that same version.

   If you cannot store the minimal export, use [Partial history](#partial-history-skip-the-backfill) instead (`./bootstrap.sh download-schema` — sync from ~now, no CSV backfill).

4. Initialize PostgreSQL and import the export:

   ```bash
   ./bootstrap.sh init
   ./bootstrap.sh import
   ./bootstrap.sh status
   ```

   `init` starts Postgres (first boot runs `config/init.sh` inside the DB container to create roles), then applies `schema.sql`. The import is resumable: rerun `import` after an interruption. Run `./bootstrap.sh watch` in another terminal for live progress.

   `docker-entrypoint-initdb.d` only runs on an **empty** datadir. After a failed or partial first start, wipe and retry:

   ```bash
   docker compose down
   rm -rf "$HOME/hedera-postgres-data"/* "$HOME/hedera-bootstrap-data/bootstrap-logs/SKIP_DB_INIT"
   ./bootstrap.sh init
   ```

5. Start the Mirror Node only after every bootstrap file is imported:

   ```bash
   ./bootstrap.sh start-mirror
   curl -s http://127.0.0.1:8080/api/v1/blocks?limit=1
   docker compose logs -f importer
   ```

6. Once the importer is catching up successfully, start HTTP and WebSocket RPC:

   ```bash
   ./bootstrap.sh start-relay
   curl -s http://127.0.0.1:7546 \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
   ```

   HTTP RPC is `127.0.0.1:7546`, WebSocket RPC is `127.0.0.1:8546`, and the local Mirror REST API is `127.0.0.1:8080`.

## Database bootstrap

### Source

Requester-pays export: `gs://mirrornode-db-export/MAINNET/<version>/`.

Downloads go under `$HOME/hedera-bootstrap-data` — never `/tmp`.

### Minimal vs full export (Atma)

This setup’s `./bootstrap.sh download` uses the **minimal** mainnet export: it skips `*_atma.csv.gz`.

**What is Atma?** [atma.io](https://hedera.com/blog/avery-dennisons-atma-io-connected-product-cloud-to-utilize-the-hedera-network-to-account-for-carbon-emissions-of-billions-of-unique-items/) (Avery Dennison) — connected-product / carbon-accounting traffic on Hedera, a very large share of mainnet volume. Hedera splits that history into separate `*_atma.csv.gz` files so operators can bootstrap without those rows.

| Mode | How | History | What’s missing | Compressed download (approx.) | After Postgres import |
| --- | --- | --- | --- | --- | --- |
| **Minimal (default)** | `./bootstrap.sh download` | Full timeline of non-Atma txs / receipts / logs | Atma bulk rows only | ~1.2 TiB for `0.156.0` (measure with the size check below) | Often ~2–4+ TiB; leave headroom — larger than the `.csv.gz` download (indexes, WAL) |
| **Full (with Atma)** | Same GCS rsync **without** the Atma exclude | Complete mainnet history including Atma | Nothing from the export | Multi‑TiB larger than minimal (`du -s` on the folder) | Can approach the upstream ~tens of TiB / ~50 TiB class |
| **Schema-only** | `./bootstrap.sh download-schema` | From ~now forward only | All history before start | Kilobytes | Small; grows with live catch-up |

Minimal is still **full history without Atma** — not a tip-only snapshot. Enough for typical EVM / log RPC. Use full export only if you need Atma’s historical records; use schema-only only if you cannot store the minimal download.

### Hardware (upstream guide)

For a busy Mirror Node: PostgreSQL 16+, ~10 vCPU, ~40 GiB RAM. Disk **1–55 TiB** depending on retention; complete mainnet (with Atma-scale data) can approach ~50 TiB. Skipping Atma puts you on the **low end** of that band, but still plan **several TiB** free for the DB volume after a minimal import — not just the ~1.2 TiB download.

### Check export size before download

Full folder (includes Atma — larger than what we download):

```bash
gcloud storage du -s --readable-sizes --billing-project=<GCP_PROJECT_ID> \
  gs://mirrornode-db-export/MAINNET/<version>/
```

What `./bootstrap.sh download` actually pulls (excludes `*_atma.csv.gz`):

```bash
gcloud storage ls -l --billing-project=<GCP_PROJECT_ID> \
  gs://mirrornode-db-export/MAINNET/<version>/** \
  | grep -v '_atma\.csv\.gz' \
  | awk '$1 ~ /^[0-9]+$/ {sum += $1} END {printf "%.2f GiB\n", sum/1024/1024/1024}'
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

**Block streams cutover (2026):** Hedera mainnet is replacing record streams with block streams by September 2026 (consensus node v0.77). Mirror Node operators must be running v0.160.0 or later before that date, or ingestion stops at cutover — see the [block streams announcement](https://hedera.com/blog/block-streams-replace-the-record-stream-by-default-starting-september-2026-action-required-by-mirror-node-operators/). Watch `gs://mirrornode-db-export/MAINNET/` for a `0.160.0`+ export and plan the upgrade well before the deadline.

Docs: [Mirror Node bootstrap](https://github.com/hiero-ledger/hiero-mirror-node/blob/main/docs/database/bootstrap.md) · [Mirror Node GCS setup](https://docs.hedera.com/operators/mirror-node/run-your-own/gcs) · [JSON-RPC Relay](https://github.com/hiero-ledger/hiero-json-rpc-relay)
