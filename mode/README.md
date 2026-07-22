# Mode (op-reth + op-node)

Mainnet OP Stack L2 (Conduit). Chain data: `$HOME/mode-op-reth-data`, `$HOME/mode-op-node-data`.

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env
./create-jwt.sh
docker compose up -d
```

## Snapshot

Conduit archive snapshots (requester-pays GCS). Restore into `$HOME/mode-op-reth-data`, then start as above (genesis init is automatic via `--chain=mode`):

```bash
gcloud storage cp --billing-project="${GCP_PROJECT}" \
  "gs://conduit-networks-snapshots/mode-mainnet-0/latest.tar" .
# extract into $HOME/mode-op-reth-data (op-reth layout — no mnt/geth/ path)
```

See [Conduit OP Stack nodes](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes).

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default `31303`) and `OP_NODE_P2P_PORT` (op-node, default `9223`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Mode docs](https://docs.mode.network/) · [Conduit Hub](https://hub.conduit.xyz/mode-mainnet-0) · [Run an OP Stack node](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes)
