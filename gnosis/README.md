# Gnosis Chain (reth_gnosis + lighthouse)

Mainnet full node. Chain data: `$HOME/gnosis-reth-data`, `$HOME/gnosis-lighthouse-data`.

## Start

```bash
cp env.template .env    # set EXT_IP, CHECKPOINT_SYNC_URL
./create-jwt.sh
docker compose up -d
```

## Upgrade

After a merged pin PR (tag-only): `./scripts/apply-tag-only.sh gnosis` from the repo root (syncs both image pins, pull, up, block_time health on execution RPC).

Manual: copy `GNOSIS_RETH_IMAGE` and `LIGHTHOUSE_IMAGE` from `env.template` into `.env`, then `docker compose pull && docker compose up -d`.

Lighthouse `v8.2.2` is an image swap (no DB migration). `reth_gnosis` `v2.1.0` is a regular upstream reth bump; existing storage-v1 datadirs keep working.

## Host ports

When running a public replica, allow inbound P2P: `P2P_PORT` (reth execution, default `25025`, TCP + UDP) and `BEACON_P2P_PORT` (lighthouse, default `9001`, TCP + UDP). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Gnosis node manual](https://docs.gnosischain.com/node/manual) · [gnosischain/reth_gnosis](https://github.com/gnosischain/reth_gnosis)
