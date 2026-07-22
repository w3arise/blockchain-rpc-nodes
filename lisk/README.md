# Lisk (op-reth + op-node)

Mainnet OP Stack L2. Chain data: `$HOME/lisk-op-reth-data`, `$HOME/lisk-op-node-data`.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON
./create-jwt.sh
docker compose up -d
```

## Snapshot

Official archival op-reth datadir snapshots: [snapshots.lisk.com/mainnet](https://snapshots.lisk.com/mainnet) (`latest-reth-datadir`). Gelato mirror: [lisk.snapshots.gelato.cloud](https://lisk.snapshots.gelato.cloud/index.html) (`reth/archival/datadir`).

```bash
# example — resolve latest name from snapshots.lisk.com/mainnet/latest-reth-datadir, then:
tar --directory "$HOME/lisk-op-reth-data" -I lz4 -xf lisk-reth-archival-datadir-*.tar.lz4
# or: tar --directory "$HOME/lisk-op-reth-data" -xf <snapshot>.tar.gz
docker compose up -d
```

Skip a fresh genesis sync after restore. Snap sync without a snapshot: keep `OP_NODE_SYNCMODE=execution-layer` and `OP_RETH_BOOTNODES` (default in `env.template`).

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default `10411`) and `OP_NODE_P2P_PORT` (op-node, default `9222`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

## Testnet

For Lisk Sepolia, edit `docker-compose.yml` (`--chain=lisk-sepolia`, sequencer `https://rpc.sepolia-api.lisk.com`) and swap the `OP_NODE_*` network/L1/P2P vars in `.env` — see comments in `env.template`. Snapshots: [snapshots.lisk.com/sepolia](https://snapshots.lisk.com/sepolia) · [Gelato Sepolia](https://lisk.t.snapshots.gelato.cloud/index.html).

Docs: [LiskHQ/lisk-node](https://github.com/LiskHQ/lisk-node) · [Optimism node operators](https://docs.optimism.io/node-operators/tutorials/node-from-docker)
