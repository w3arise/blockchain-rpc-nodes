# Zircuit (conduit-op-reth + op-node)

Mainnet OP Stack L2 on **Conduit** infrastructure (chain ID **48900**). Chain data: `$HOME/zircuit-op-reth-data`, `$HOME/zircuit-op-node-data`.

**Client:** [`conduit-op-reth`](https://github.com/conduitxyz/conduit-op-reth) — the op-reth drop-in Conduit runs on Zircuit and uses to produce the GCS snapshots this setup restores. It symlinks `op-reth`, so flags are unchanged.

**Sync mode:** `OP_NODE_SYNCMODE=consensus-layer` — op-node derives from L1 and drives op-reth over the Engine API, so no execution peers are needed. See [op-reth peers](#op-reth-peers).

**Migration (Aug 2026):** Zircuit mainnet moved from `zircuit1/l2-geth` + `bootstrap.mainnet.zircuit.com` to Conduit. Legacy Zircuit node software and docs are **not maintained** for mainnet — use this setup. Wipe pre-migration `l2-geth` datadirs; op-reth uses a new layout.

**Pruning mode:** op-reth **archive** (no `--full` / `--prune.*` flags) — full block, receipt, and log history plus historical state.

**Bedrock migration:** Zircuit is a *migration* network. Blocks `0`–`32956467` come from legacy `l2-geth`; the OP Stack chain starts at **`bedrockBlock` 32956468**, which `config/genesis.json` sets. Pre-bedrock blocks are **not** derivable from L1 and are **not** served over OP Stack P2P, so a genesis sync is impossible — **the Conduit snapshot is required**. `--rollup.historicalrpc` proxies pre-bedrock queries to `SEQUENCER_HTTP`. `bedrockBlock` also feeds the execution fork ID, so a wrong value makes every Zircuit peer reject the handshake and leaves op-reth at **0 peers**.

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env
./create-jwt.sh
./restore-snapshot.sh   # required — see Bedrock migration above
docker compose up -d
```

When L1 runs on the Docker host, `host.docker.internal` works for L1 URLs (compose sets `extra_hosts`).

Refresh `config/genesis.json` and `config/rollup.json` from the [Conduit API](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) (slug **`zircuit-mainnet`**) after network upgrades.

## Snapshot

Conduit requester-pays GCS (required — no genesis sync path):

```bash
# set GCP_PROJECT in .env first
./restore-snapshot.sh
docker compose up -d
```

Manual: `gs://conduit-networks-snapshots/zircuit-mainnet/latest.tar` into `$HOME/zircuit-op-reth-data`. See [Conduit OP Stack nodes](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes).

Pre-Conduit Liquify lz4 snapshots (`zircuit-snapshot.liquify.com`) target **legacy l2-geth** datadirs and are **not** compatible with this op-reth setup.

## Testnet (Garfield)

Chain ID **48898**. Conduit slug **`zircuit-garfield-testnet`** (already on Conduit — use to validate before mainnet changes). Refresh `config/` from the Conduit API, set L1 to Sepolia, `SEQUENCER_HTTP=https://garfield-testnet.zircuit.com`, update P2P bootnodes/static peers, and snapshot `gs://conduit-networks-snapshots/zircuit-garfield-testnet/latest.tar`.

## op-reth peers

Conduit publishes op-node bootnodes and static peers but **no Zircuit execution bootnodes**, and `mainnet.zircuit.com` sits behind Cloudflare with `admin_nodeInfo` disabled, so its enode cannot be read. `OP_RETH_BOOTNODES` therefore uses the generic OP Stack mainnet pool as shared-DHT entry points; fork-ID filtering keeps only chain-48900 peers, which requires the correct `bedrockBlock`. If Conduit support hands you a Zircuit enode, add `--trusted-peers=<enode>` to the `zircuit-op-reth` command for a direct connection.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default **11588**) and `OP_NODE_P2P_PORT` (op-node, default **9228**). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Conduit — Run an OP Stack node](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) · [Zircuit RPCs](https://docs.zircuit.com/infra/rpcs) · [Conduit Hub](https://hub.conduit.xyz/)
