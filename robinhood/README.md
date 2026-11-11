# Robinhood Chain (nitro)

Mainnet archive node on Ethereum L1. Chain data: `$HOME/robinhood-data`.

Requires synced **Ethereum** execution + beacon endpoints (`L1_ETH_URL`, `L1_ETH_BEACON_URL`).

The `nitro-node` image runs as **`user` (UID 1000, GID 1000)**. Datadir inside the container: `/home/user/.arbitrum`.

`eth_sendRawTransaction` is forwarded to the Robinhood sequencer (`FORWARDING_TARGET` in `.env`). Reads are served locally from the archive datadir.

Sequencer feeds: `FEED_URLS` is a comma-separated list (no spaces) passed to `--node.feed.input.url`. The node reads every feed at once and deduplicates by sequence number; the default is the main feed plus the delayed backup feed. On an existing `.env`, replace `FEED_URL` / `SECONDARY_FEED_URL` with `FEED_URLS` before recreating the node: compose refuses to start without it ([docs](https://docs.robinhood.com/chain/run-a-full-node/#recommended-run-both-feeds-simultaneously)).

## State retention

PathDB archive: `STATE_SCHEME=path`, `STATE_HISTORY=0`, plus `--execution.caching.archive` in compose.

**Do not set `STATE_HISTORY` to a non-zero value** on an existing archive datadir or after restoring an archive snapshot — Nitro prunes history immediately. For pruned full-node behavior (~24h retention), set `STATE_HISTORY=345600` and remove `--execution.caching.archive` only on a fresh sync or when you accept the prune. See [AGENTS.md](../AGENTS.md#arbitrum-nitro-pathdb--pbss).

## Start

```bash
mkdir -p "$HOME/robinhood-data"
sudo chown -R 1000:1000 "$HOME/robinhood-data"   # skip if your UID is already 1000
chmod o+r config/*
cp env.template .env    # set L1_ETH_URL, L1_ETH_BEACON_URL (feeds default in template)
docker compose up -d
```

Same-series Nitro patches are **tag-only**: `./scripts/apply-tag-only.sh robinhood`

## Feed relay (optional)

`docker-compose.relay.yml` runs the Nitro `relay` binary: it reads `FEED_RELAY_INPUT_URL` and re-serves the feed on `FEED_RELAY_BIND_ADDR:FEED_RELAY_PORT` (host network, default `127.0.0.1:9642`).

```bash
docker compose -f docker-compose.relay.yml up -d
```

On an existing `.env`, first copy the `FEED_RELAY_*` keys from `env.template`. To feed the node from the relay, set `FEED_URLS=ws://127.0.0.1:9642` in `.env` (or add it to the list) and recreate the node.

Same-series relay patches are **tag-only** and apply apart from the node: `./scripts/apply-tag-only.sh robinhood-feed-relay`. A `COMPOSE_PROJECT_NAME` in `.env` also renames the relay project (it overrides `name:`), so compose then reports the other file's containers as orphans; never pass `--remove-orphans` in that case.

## Snapshot

No official snapshot URL is published. Sync from genesis via the sequencer feed, or add `--init.url=<SNAPSHOT_URL>` to `docker-compose.yml` for a one-time first start with an empty datadir if you have a snapshot source.

## Testnet

Testnet (chain ID 46630) uses `robinhood-chain-testnet-info.json` and omits the custom genesis file. See [Run a full node](https://docs.robinhood.com/chain/run-a-full-node/).

Docs: [Run a full node](https://docs.robinhood.com/chain/run-a-full-node/) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
