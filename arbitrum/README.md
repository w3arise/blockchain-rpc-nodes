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

Same-series patch tags (`v3.12.*` while that is the pin) are **tag-only** — see [AUTO_UPGRADES.md](../AUTO_UPGRADES.md). CI may open a pin PR; after merge, apply on the host (do not recopy `env.template` — that wipes `L1_URL` / `L1_BEACON_URL`):

```bash
# from the repo root (hosts: clean arbitrum/ checkout)
./scripts/apply-tag-only.sh arbitrum
```

Nitro 3.8 and 3.10 apply **one-way** database schema; you cannot roll back to 3.7.x / 3.9.x without restoring a backup. Minor/major jumps (`v3.12` → `v3.13`) stay manual — stop compose, then pin and recreate.

Keep `STATE_HISTORY=0` and `--execution.caching.archive` on this archive datadir.

Docs: [Run an Arbitrum full node](https://docs.arbitrum.io/run-arbitrum-node/run-full-node) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
