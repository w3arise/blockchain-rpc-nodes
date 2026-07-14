# ApeChain (Caldera Nitro)

Mainnet pruned replica. Settles on Arbitrum One. Chain data: `$HOME/apechain-data`.

Requires a synced **Arbitrum One** RPC (`arbitrum/` or private endpoint).

## Start

```bash
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
