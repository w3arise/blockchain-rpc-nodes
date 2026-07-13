# XLayer (op-geth + op-node + cdk-erigon)

Mainnet OP Stack node with archival cdk-erigon backend. Chain data: `$HOME/xlayer-op-geth-data`, `$HOME/xlayer-op-node-data`, `$HOME/xlayer-cdk-erigon-data`.

## Start

```bash
./create-jwt.sh
cp env.template .env    # set L1_RPC_URL, L1_BEACON_URL, EXT_IP
./init-database.sh      # from scratch only
docker compose build    # cdk-erigon image
docker compose up -d
```

## Snapshot

Restore op-geth snapshot data into `$HOME/xlayer-op-geth-data`, then skip `init-database.sh`:

```bash
./create-jwt.sh
cp env.template .env
docker compose build
docker compose up -d
```

Docs: [X Layer docs](https://www.okx.com/xlayer/docs) · [okx/xlayer-erigon](https://github.com/okx/xlayer-erigon)
