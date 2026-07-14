# Worldchain (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/worldchain-op-reth-data`, `$HOME/worldchain-op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

## Testnet

For World Chain Sepolia, edit `docker-compose.yml` (`--chain=worldchain-sepolia`) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [World Chain node setup](https://docs.world.org/world-chain/reference/node-setup) · [Optimism node operators](https://docs.optimism.io/node-operators/tutorials/node-from-docker)
