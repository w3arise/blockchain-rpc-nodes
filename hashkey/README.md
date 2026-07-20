# HashKey Chain (op-geth + op-node)

Mainnet archive replica. Chain ID **177**. Custom gas token (HSK). Chain data: `$HOME/hashkey-op-geth-data`, `$HOME/hashkey-op-node-data`.

## Start

```bash
./configure.sh
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env (Ethereum mainnet)
./create-jwt.sh
./init-database.sh
docker compose up -d
```

RPC: `http://127.0.0.1:8111` (HTTP), `http://127.0.0.1:8112` (WS). op-node admin RPC: `http://127.0.0.1:8113`.

If `./init-database.sh` failed partway, remove the partial datadir (`rm -rf <HOST_DATADIR>/geth`) and rerun. The script patches `pragueTime` to match `isthmusTime` in the official genesis (required by op-geth, omitted on S3).

## Host ports

Public P2P (TCP + UDP): op-geth `${P2P_PORT}` (default 10415), op-node `${HOST_OP_NODE_P2P_PORT}` (default 10429). Set by `./configure.sh` on `EXT_IP` / `OP_NODE_P2P_ADVERTISE_IP`.

Committed `config/rollup.json` uses op-node snake_case fork fields (`holocene_time`, etc.). Official S3 publishes camelCase; normalize if you refresh from upstream.

## Snapshot

Archive op-geth chaindata: [official snapshot guide](https://docs.hashkeychain.net/docs/Build-on-HashKey-Chain/RPC-Node-Provider#syncing-from-a-snapshot).

Mainnet tarball: `https://snapshot.hashkeychain.net/mainnet/20260701-mainnet-archive-chaindata.tar.zst`

Extract so chaindata lands at `$HOME/hashkey-op-geth-data/geth/chaindata`, keep `GETH_SYNC_MODE=full`, skip `./init-database.sh`, then `docker compose up -d`.

## State retention

Default is archive (`GC_MODE=archive`, `GETH_SYNC_MODE=full`) per official docs. For a pruned node, set `GC_MODE=full` before first start on a fresh datadir only.

## Testnet

Chain ID **133**, L1 Sepolia. Replace `config/genesis.json`, `config/rollup.json`, and `config/config.toml` with testnet values from the [official template](https://docs.hashkeychain.net/docs/Build-on-HashKey-Chain/RPC-Node-Provider), set `SEQUENCER_HTTP=https://testnet.hsk.xyz`, and update `OP_NODE_P2P_STATIC` in `.env`.

Docs: [RPC & Node Provider](https://docs.hashkeychain.net/docs/Build-on-HashKey-Chain/RPC-Node-Provider) · [Network info](https://docs.hashkeychain.net/docs/Build-on-HashKey-Chain/network-info)
