# Agent guide

Conventions for adding and maintaining chain nodes in this repo (L1, L2, OP Stack, and others). OP Stack / Conduit-specific notes are in their own sections below.

Nodes in this repo are meant to run on **Linux hosts**. Do not target macOS for deployment scripts.

## Chain links (`CHAIN_LINKS.md`)

When adding or updating a chain setup, add its **official** documentation and repositories to [`CHAIN_LINKS.md`](CHAIN_LINKS.md). Include links you rely on during setup (node run guides, network specs, client repos/releases).

Use this table format — one row per chain:

| Chain | Explorer | Links |
| --- | --- | --- |
| … | … | … |

- **Explorer** — official block explorer URL when the chain has one (e.g. [soneium.blockscout.com](https://soneium.blockscout.com/)). Use `—` if none. Verify the URL responds before adding (e.g. `curl -L -o /dev/null -w "%{http_code}"`).
- **Links** — docs, repos, network specs, and other setup references. Multiple links in one cell, separated by ` · `.

## Chain README (`<chain>/README.md`)

Each chain directory gets a **minimal** `README.md` with the exact steps to run it. Keep it short — see `neox/README.md` or `berachain/README.md` for tone and length.

Include:

- One-line description (client, network role)
- Host datadir path(s)
- **Start** — numbered shell commands from a fresh setup (configure, build, init, compose up)
- **Snapshot** — restore path and which init steps to skip (if snapshots are supported)
- **Testnet** — only if the setup supports it
- Link to official run docs

Do not duplicate `env.template` comments or long troubleshooting guides.

## Architecture (OP Stack)

```
L1 (Ethereum) ──► op-node ──► Engine API (JWT) ──► op-reth ──► JSON-RPC
                      │
                      └── P2P (bootnodes / static peers)
```

- **op-reth**: stores chain data, serves HTTP/WS RPC, exposes authenticated Engine API (port 8551 or 9551).
- **op-node**: derives L2 from L1, drives op-reth via Engine API, syncs unsafe blocks from P2P peers.
- Both must share the **same JWT** for Engine API auth



## Standard layout per chain directory

```
chain/
├── docker-compose.yml
├── env.template          # copy to .env; never commit .env
├── README.md             # minimal start steps
├── configure.sh          # optional: create .env, set EXT_IP
├── init-database.sh      # optional: genesis / datadir init
├── Dockerfile            # optional: local image build
├── create-jwt.sh         # OP Stack only: writes config/jwt.hex
└── config/               # genesis, rollup, JWT, chain params
```

- Store **chain data** under `$HOME`, not inside the repo.
- Add setup scripts only when the chain needs them (not every chain uses JWT, Docker build, or genesis init).



## Environment variables



### op-node L1 (required)

op-node does **not** read generic names. Use the `OP_NODE_`* prefix:


| Wrong (ignored) | Correct              |
| --------------- | -------------------- |
| `L1_RPC`        | `OP_NODE_L1_ETH_RPC` |
| `L1_BEACON`     | `OP_NODE_L1_BEACON`  |


If L1 vars are missing, op-node fails at startup with: `flag l1 is required`.

Use a single `.env` loaded via `env_file: .env` on op-node. Do not split into `op-node.env` unless compose explicitly references it.

### op-node network preset

Prefer built-in network names when available:

```
OP_NODE_NETWORK=mode-mainnet   # or bob-mainnet
OP_NODE_ROLLUP_CONFIG=         # empty = use built-in preset
```

Bootnodes and static peers still come from env (see Conduit API below).

### op-reth chain configuration

Two valid approaches — **do not mix on an existing datadir**:


| Approach        | op-reth flag                   | When to use                                       |
| --------------- | ------------------------------ | ------------------------------------------------- |
| Built-in preset | `--chain=mode` / `--chain=bob` | Fresh sync; image embeds current chain spec       |
| Genesis file    | `--chain=/data/genesis.json`   | Existing datadir already synced with that genesis |


**Critical:** Switching from `--chain=/data/genesis.json` to `--chain=bob` (or vice versa) on a populated datadir causes sync to stall. op-node keeps pushing blocks; op-reth returns `updated forkchoice, but node is syncing` and the head stops moving.

If the chain spec must change, either:

- revert to the original genesis path/spec, or
- wipe datadir and resync from scratch.

Genesis in the datadir (`$HOME/op-reth-data/genesis.json`) is what op-reth reads with the file-based approach. Files under `config/` are not used unless explicitly mounted and referenced.

## JWT (Engine API)

Generate once per deployment:

```bash
./create-jwt.sh   # writes config/jwt.hex
```

Both services mount the same file:

- op-reth: `--authrpc.jwtsecret=/config/jwt.hex`
- op-node: `OP_NODE_L2_ENGINE_AUTH=/config/jwt.hex`

Do not use a custom entrypoint to write JWT at runtime unless necessary. Regenerating JWT requires restarting **both** containers.

## P2P and public IP



### op-node peers (Conduit API)

Fetch current lists — do not copy from another chain (Mode ≠ BOB):

```
https://api.conduit.xyz/public/network/bootnodes/<network-slug>
https://api.conduit.xyz/public/network/staticPeers/<network-slug>
```

Example slugs: `mode-mainnet-0`, `bob-mainnet-0`.

Set in env:

```
OP_NODE_P2P_BOOTNODES=enode://...
OP_NODE_P2P_STATIC=/ip4/.../tcp/9222/p2p/...
```

Some Conduit bootnodes (e.g. `bootnode.conduit.xyz`) are shared across chains; the first enode and static peer are chain-specific.

### op-reth P2P NAT

For public P2P advertisement on op-reth:

```yaml
# docker-compose.yml
- --nat=extip:${EXT_IP}
```

```
# env.template
EXT_IP=<YOUR_PUBLIC_IP>
```

This is separate from op-node P2P settings (`OP_NODE_P2P_ADVERTISE_IP`).

## Conduit config files

Download authoritative config from Conduit and verify with checksums before committing:

```
https://api.conduit.xyz/file/v1/optimism/genesis/<network-slug>
https://api.conduit.xyz/file/v1/optimism/rollup/<network-slug>
https://api.conduit.xyz/file/v1/optimism/forkTimestamps/<network-slug>
```

Local copies drift quickly (missing fork timestamps). An outdated genesis causes subtle sync failures near fork boundaries.

## op-node persistence (SafeDB)

```
OP_NODE_SAFEDB_PATH=/data
```

Mount `$HOME/op-node-data:/data` so op-node retains safe-head state across restarts. Without it, the node works but may lose sync progress on container recreate.

## Sync troubleshooting



### Normal catch-up (temporary)

During `OP_NODE_SYNCMODE=execution-layer`, op-node may ahead of op-reth:

```
failed to insert unsafe payload ... err: updated forkchoice, but node is syncing
requesting engine missing unsafe L2 block range ... size=N
```

This is expected while op-reth imports the gap. Errors should stop once reth catches up.

### Real stall (investigate)

Head block unchanged for >1–2 hours while L1 origin advances:

1. **Chain spec mismatch** — genesis/built-in preset changed but datadir was not wiped.
2. **Datadir path change** — `$HOME/op-reth-data` vs `./op-reth-data` pointing at different data.
3. **Missing L1 env** — `OP_NODE_L1_ETH_RPC` / `OP_NODE_L1_BEACON` not loaded into container.
4. **JWT mismatch** — Engine API auth failure (usually total failure, not partial stall).
5. **Outdated fork overrides** — manual op-node fork flags out of sync with the network.

Diagnostic commands:

```bash
# L1 vars present?
docker compose exec <op-node> env | grep OP_NODE_L1

# reth syncing?
curl -s http://127.0.0.1:<rpc-port> -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# rollup config
curl -s http://127.0.0.1:<op-node-rpc> -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"optimism_rollupConfig","params":[],"id":1}' | jq
```



## Version pins

Pin client images in `env.template` (op-reth, op-node, etc.) and bump them together when upgrading.

## Checklist for new chain

Apply every item that fits the chain type. Skip sections that do not apply (e.g. JWT for a single-client L1).

### All chains

1. Create `<chain>/` with `docker-compose.yml`, `env.template`, and any needed setup scripts.
2. Pin client versions in `env.template` (image tags, release versions, etc.).
3. Store datadirs under `$HOME`.
4. **Add** `<chain>/README.md` — minimal start/snapshot/testnet steps (see Chain README above).
5. **Update** root `README.md` — Supported Chains table (status, type, execution client); remove from Planned if applicable.
6. **Update** `CHAIN_LINKS.md` — official explorer (if any), docs, network specs, and client repo/release links.
7. Check `.gitignore` for secrets and generated files (`.env`, JWT, downloaded binaries).

### OP Stack (op-node + execution client)

8. `create-jwt.sh` and mount shared JWT for Engine API auth.
9. Use `OP_NODE_L1_*` env vars in a single `.env`.
10. Set `OP_NODE_SAFEDB_PATH` and persist op-node datadir under `$HOME`.
11. Choose chain spec strategy (built-in `--chain=<name>` vs datadir genesis) and **do not mix** on an existing datadir.
12. Set `--nat=extip:${EXT_IP}` (or equivalent) for public P2P where needed.

### Conduit OP Stack (additional)

13. Fetch bootnodes/static peers from Conduit API for the correct network slug.
14. Fetch genesis/rollup from Conduit API; verify before committing.

