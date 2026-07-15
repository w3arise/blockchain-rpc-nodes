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

Docs: [Run an Arbitrum full node](https://docs.arbitrum.io/run-arbitrum-node/run-full-node) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
