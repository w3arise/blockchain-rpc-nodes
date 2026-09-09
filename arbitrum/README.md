# Arbitrum (nitro)

Mainnet archive node. Chain data: `$HOME/arbitrum-data`.

## State retention

PathDB archive: `STATE_SCHEME=path`, `STATE_HISTORY=0`, plus `--execution.caching.archive` in compose.

**Do not set `STATE_HISTORY` to a non-zero value** on an existing archive datadir or after restoring an archive snapshot — Nitro prunes history immediately. For pruned full-node behavior (~24h retention), set `STATE_HISTORY=345600` and remove `--execution.caching.archive` only on a fresh sync or when you accept the prune. See [AGENTS.md](../AGENTS.md#arbitrum-nitro-pathdb--pbss).

## Start

```bash
cp env.template .env    # set L1_URL, L1_BEACON_URL
docker compose up -d
```

## Upgrades

**Not tag-only.** Do not run `./scripts/apply-tag-only.sh` for Arbitrum until it has a row in [`scripts/auto-upgrade.yaml`](../scripts/auto-upgrade.yaml). Architecture: [AUTO_UPGRADES.md](../AUTO_UPGRADES.md).

Pinned image: `NITRO_IMAGE` in `env.template` (`v3.11.3-beb2108`). Nitro 3.8 and 3.10 apply **one-way** database schema; you cannot roll back to 3.7.x / 3.9.x without restoring a backup.

On a live host after the pin is on `main`:

1. Stop compose. Cold-copy `$HOME/arbitrum-data`.
2. `git pull --ff-only`. Set `NITRO_IMAGE` in `.env` to match `env.template` (do not recopy the whole template — that wipes `L1_URL` / `L1_BEACON_URL`).
3. `docker compose pull && docker compose up -d`.

Keep `STATE_HISTORY=0` and `--execution.caching.archive` on this archive datadir.

Same-series `v3.11.*` patches may be allowlisted later; that is a separate, user-approved YAML row.

Docs: [Run an Arbitrum full node](https://docs.arbitrum.io/run-arbitrum-node/run-full-node) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
