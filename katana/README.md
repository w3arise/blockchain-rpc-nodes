# Katana (conduit-op-reth + op-node)

Mainnet OP Stack L2 (Conduit / Agglayer CDK). Chain data: `$HOME/katana-op-reth-data`, `$HOME/katana-op-node-data`.

## Start

```bash
./configure.sh          # .env + EXT_IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env
./create-jwt.sh
docker compose up -d
```

Before upgrading an existing node, run `./check-genesis.sh` and refresh images/config from [network-configs](https://github.com/katana-network/network-configs) when upstream changes.

## Snapshot

Official archive snapshots (op-reth layout). Restore into `$HOME/katana-op-reth-data`, then start as above (genesis init is automatic via `--chain`):

```bash
curl -L -o katana-latest.tar \
  "https://pub-1d729d824bda40459735d97aca47bc6f.r2.dev/katana/latest.tar"
# extract into $HOME/katana-op-reth-data
```

Source: [network-configs snapshots](https://github.com/katana-network/network-configs).

## Testnet (Bokuto)

Replace `config/genesis.json` and `config/rollup.json` with [bokuto/op-reth](https://github.com/katana-network/network-configs/tree/main/bokuto/op-reth), set L1 to Sepolia, and refresh P2P from Conduit slug `katana-bokuto`. Snapshot: `https://pub-1d729d824bda40459735d97aca47bc6f.r2.dev/katana-bokuto/latest.tar`.

Docs: [Katana network info](https://docs.katana.network/katana/technical-reference/network-information/) · [network-configs](https://github.com/katana-network/network-configs) · [Conduit Hub](https://hub.conduit.xyz/katana)
