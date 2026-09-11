# Bob (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/op-reth-data`, `$HOME/op-node-data`.

## Start

```bash
cp env.template .env    # set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON, EXT_IP
./create-jwt.sh
docker compose up -d
```

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `RETH_PORT` (op-reth, default `10101`) and `DISCOVERY_V5_PORT` (discv5, default `9201`). RPC stays localhost-only by default.

Docs: [BOB docs](https://docs.gobob.xyz/) · [Conduit Hub](https://hub.conduit.xyz/bob-mainnet-0) · [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration)
