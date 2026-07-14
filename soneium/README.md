# Soneium (op-reth + op-node)

Mainnet rollup node. Chain data: `$HOME/soneium-op-reth-data`, `$HOME/soneium-op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

## Snapshot

Restore op-reth data from a third-party snapshot to skip initial sync. See [Alchemy Soneium snapshots](https://www.alchemy.com/docs/snapshots/soneium). After restore, skip a fresh sync and run `docker compose up -d`.

## Testnet

For Minato (Sepolia L1), edit `docker-compose.yml` (`--chain=soneium-minato-sepolia`) and swap the `OP_NODE_*` network/L1 vars in `.env` — see comments in `env.template`.

Docs: [Soneium docs](https://docs.soneium.org/) · [Optimism node operators](https://docs.optimism.io/node-operators/tutorials/node-from-docker)
