# Optimism (op-reth + op-node)

Mainnet archive node. Chain data: `$HOME/op-reth-datadir`, `$HOME/op-node-datadir`.

## Start

```bash
cp env.template .env    # set L1_RPC, L1_BEACON, EXT_IP, P2P_PORT
./create-jwt.sh
docker compose up -d
```

Docs: [Optimism node operators](https://docs.optimism.io/operators/node-operators/configuration) · [ethereum-optimism/optimism](https://github.com/ethereum-optimism/optimism)
