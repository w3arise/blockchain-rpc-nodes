# Agent guide: OP Stack L2 chains (Conduit)

Generic knowledge for adding or maintaining Layer 2 rollup nodes in this repo (e.g. `mode/`, `bob/`). These chains typically run **op-reth** (execution client) + **op-node** (rollup consensus client).

Nodes in this repo are meant to run on **Linux hosts**. Do not target macOS for deployment scripts.

## Architecture

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
├── create-jwt.sh         # writes config/jwt.hex (gitignored)
├── config/
│   ├── jwt.hex           # generated; shared by op-reth and op-node
│   ├── genesis.json      # optional reference / backup
│   └── rollup.json       # optional reference / backup
```

- Store **chain data** under `$HOME` (e.g. `$HOME/op-reth-data`, `$HOME/op-node-data`), not inside the repo.
- Mount `./config:/config` for JWT (and optional chain config files).



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

Local copies drift quickly (missing fork timestamps such as `jovianTime`, `karstTime`). An outdated genesis causes subtle sync failures near fork boundaries.

## op-node persistence (SafeDB)

```
OP_NODE_SAFEDB_PATH=/data
```

Mount `$HOME/op-node-data:/data` so op-node retains safe-head state across restarts. Without it, the node works but may lose sync progress on container recreate.

## Karst hardfork (`keep_karst_upgrade_gas`)

**Applies to:** OP, Ink, Metal, **Mode**, Soneium, Unichain, **Zora** (and Sepolia equivalents).

**Does not apply to:** BOB and other Conduit chains without `karst_time` in their fork schedule.

Conduit confirmed `keep_karst_upgrade_gas` must be `false` for Mode, Metal, and Zora, even though the superchain registry may set it to `true`. Wrong value can cause finalized head to stall.

For affected chains on op-node v1.19.x:

1. Confirm `karst_time` via `optimism_rollupConfig` RPC (Mode mainnet: `1783526401`).
2. Check startup logs for `keep_karst_upgrade_gas=true`.
3. Override: `--override.keep-karst-upgrade-gas=false` or `OP_NODE_OVERRIDE_KEEP_KARST_UPGRADE_GAS=false`.

BOB sync errors (`failed to insert unsafe payload`, `node is syncing`) are usually **not** Karst-related. See sync troubleshooting below.

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
5. **Outdated fork overrides** — e.g. `OP_NODE_OVERRIDE_JOVIAN` out of sync with network.

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

Pin images in `env.template`:

```
OP_RETH_IMAGE=us-docker.pkg.dev/oplabs-tools-artifacts/images/op-reth:v2.3.3
OP_NODE_IMAGE=us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.19.2
```

Karst activation requires op-reth (not op-geth) and compatible op-node/op-reth pairs per [Optimism upgrade notices](https://docs.optimism.io/notices/upgrade-19).

## Checklist for new Conduit L2 chain

1. Create chain directory with `docker-compose.yml`, `env.template`, `create-jwt.sh`.
2. Fetch bootnodes/static peers from Conduit API for the correct network slug.
3. Fetch genesis/rollup from Conduit API; verify MD5/size.
4. Choose chain spec strategy (built-in `--chain=<name>` vs datadir genesis) and stick with it.
5. Use `OP_NODE_L1_*` env vars in a single `.env`.
6. Mount `./config:/config` for shared JWT.
7. Store datadirs under `$HOME`.
8. Add `**/jwt.hex` to `.gitignore` (already in repo root).
9. Check whether Karst `keep_karst_upgrade_gas` override is needed (Mode/Metal/Zora only).
10. **Update** `README.md` — review the "Supported Chains" table and update the chain's status, type, and execution client. Also check `.gitignore` and remove the chain from the "Planned" section if it was listed there.

