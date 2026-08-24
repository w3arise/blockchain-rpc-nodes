# Plume (nitro)

Mainnet archive node on Ethereum L1 (Conduit Orbit, AnyTrust DA). Chain data: `$HOME/plume-data`.

Requires synced **Ethereum** execution + beacon endpoints (`L1_ETH_URL`, `L1_ETH_BEACON_URL`).

The `nitro-node` image runs as **`user` (UID 1000, GID 1000)**. Datadir inside the container: `/home/user/.arbitrum`.

WebSocket RPC listens on host `${WS_PORT}` (default `8547`) → container `8547`. Metrics on `${METRICS_PORT}` (default `6070`).

## State retention

Hash-scheme archive: `STATE_SCHEME=hash` (default) plus `--execution.caching.archive` in compose — matches a typical Plume external node and keeps full block/receipt/log history without historical state.

**Do not change `STATE_SCHEME` on an existing datadir** — hash and path are incompatible; your node logs show `scheme=hash`. For a fresh PathDB setup instead, use `STATE_SCHEME=path`, add `--execution.caching.state-history=0`, and sync from scratch or a path snapshot. See [AGENTS.md](../AGENTS.md#arbitrum-nitro-pathdb--pbss).

## Start

```bash
mkdir -p "$HOME/plume-data"
sudo chown -R 1000:1000 "$HOME/plume-data"   # skip if your UID is already 1000
chmod o+r config/*
cp env.template .env    # set L1_ETH_URL, L1_ETH_BEACON_URL
docker compose up -d
```

## Snapshot

No official snapshot URL is published. Sync from genesis via the sequencer feed, or add `--init.url=<SNAPSHOT_URL>` to `docker-compose.yml` for a one-time first start with an empty datadir if you have a snapshot source.

After Plume network upgrades, refresh `config/chainInfo.json` from [assets.plume.org/mainnet/chainInfo.json](https://assets.plume.org/mainnet/chainInfo.json) (use the parsed `info-json` array).

## Testnet

Plume Testnet (chain ID 98867) settles on Sepolia. Chain info: [assets.plume.org/testnet/chainInfo.json](https://assets.plume.org/testnet/chainInfo.json). Update `CHAIN_ID`, feed/DA URLs, L1 endpoints, and `FORWARDING_TARGET=https://testnet-rpc.plume.org` in `.env`.

Docs: [How to run a node](https://docs.plume.org/plume/developers/how-to-guides/how-to-run-a-node) · [Network information](https://docs.plume.org/plume/developers/network-information) · [OffchainLabs/nitro](https://github.com/OffchainLabs/nitro)
