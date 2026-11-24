# XLayer (op-geth + op-node + cdk-erigon) — deprecated

> **Deprecated.** Upstream `op-geth` for X Layer is end-of-support and archived ([okx/op-geth](https://github.com/okx/op-geth)). It will not follow the L1 Glamsterdam hardfork, and new X Layer hardforks ship on `xlayer-reth` only. Use [`xlayer-reth/`](../xlayer-reth/) for new setups. To migrate, sync `xlayer-reth` alongside this node and switch once it is validated. This setup gets no further pin bumps.

Mainnet OP Stack node with archival cdk-erigon backend. Chain data: `$HOME/xlayer-op-geth-data`, `$HOME/xlayer-op-node-data`, `$HOME/xlayer-cdk-erigon-data`.

Replacement: [`xlayer-reth/`](../xlayer-reth/) (xlayer-reth + op-node). Ports don't clash, so both can run side by side during migration.

## Start

```bash
./configure.sh          # create .env, set EXT_IP
./create-jwt.sh
# edit .env — set L1_RPC_URL, L1_BEACON_URL, ZKEVM_L1_RPC_URL
./init-database.sh      # from scratch only
docker compose build    # cdk-erigon image
docker compose up -d
```

## Snapshot

Restore op-geth snapshot data into `$HOME/xlayer-op-geth-data`, then skip `init-database.sh`:

```bash
./configure.sh          # create .env, set EXT_IP
./create-jwt.sh
# edit .env — set L1_RPC_URL, L1_BEACON_URL, ZKEVM_L1_RPC_URL
docker compose build    # cdk-erigon image
docker compose up -d
```

## Host ports

P2P port 35303 (TCP + UDP) is exposed for incoming peers. RPC ports 28545 (HTTP) and 28546 (WS) are localhost-only.

Docs: [X Layer docs](https://www.okx.com/xlayer/docs) · [okx/xlayer-erigon](https://github.com/okx/xlayer-erigon)
