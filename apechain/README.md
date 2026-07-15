# ApeChain (Caldera Nitro)

Mainnet pruned replica. Settles on Arbitrum One. Chain data: `$HOME/apechain-data`.

Requires a synced **Arbitrum One** RPC (`arbitrum/` or private endpoint).

The Caldera image runs as **`user` (UID 1000, GID 1000)**. Datadir inside the container: `/home/user/.arbitrum`.

## Node mode & disk

| | This setup |
| --- | --- |
| **Type** | Full **replica** (not light, not sequencer) |
| **State retention** | **Pruned** — `execution.caching.archive: false` in `nodeConfig.json` |
| **Historical state** | Recent only (PathDB auto-prunes older state; not an archive node) |
| **RPC use** | Current blocks, recent `eth_call`, standard queries — not full historical archive queries |

This is **not** an archive node. For `eth_call` at very old blocks or deep historical traces, use a public archive RPC or run with `"archive": true` (much larger disk).

**Disk (pruned, rough estimate):**

| Stage | Size |
| --- | --- |
| Syncing from genesis (no snapshot) | Grows during catch-up; fast feed sync is normal |
| Steady state today | ~**100–300 GB** (chain is young vs Arbitrum One) |
| Plan headroom | **500 GB–1 TB** NVMe free |

Arbitrum One pruned nodes are ~1.4 TB; ApeChain is a smaller L3 — expect far less, but monitor `$HOME/apechain-data` as the chain grows. Snapshot restore needs ~2× the archive size temporarily during extraction.

## Datadir permissions

Docker cannot create bind-mount host directories as UID 1000 — if `$HOME/apechain-data` is missing, the daemon creates it as **root**. Nitro then fails to write chain data.

**Before the first `docker compose up`**, create the directory with the correct owner:

```bash
mkdir -p "$HOME/apechain-data"
sudo chown -R 1000:1000 "$HOME/apechain-data"
```

If your login user is already UID 1000, `mkdir -p "$HOME/apechain-data"` alone is enough (skip `chown`).

If compose already created a root-owned datadir:

```bash
docker compose down
sudo chown -R 1000:1000 "$HOME/apechain-data"
docker compose up -d
```

## Start

```bash
mkdir -p "$HOME/apechain-data"
sudo chown -R 1000:1000 "$HOME/apechain-data"   # skip if your UID is already 1000
cp env.template .env    # set PARENT_CHAIN_RPC (Arbitrum One)
docker compose up -d
```

## Snapshot

Official snapshot (Sep 22, 2025): [Caldera S3](https://caldera-chain-data-snapshots.s3.us-west-2.amazonaws.com/exported-snapshots/nitro-apechain/nitro-apechain-2025-Sep-22.tar)

Restore into `$HOME/apechain-data/apechain/nitro/`, then start compose. Verify the URL is reachable from your host before downloading.

Alternatively, add `--init.url=<snapshot-url>` to `docker-compose.yml` command for a one-time first start with an empty datadir.

## Testnet

Curtis testnet uses image `public.ecr.aws/i6b2w2n6/nitro-node:curtis3` and Arbitrum Sepolia as parent. See [ApeChain run-node docs](https://docs.apechain.com/run-node).

Docs: [Run a replica node](https://docs.apechain.com/run-node) · [replica-guide-apechain-mainnet](https://github.com/ConstellationCrypto/replica-guide-apechain-mainnet)
