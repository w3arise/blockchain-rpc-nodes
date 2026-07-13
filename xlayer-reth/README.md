# XLayer (xlayer-reth + op-node)

Mainnet OP Stack node (reth alternative to `xlayer/`). Chain data: `$HOME/xlayer-op-reth-data`, `$HOME/xlayer-reth-op-node-data`.

## Start

```bash
./create-jwt.sh
cp env.template .env    # set L1_RPC_URL, L1_BEACON_URL, EXT_IP
./init-database.sh      # from scratch only
docker compose up -d
```

## Snapshot

Restore op-reth snapshot data into `$HOME/xlayer-op-reth-data`, then skip `init-database.sh`:

```bash
./create-jwt.sh
cp env.template .env
docker compose up -d
```

Snapshot: [reth-mainnet-latest](https://static.okx.com/cdn/chain/xlayer/snapshot/reth-mainnet-latest)

Docs: [X Layer docs](https://www.okx.com/xlayer/docs) · [okx/xlayer-reth](https://github.com/okx/xlayer-reth)
