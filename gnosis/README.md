# Gnosis Chain (reth_gnosis + lighthouse)

Mainnet full node. Chain data: `$HOME/gnosis-reth-data`, `$HOME/gnosis-lighthouse-data`.

## Start

```bash
cp env.template .env    # set EXT_IP, CHECKPOINT_SYNC_URL
./create-jwt.sh
docker compose up -d
```

Docs: [Gnosis node manual](https://docs.gnosischain.com/node/manual) · [gnosischain/reth_gnosis](https://github.com/gnosischain/reth_gnosis)
