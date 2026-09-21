# Bob (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/op-reth-data`, `$HOME/op-node-data`.

## Start

```bash
cp env.template .env    # set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON, EXT_IP
./create-jwt.sh
docker compose up -d
```

After Conduit network upgrades, run `./check-genesis.sh` (slug **`bob-mainnet-0`**) and copy any new `OP_NODE_OVERRIDE_*` values into `.env`. Restart op-node + op-reth after genesis or override changes (no resync).

Docs: [BOB docs](https://docs.gobob.xyz/) · [Conduit Hub](https://hub.conduit.xyz/bob-mainnet-0) · [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration)
