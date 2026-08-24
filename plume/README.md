# Plume (nitro)

Mainnet archive node on Ethereum L1 (Conduit Orbit, AnyTrust DA). Chain data: `$HOME/plume-data`.

Requires synced **Ethereum** execution + beacon endpoints (`L1_ETH_URL`, `L1_ETH_BEACON_URL`).

The `nitro-node` image runs as **`user` (UID 1000, GID 1000)**. Datadir inside the container: `/home/user/.arbitrum`.

WebSocket RPC listens on host `${WS_PORT}` (default `8547`) → container `8547`. Metrics on `${METRICS_PORT}` (default `6070`).

## State retention

Hash-scheme archive: `STATE_SCHEME=hash` (default) plus `--execution.caching.archive` in compose. Archive mode retains **full historical state** (past `eth_call`, balances, storage proofs) as well as blocks, receipts, and logs — an archive node prunes nothing by definition. See [Arbitrum glossary — Archive node](https://docs.arbitrum.io/intro/glossary).

Without `--execution.caching.archive`, a hash-scheme **full** node still keeps block/receipt/log history but prunes old state (offline, via `--init.prune`). PathDB (`STATE_SCHEME=path`) is an alternative layout with online pruning; use `--execution.caching.state-history=0` with archive on a fresh path datadir.

**Do not change `STATE_SCHEME` on an existing datadir** — hash and path are incompatible. See [AGENTS.md](../AGENTS.md#arbitrum-nitro-pathdb--pbss).

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
