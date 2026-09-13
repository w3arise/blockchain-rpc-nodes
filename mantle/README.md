# Mantle (mantle-op-geth + mantle-op-node)

Mainnet OP Stack L2 (chain ID **5000**), **hash-full**: full blocks/receipts/logs from the v2 regenesis, pruned state. Chain data: `$HOME/mantle-op-geth-data`, `$HOME/mantle-op-node-data`.

Official images (`mantlenetworkio/mantle-op-geth` + `mantlenetworkio/mantle-op-node`). Stock op-reth cannot follow Mantle’s custom forks.

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env (Ethereum mainnet)
./create-jwt.sh
./restore-snapshot.sh   # required — official full chaindata
docker compose up -d
```

RPC: `http://127.0.0.1:8541` (HTTP), `ws://127.0.0.1:8542` (WS). op-node admin: `http://127.0.0.1:8543`.

Bring **geth up before op-node** (compose waits on the geth healthcheck). When bumping images, upgrade mantle-op-geth first, then mantle-op-node.

## Snapshot

Official **full** (state-pruned) tarball from [snapshot.mantle.xyz](https://s3.ap-southeast-1.amazonaws.com/snapshot.mantle.xyz/) (`*-mainnet-full-chaindata.tar.zst`). `./restore-snapshot.sh` resolves `current.info`, downloads with aria2c (or curl), verifies sha256, and extracts into `$HOME/mantle-op-geth-data/geth/chaindata`. Staging dir: `$HOME/mantle-snapshot-tmp` (`SNAPSHOT_TMPDIR` override).

Archive snapshots (`*-mainnet-chaindata.tar.zst`) are a different retention mode — do not restore them onto this hash-full datadir.

Pre-regenesis (v1) history is a separate `historyrpcdata-mainnet-chaindata` snapshot and compose; this setup does not include it.

## Pruning Mode

| Mode | Flags | Receipts / logs | State |
| --- | --- | --- | --- |
| **Hash full (this setup)** | `--syncmode=full` `--gcmode=full` `--txlookuplimit=0` | Full from v2 regenesis (block 61,171,946) | Recent only |
| Hash archive | `--gcmode=archive` + archive snapshot | Full | Full (much heavier) |

Do not flip `GC_MODE` on an existing datadir. Official execution P2P is unused (`--maxpeers=0`); the node follows the sequencer via Engine API.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `OP_NODE_P2P_PORT` (default `10419`). `P2P_PORT` (default `10417`) is mapped for geth but official `--maxpeers=0` does not accept peers. RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

## Testnet

Mantle Sepolia (chain ID **5003**): pin `v1.5.3` images, Sepolia L1 endpoints, `networks/sepolia/rollup.json`, and the Sepolia sequencer / static peer commented in `env.template`. Snapshot bucket: `snapshot.sepolia.mantle.xyz`.

Docs: [Mainnet v1.5.4](https://docs.mantle.xyz/network/for-node-operators/deployment-guides/mainnet-v1.5.4) · [networks](https://github.com/mantlenetworkio/networks) · [run-node-mainnetv2.md](https://github.com/mantlenetworkio/networks/blob/main/run-node-mainnetv2.md)
