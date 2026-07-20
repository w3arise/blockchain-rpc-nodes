# Katana (conduit-op-reth + op-node)

Mainnet OP Stack L2 (Conduit / Agglayer CDK). Chain data: `$HOME/katana-op-reth-data`, `$HOME/katana-op-node-data`.

## Start

```bash
./configure.sh          # .env + EXT_IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env
./create-jwt.sh
docker compose up -d
```

## Snapshot

Conduit archive snapshots (requester-pays GCS). Restore into `$HOME/katana-op-reth-data`, then start as above (genesis init is automatic via `--chain`):

```bash
gcloud storage cp --billing-project="${GCP_PROJECT}" \
  "gs://conduit-networks-snapshots/katana/latest.tar" .
# extract into $HOME/katana-op-reth-data (op-reth layout — no mnt/geth/ path)
```

See [Conduit OP Stack nodes](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes).

## Testnet (Bokuto)

Replace `config/genesis.json` and `config/rollup.json` with [bokuto/op-reth](https://github.com/katana-network/network-configs/tree/main/bokuto/op-reth), set L1 to Sepolia, and refresh P2P from Conduit slug `katana-bokuto`. Snapshot: `gs://conduit-networks-snapshots/katana-bokuto/latest.tar`.

Docs: [Katana network info](https://docs.katana.network/katana/technical-reference/network-information/) · [network-configs](https://github.com/katana-network/network-configs) · [Conduit Hub](https://hub.conduit.xyz/katana)
