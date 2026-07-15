# Lens (ZK Stack external node)

Mainnet external node (matterlabs/external-node + PostgreSQL). Lightweight mode: snapshot recovery + pruning — recent block history only, no full state archive. Chain data: `$HOME/lens-postgres-data`, `$HOME/lens-rocksdb-data`.

## Start

```bash
./configure.sh
# edit .env — set EN_ETH_CLIENT_URL and DB_PASSWORD (DA seed phrase is auto-generated if empty)
docker compose up -d
```

First run downloads a snapshot from GCS (`raas-lens-mainnet-external-node-snapshots`) and prunes old L1 batches (~7 days retention). RPC is unavailable until recovery completes — check `curl http://127.0.0.1:3181/health`.

If the external node fails with `Too many open files` during RocksDB catch-up, recreate it so compose `ulimits` apply: `docker compose up -d --force-recreate external-node`.

Pinned to `EN_VERSION=v29.20.0-alpha` — v29.1.2 auto-dials dead Gateway DNS (`rpc.era-gateway-mainnet.zksync.dev`) for Lens Bridgehub.

If startup fails with `settlement_layer_en` / `dns error` on your L1 URL, `EN_ETH_CLIENT_URL` is missing or unreachable from inside the container. Use a public HTTPS endpoint (e.g. `https://ethereum-rpc.publicnode.com`) or `http://host.docker.internal:<port>` for an L1 node on the host — not `127.0.0.1`.

## Snapshot

Snapshot recovery is enabled by default. It must stay on for the **first** start; changing it later does not reset an existing datadir. To resync from a fresh snapshot, stop the stack and remove both datadirs (see Reset).

Historical blocks before the snapshot L1 batch are not available. Pruning removes older retained batches continuously.

## Reset

```bash
docker compose down
# remove $HOME/lens-postgres-data and $HOME/lens-rocksdb-data to resync from scratch
```

Docs: [Running a node](https://lens.xyz/docs/chain/running-a-node) · [lens-protocol/lens-chain-node](https://github.com/lens-protocol/lens-chain-node)
