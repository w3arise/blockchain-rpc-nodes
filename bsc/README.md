# BSC (bsc-geth)

Mainnet RPC node. Chain data: `$HOME/chain-data` (override with `HOST_DATADIR` in `.env`).

## Start

```bash
./configure.sh          # creates .env, sets EXT_IP from ip.me
docker compose up -d
```

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (default `30307`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [BSC full node](https://docs.bnbchain.org/bnb-smart-chain/developers/node_operators/full_node/) · [bnb-chain/bsc](https://github.com/bnb-chain/bsc)
