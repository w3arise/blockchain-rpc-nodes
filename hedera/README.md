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

   Edit `.env`: set `GCP_PROJECT_ID`, `GCP_ACCESS_KEY`, and `GCP_SECRET_KEY`. To submit transactions, also set a funded `OPERATOR_ID_MAIN` and its `OPERATOR_KEY_MAIN`; otherwise set `READ_ONLY=true`. Rerun `./configure.sh` after editing.

   `configure.sh` generates the PostgreSQL role passwords once and copies `.env` into `secrets-backups/` (gitignored) whenever it generates new ones, then pauses for confirmation. These passwords get set on roles **inside** the database during `./bootstrap.sh init`; if `.env` is lost afterward and regenerated, the new passwords won't match the existing database and every service will fail to authenticate. Copy the backup file to secure, offline storage before continuing.

3. Confirm the available export and version, then download the minimal mainnet database:

   ```bash
   ./bootstrap.sh list
   ./bootstrap.sh download
   ```

   `MIRROR_NODE_VERSION` must match the selected export's `MIRRORNODE_VERSION.gz`. The initial importer must run that same version.

4. Initialize PostgreSQL and import the export:

   ```bash
   ./bootstrap.sh init
   ./bootstrap.sh import
   ./bootstrap.sh status
   ```

   The import is resumable: rerun `import` after an interruption. Run `./bootstrap.sh watch` in another terminal for live progress.

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

The official requester-pays export is downloaded from `gs://mirrornode-db-export/MAINNET/<version>/`. Downloads use `$HOME/hedera-bootstrap-data`, never `/tmp`.

The minimal mainnet export excludes `*_atma.csv.gz` bulk data. It retains the remaining historical transaction, receipt, and log data, but queries involving omitted Atma traffic are not complete. Use the full export instead if every Atma record is required.

Upstream sizing for a busy full-history Mirror Node is PostgreSQL 16+, about 10 vCPU, 40 GiB RAM, and 1–55 TiB depending on retained history; Hedera's operator guide warns that complete mainnet history can require roughly 50 TiB. Check the actual size for the current export before downloading:

```bash
gcloud storage du -s --readable-sizes --billing-project=<GCP_PROJECT_ID> \
  gs://mirrornode-db-export/MAINNET/<version>/
```

### Partial history (skip the full backfill)

If you don't have room for the full (still multi-TiB) minimal export, you can skip historical backfill entirely and start the Mirror Node from ~now instead. This sacrifices this repo's usual historical-logs goal in exchange for a much smaller disk footprint — only use this if recent-forward data is acceptable for your use case.

```bash
./bootstrap.sh download-schema   # fetches only schema.sql.gz + MIRRORNODE_VERSION.gz, not the CSV data
./bootstrap.sh init
./bootstrap.sh start-mirror       # no ./bootstrap.sh import step — the DB starts empty
```

This works because `hiero.mirror.importer.startDate` defaults to "now" when it's unset and the database is empty, so the importer syncs forward from the live record/block stream instead of backfilling. `./bootstrap.sh import` and `status`/`watch` are not used in this path; `start-mirror`/`start-relay` detect schema-only mode automatically and skip the historical-import completeness check.

## State retention

Importer retention is disabled, so imported non-Atma receipts and logs are not intentionally pruned. Enabling `hiero.mirror.importer.retention.enabled` deletes old transaction and balance data and conflicts with this repository's historical-log goal.

The relay limits a single `eth_getLogs` request to 10,000 blocks by default in `.env`; paginate larger ranges.

## Upgrade

Bootstrap and first-start the importer with the version recorded in `MIRRORNODE_VERSION.gz`. After it starts cleanly and catches up, upgrade `MIRROR_NODE_VERSION` separately so database migrations run from the known-compatible schema. Do not point a newer importer at a fresh older export before the version-matched first start.

**Block streams cutover (2026):** Hedera mainnet is replacing record streams with block streams by September 2026 (consensus node v0.77). Mirror Node operators must be running v0.160.0 or later before that date, or ingestion stops at cutover — see the [block streams announcement](https://hedera.com/blog/block-streams-replace-the-record-stream-by-default-starting-september-2026-action-required-by-mirror-node-operators/). Watch `gs://mirrornode-db-export/MAINNET/` for a `0.160.0`+ export and plan the upgrade well before the deadline.

Docs: [Mirror Node bootstrap](https://github.com/hiero-ledger/hiero-mirror-node/blob/main/docs/database/bootstrap.md) · [Mirror Node GCS setup](https://docs.hedera.com/operators/mirror-node/run-your-own/gcs) · [JSON-RPC Relay](https://github.com/hiero-ledger/hiero-json-rpc-relay)
