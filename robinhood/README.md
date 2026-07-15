# Robinhood Chain (nitro)

Mainnet archive node on Ethereum L1. Chain data: `$HOME/robinhood-data`.

Requires synced **Ethereum** execution + beacon endpoints (`L1_ETH_URL`, `L1_ETH_BEACON_URL`).

The `nitro-node` image runs as **`user` (UID 1000, GID 1000)**. Datadir inside the container: `/home/user/.arbitrum`.

## Start

```bash
mkdir -p "$HOME/robinhood-data"
sudo chown -R 1000:1000 "$HOME/robinhood-data"   # skip if your UID is already 1000
cp env.template .env    # set L1_ETH_URL, L1_ETH_BEACON_URL
docker compose up -d
```

## Snapshot

No official snapshot URL is published. Sync from genesis via the sequencer feed, or add `--init.url=<SNAPSHOT_URL>` to `docker-compose.yml` for a one-time first start with an empty datadir if you have a snapshot source.

## Testnet

Testnet (chain ID 46630) uses `robinhood-chain-testnet-info.json` and omits the custom genesis file. See [Run a full node](https://docs.robinhood.com/chain/run-a-full-node/).

Docs: [Run a full node](https://docs.robinhood.com/chain/run-a-full-node/) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
