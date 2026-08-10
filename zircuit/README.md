# Zircuit (conduit-op-reth + op-node)

Mainnet OP Stack L2 on **Conduit** infrastructure (chain ID **48900**). Chain data: `$HOME/zircuit-op-reth-data`, `$HOME/zircuit-op-node-data`.

**Client:** [`conduit-op-reth`](https://github.com/conduitxyz/conduit-op-reth) (Conduit op-reth build; GCS snapshots match this client).

**Sync mode:** `OP_NODE_SYNCMODE=consensus-layer` — op-node derives from L1 and drives op-reth over the Engine API.

**Migration (Aug 2026):** Zircuit mainnet moved from `zircuit1/l2-geth` + `bootstrap.mainnet.zircuit.com` to Conduit. Legacy Zircuit node software and docs are **not maintained** for mainnet — use this setup. Wipe pre-migration `l2-geth` datadirs; op-reth uses a new layout. Pre-Conduit **`l2-geth` + Liquify snapshots** are documented in [`../zircuit-legacy/`](../zircuit-legacy/README.md).

**Pruning mode:** op-reth **archive** (no `--full` / `--prune.*` flags) — full block, receipt, and log history plus historical state.

**Derivation anchor:** Zircuit has been Bedrock since block 0 (`bedrockBlock: 0` — do not change it), but `config/rollup.json` anchors derivation at the Conduit migration point, L2 block **32956468** (`0x739969ca…`). op-node derives forward from that anchor only, so it requires op-reth to **already contain that block** and refuses to start otherwise:

```
failed to find the L2 Heads to start from: ... could not get payload: not found
```

Blocks `0`–`32956468` are not derivable from L1 under this rollup config, so **the Conduit snapshot is required** — an empty datadir cannot bootstrap. `--rollup.historicalrpc` proxies pre-anchor queries to **`HISTORICAL_RPC`** (default: public RPC; set to `http://host.docker.internal:11565` when running [`../zircuit-legacy/`](../zircuit-legacy/README.md) locally).

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON in .env
./create-jwt.sh
./restore-snapshot.sh   # required — see Derivation anchor above
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

Chain ID **48898**. Conduit slug **`zircuit-garfield-testnet`**. Refresh `config/` from the Conduit API, set L1 to Sepolia, `SEQUENCER_HTTP=https://garfield-testnet.zircuit.com`, update P2P bootnodes/static peers, and snapshot `gs://conduit-networks-snapshots/zircuit-garfield-testnet/latest.tar`.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default **11588**) and `OP_NODE_P2P_PORT` (op-node, default **9228**). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Conduit — Run an OP Stack node](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) · [Zircuit RPCs](https://docs.zircuit.com/infra/rpcs) · [Conduit Hub](https://hub.conduit.xyz/)
