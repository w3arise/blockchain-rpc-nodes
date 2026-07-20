# opBNB (op-geth + op-node)

Mainnet full node (PBSS + Pebble). Chain data: `$HOME/opbnb-geth`, `$HOME/opbnb-node`.

## Start

```bash
./configure.sh          # creates .env, sets EXT_IP from ip.me
# set OP_NODE__RPC_ENDPOINT (BSC L1 RPC) in .env
./create-jwt.sh
docker compose up -d
```

P2P: op-geth `${OP_GETH_P2P_PORT}` (default 37307) and op-node `${PORT__OP_NODE_P2P}` (default 9003) must be reachable on `EXT_IP`.

op-node P2P identity is persisted at `$HOME/opbnb-node/opnode_p2p_priv.txt` (auto-created on first start).

## Snapshot

PBSS snapshots: [bnb-chain/opbnb-snapshot](https://github.com/bnb-chain/opbnb-snapshot). Extract into `$HOME/opbnb-geth`, then start as above (skip genesis init).

Archive snapshots are generally unavailable; archive requires HBSS and sync from scratch.

Docs: [Run a Local Node](https://docs.bnbchain.org/bnb-opbnb/advanced/local-node/) · [Best practices](https://docs.bnbchain.org/bnb-opbnb/advanced/node-best-practices/)
