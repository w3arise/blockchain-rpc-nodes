# Bob (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/op-reth-data`, `$HOME/op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

Docs: [BOB docs](https://docs.gobob.xyz/) · [Conduit Hub](https://hub.conduit.xyz/bob-mainnet-0) · [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration)
