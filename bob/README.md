# Bob (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/op-reth-data`, `$HOME/op-node-data`.

## Start

```bash
cp env.template .env    # set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON, EXT_IP
./create-jwt.sh
docker compose up -d
```

Docs: [BOB docs](https://docs.gobob.xyz/) · [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration)
