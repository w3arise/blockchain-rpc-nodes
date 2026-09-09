# Gnosis Chain (reth_gnosis + lighthouse)

Mainnet full node. Chain data: `$HOME/gnosis-reth-data`, `$HOME/gnosis-lighthouse-data`.

## Start

```bash
cp env.template .env    # set EXT_IP, CHECKPOINT_SYNC_URL
./create-jwt.sh
docker compose up -d
```

## Upgrade

Copy `GNOSIS_RETH_IMAGE` and `LIGHTHOUSE_IMAGE` from `env.template` into `.env`, then:

```bash
docker compose pull
docker compose up -d
```

Lighthouse `v8.2.2` is an image swap (no DB migration). `reth_gnosis` `v2.1.0` is a regular upstream reth bump; existing storage-v1 datadirs keep working.

Docs: [Gnosis node manual](https://docs.gnosischain.com/node/manual) · [gnosischain/reth_gnosis](https://github.com/gnosischain/reth_gnosis)
