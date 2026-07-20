# Hemi (op-geth + op-node + bssd)

Mainnet `hemi-min` node (snap sync). Chain data: `$HOME/hemi-op-geth-data`, `$HOME/hemi-tbc-data`, `$HOME/hemi-op-node-data`.

Requires external Ethereum execution + beacon RPCs. Host `ulimit -n` should be ≥ 65536 (see official docs).

## Start

```bash
./configure.sh          # creates .env, EXT_IP, datadirs
sudo chown -R 65532:65532 $HOME/hemi-op-geth-data $HOME/hemi-tbc-data
# set GETHL1ENDPOINT and PRYSMENDPOINT in .env
./create-jwt.sh
docker compose up -d
```

Init containers copy `jwt.hex`, `l2-config.toml`, and `rollup.json` into the datadirs so op-geth (UID 65532) does not read repo bind mounts directly.

RPC (localhost): set `OP_GETH_HTTP_PORT` / `OP_GETH_WS_PORT` / `OP_NODE_RPC_PORT` in `.env` (defaults `18546` / `28546` / `8547`).

Snap sync with external L1s is typically ~2 business days.

## Snapshot

No official datadir snapshot. Initial sync uses op-geth `--syncmode=snap` (do not switch to full unless you have historical EIP-4844 blobs).

## Testnet

Not packaged here. Official testnet files: [hemi-node/testnet](https://github.com/hemilabs/hemi-node/tree/main/testnet).

Docs: [NODE_RUNNING.md](https://github.com/hemilabs/hemi-node/blob/main/NODE_RUNNING.md) · [Network details](https://docs.hemi.xyz/discover/network-details)
