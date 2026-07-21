# Agent guide

Conventions for adding and maintaining chain nodes in this repo (L1, L2, OP Stack, ZK Stack, and others). OP Stack / Conduit-specific notes are in their own sections below.

Nodes in this repo are meant to run on **Linux hosts**. Do not target macOS for deployment scripts.

## RPC gas cap

Unless a chain’s docs or operator requirements say otherwise, set the execution client’s RPC gas cap to **`600000000`** (600M) via env (typically `GAS_CAP`) and wire it to the client flag (e.g. `--rpc.gascap=${GAS_CAP}`). This matches the BSC / DRPC default used elsewhere in the repo. Prefer making it env-configurable rather than hardcoding.

## Chain links (`CHAIN_LINKS.md`)

When adding or updating a chain setup, add its **official** documentation and repositories to [`CHAIN_LINKS.md`](CHAIN_LINKS.md). Include links you rely on during setup (node run guides, network specs, client repos/releases).

Use this table format — one row per chain:

| Chain | Explorer | Links | Snapshot |
| --- | --- | --- | --- |
| … | … | … | … |

- **Explorer** — official block explorer URL when the chain has one (e.g. [soneium.blockscout.com](https://soneium.blockscout.com/)). Use `—` if none. Verify the URL responds before adding (e.g. `curl -L -o /dev/null -w "%{http_code}"`).
- **Links** — docs, repos, network specs, and other setup references. Multiple links in one cell, separated by ` · `.
- **Snapshot** — official or documented snapshot download / recovery pages. Use `—` if none.

## Chain README (`<chain>/README.md`)

Each chain directory gets a **minimal** `README.md` with the exact steps to run it. Keep it short — see `neox/README.md` or `berachain/README.md` for tone and length.

Include:

- One-line description (client, network role)
- Host datadir path(s)
- **Start** — numbered shell commands from a fresh setup (configure, build, init, compose up)
- **Snapshot** — restore path and which init steps to skip. When adding a chain, **prefer finding an official or community snapshot source** (chain docs, client repo, explorer/provider pages). Document the source URL and restore steps in the README; if none exists, state that explicitly and sync from genesis/P2P. Note whether recovery uses a tarball, genesis prime file, or both.
- **Pruning Mode** or **State retention** — when the client has archive/pruning flags or init-time choices; see [Archive and state retention (general)](#archive-and-state-retention-general).
- **Testnet** — only if the setup supports it
- **Host ports** — when running a public replica, document inbound P2P ports; see [Ports, connectivity, and P2P (L2)](#ports-connectivity-and-p2p-l2)
- Link to official run docs

Do not duplicate `env.template` comments or long troubleshooting guides.

If the compose setup includes **Prometheus and/or Grafana**, add a **first-start ownership** step in **Start** (see [Prometheus and Grafana](#prometheus-and-grafana-optional-monitoring) below).

## Prometheus and Grafana (optional monitoring)

Some chain setups include Prometheus and Grafana (e.g. `abstract/`). These use the **official** images; the internal users are fixed by the image tag, not the chain.

| Image | Internal user | UID | GID |
| --- | --- | --- | --- |
| `prom/prometheus` (e.g. `v2.35.0`) | `nobody` | 65534 | 65534 |
| `grafana/grafana` (e.g. `9.3.6`) | `grafana` | 472 | 0 |

When compose bind-mounts host datadirs for these services, the operator must **`chown` the directories on the host after creating them and before first start**. Docker creates empty mount paths as root; the containers cannot write TSDB or Grafana state without correct ownership.

Example (adjust paths to the chain):

```bash
mkdir -p "$HOME/<chain>-prometheus-data" "$HOME/<chain>-grafana-data"
sudo chown -R 65534:65534 "$HOME/<chain>-prometheus-data"
sudo chown -R 472:0 "$HOME/<chain>-grafana-data"
```

For chains that ship Grafana/Prometheus in compose:

- Document datadir paths and the `chown` commands in `<chain>/README.md` **Start** steps (first start only).
- Pin the image tag in `docker-compose.yml` or `env.template`. If the tag changes, re-check the user: `docker run --rm --entrypoint id <image>`.

## ZK Stack / ZKsync external nodes

Chains built on the ZK Stack (e.g. Abstract, ZKsync Era, Lens) typically run a **`matterlabs/external-node`** container. In upstream compose files the service is usually named **`external-node`**.

These nodes use **RocksDB** for state (`state_keeper`, `lightweight` trees). During snapshot recovery or catch-up, RocksDB opens many `.sst` files at once. Docker’s default `nofile` limit (~1024) is too low and causes:

```
Too many open files ... While open a file for random read: ./db/ext-node/state_keeper/....sst
```

Set **`ulimits.nofile`** on the external-node service (and recreate the container after adding):

```yaml
external-node:
  image: matterlabs/external-node:${EN_VERSION}
  ulimits:
    nofile:
      soft: 1048576
      hard: 1048576
```

See `abstract/docker-compose.yml` for a working example. If the limit still appears low inside the container (`docker compose exec external-node sh -c 'ulimit -n'`), raise the host hard limit (`ulimit -Hn`, `/etc/security/limits.conf`).

## Arbitrum Nitro (PathDB / PBSS)

All Nitro setups in this repo prefer **PathDB** (`--execution.caching.state-scheme=path`, or `"state-scheme": "path"` in a config file).

### Archive vs pruned (state history)

Two flags control retention on PathDB nodes:

| Flag | Default | Meaning |
| --- | --- | --- |
| `--execution.caching.state-history` | `345600` (~24h at 250ms blocks) | Recent blocks of state history to retain. **`0` = unlimited** (archive). PathDB only. |
| `--execution.caching.archive` | off | Required for archival nodes; retains past block state. |

**Archive mode** — both together with `state-history=0`:

```
--execution.caching.state-scheme=path
--execution.caching.state-history=0
--execution.caching.archive
```

**Pruned full node** — set `state-history` to a non-zero value (e.g. `345600` for ~24h) and omit `--execution.caching.archive` (or `"archive": false` in a config file).

**Repo default for archive setups:** `STATE_HISTORY=0` plus `--execution.caching.archive` in compose.

### Critical: do not change `state-history` casually

Tested behavior on existing datadirs:

- **Archive → pruned:** changing `state-history` from `0` to any non-zero value **immediately prunes** retained history.
- **Snapshot restore:** starting with `state-history != 0` against a restored archive snapshot **prunes the DB on first start**. Keep `state-history=0` when restoring archive snapshots unless you intentionally want a pruned node.

For pruned full-node behavior after a safe archive restore, change `STATE_HISTORY` only once you confirm the node is synced and you accept the pruning.

Flag this in every Nitro chain README under a **State retention** section (see `arbitrum/README.md`).

## Architecture (OP Stack)

```
L1 (Ethereum) ──► op-node ──► Engine API (JWT) ──► op-reth ──► JSON-RPC
                      │
                      └── P2P (bootnodes / static peers)
```

- **op-reth**: stores chain data, serves HTTP/WS RPC, exposes Engine API to op-node (Docker-internal only — see [Ports](#ports-connectivity-and-p2p-l2)).
- **op-node**: derives L2 from L1, drives op-reth via Engine API, syncs unsafe blocks from P2P peers.
- Both must share the **same JWT** for Engine API auth — see [JWT (Engine API)](#jwt-engine-api).

## Ports, connectivity, and P2P (L2)

All **L2** setups (OP Stack, Nitro, ZK Stack external nodes, etc.) must follow the same port and connectivity rules. Reference implementation: [`katana/`](katana/).

### General rules

1. **Define ports in `env.template`** under a `### Ports ###` group — do not hardcode host ports in `docker-compose.yml`.
2. **RPC / WebSocket / op-node admin RPC** bind to **`RPC_BIND_ADDR`** on the host (default **`127.0.0.1`**). Change to `0.0.0.0` only when LAN access is intentional.
3. **P2P ports** bind on **all interfaces** (no `127.0.0.1` prefix) — peers must reach them from the internet when the node advertises P2P.
4. **Host vs container for execution-client RPC:** host port is **configurable**; in-container listen port is **fixed** at the client default (e.g. op-reth `8545` / `8546`). Do not make both sides the same env var unless the client requires it.
5. **P2P needs TCP and UDP** on the same host port — two compose mappings are required, not redundant:
   ```yaml
   - ${P2P_PORT}:${P2P_PORT}
   - ${P2P_PORT}:${P2P_PORT}/udp
   ```

### OP Stack (op-reth + op-node)

Typical `env.template` ports block:

| Variable | Default (example) | Role |
| --- | --- | --- |
| `RPC_BIND_ADDR` | `127.0.0.1` | Host bind for HTTP / WS / op-node admin RPC |
| `HTTP_PORT` | chain-specific | Host → op-reth container `8545` |
| `WS_PORT` | chain-specific | Host → op-reth container `8546` |
| `OP_NODE_RPC_PORT` | chain-specific | op-node admin RPC (e.g. `optimism_syncStatus`) |
| `OP_NODE_P2P_PORT` | `9222` (Conduit default) | op-node rollup P2P (TCP + UDP, public) |
| `P2P_PORT` | chain-specific | op-reth execution P2P (TCP + UDP, public) |

**Compose mappings (op-reth):**

```yaml
ports:
  - ${RPC_BIND_ADDR}:${HTTP_PORT}:8545
  - ${RPC_BIND_ADDR}:${WS_PORT}:8546
  - ${P2P_PORT}:${P2P_PORT}
  - ${P2P_PORT}:${P2P_PORT}/udp
```

Inside the container, op-reth listens on fixed `8545` / `8546` (`--http.port=8545`, `--ws.port=8546`). Engine API stays on the Docker network only (e.g. `9551`) — do not publish it to the host.

**op-reth P2P flags** — set `--port`, `--discovery.port`, and `--discovery.v5.port` to the **same** `${P2P_PORT}` (plus `--discovery.addr=0.0.0.0` and `--nat=extip:${EXT_IP}`):

```yaml
- --port=${P2P_PORT}
- --discovery.addr=0.0.0.0
- --discovery.port=${P2P_PORT}
- --discovery.v5.port=${P2P_PORT}
```

Do not put discovery v5 on a separate port unless chain docs explicitly require it. See [`katana/docker-compose.yml`](katana/docker-compose.yml).

**Compose mappings (op-node):**

```yaml
ports:
  - ${RPC_BIND_ADDR}:${OP_NODE_RPC_PORT}:${OP_NODE_RPC_PORT}
  - ${OP_NODE_P2P_PORT}:${OP_NODE_P2P_PORT}
  - ${OP_NODE_P2P_PORT}:${OP_NODE_P2P_PORT}/udp
```

Set in `env.template` for op-node listen/advertise:

```
OP_NODE_RPC_ADDR=0.0.0.0
OP_NODE_P2P_LISTEN_IP=0.0.0.0
OP_NODE_P2P_LISTEN_TCP=<same as OP_NODE_P2P_PORT>
OP_NODE_P2P_LISTEN_UDP=<same as OP_NODE_P2P_PORT>
OP_NODE_P2P_ADVERTISE_IP=          # filled by configure.sh
```

op-node runtime config (sync mode, rollup, P2P bootnodes, fork overrides) belongs in **`env.template`** as `OP_NODE_*` vars loaded via `env_file: .env` — not duplicated as CLI flags in compose unless a flag cannot be set via env.

### Public IP and `configure.sh`

When the chain exposes P2P, **`configure.sh`** must fetch the host public IP (e.g. via `ip.me`) and set:

| Variable | Used by |
| --- | --- |
| `EXT_IP` | Execution client NAT (e.g. op-reth `--nat=extip`) |
| `OP_NODE_P2P_ADVERTISE_IP` | op-node P2P advertise (OP Stack only) |

Leave both empty in `env.template`; operators run `./configure.sh` before first start. Re-run after a public IP change.

Document inbound P2P ports (`P2P_PORT`, `OP_NODE_P2P_PORT` — TCP + UDP) in `<chain>/README.md` when the node is a public replica. RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

### Conduit bootnodes (OP Stack)

Fetch current lists — do not copy from another chain (Mode ≠ BOB):

```
https://api.conduit.xyz/public/network/bootnodes/<network-slug>
https://api.conduit.xyz/public/network/staticPeers/<network-slug>
```

Example slugs: `mode-mainnet-0`, `bob-mainnet-0`, `katana`.

Set in `env.template`:

```
OP_NODE_P2P_BOOTNODES=enode://...
OP_NODE_P2P_STATIC=/ip4/.../tcp/9222/p2p/...
OP_NODE_P2P_SYNC_ONLYREQTOSTATIC=true
```

Some Conduit bootnodes (e.g. `bootnode.conduit.xyz`) are shared across chains; the first enode and static peer are chain-specific.

### Other L2 stacks

Apply the same split: **localhost + configurable host port** for JSON-RPC/admin APIs; **public + configurable host port** for P2P (TCP + UDP). Nitro uses `HTTP_PORT` / `WS_PORT` with fixed in-container ports; ZK Stack external nodes use `EN_HTTP_PORT` / `EN_WS_PORT` with `RPC_BIND_ADDR`. Name vars per chain, keep the pattern.

## Standard layout per chain directory

```
chain/
├── docker-compose.yml
├── env.template          # copy to .env; never commit .env
├── README.md             # minimal start steps
├── configure.sh          # optional: create .env, set public IP (see Ports section)
├── init-database.sh      # optional: genesis / datadir init
├── Dockerfile            # optional: local image build
├── create-jwt.sh         # OP Stack only: writes config/jwt.hex
└── config/               # genesis, rollup, JWT, chain params
```

- Store **chain data** under `$HOME`, not inside the repo.
- Prefer **`$HOME/<chain>-data`** (e.g. `$HOME/neox-data`, `$HOME/sonic-data`) over hidden paths like `$HOME/.chain`.
- Expose the host path as **`HOST_DATADIR`** in `env.template` and mount it in compose, e.g. `${HOST_DATADIR:-$HOME/<chain>-data}:/data`. Use **`/data`** as the in-container datadir when the client allows it.
- Add setup scripts only when the chain needs them (not every chain uses JWT, Docker build, or genesis init).

### env.template and configure.sh

- **`env.template`** — setup steps in header comments; group vars (`### Network ###`, `### Ports ###`, `### RPC ###`, etc.); pin client versions; set `GAS_CAP=600000000` unless the chain requires otherwise. Port layout and public IP vars: [Ports, connectivity, and P2P (L2)](#ports-connectivity-and-p2p-l2).
- **`configure.sh`** — optional; creates `.env` from `env.template` and sets public IP. See [Ports, connectivity, and P2P (L2)](#ports-connectivity-and-p2p-l2). Do not embed secrets.
- **`docker-compose.yml`** — load `.env` with `env_file: .env` on services that need runtime vars (typically op-node); keep runtime services only (no init-container chown hacks).

## Archive and state retention (general)

Some clients prune history at **startup flags**, **init/priming time**, or **both**. Nitro uses `state-history` / `archive` — see [Arbitrum Nitro (PathDB / PBSS)](#arbitrum-nitro-pathdb--pbss). Others (e.g. Sonic/Fantom `sonicd`) use **`--mode validator`** for live pruning vs default **`rpc`** mode for RPC/archive nodes, and may offer **pruned vs archive genesis files** when priming the DB.

For any chain with non-obvious retention behavior:

- Add a **Pruning Mode** or **State retention** section to `<chain>/README.md` — which flags/modes are safe for archive RPC, and what triggers pruning.
- **Do not re-run init/priming** (genesis import, snapshot restore script, etc.) against an existing **archive** datadir using a **pruned** source unless you intend to discard history.
- When documenting snapshots, distinguish **chaindata tarballs** from **genesis/state prime files** (`.g`, vendor-specific exports) if the chain uses the latter.

## First-start permissions

Do not fight container UID/permission issues with compose **init containers** (one-shot `chown`, config copy, genesis init). Prefer **`configure.sh` + `init-database.sh` + one `sudo chown`** — document the UID/GID and exact command in `<chain>/README.md` **Start**. This matches `opbnb/`, `neox/`, and `hemi/`. Keep `docker-compose.yml` to runtime services only.

When the client runs as a fixed non-root UID, bind-mounted repo files must be world-readable and datadirs must be owned by that UID before first start (`configure.sh` can `mkdir` datadirs and print the `chown` step).

## Geth forks (Docker build)

For geth-fork clients (e.g. BSC, Neo X, Bitlayer) built with:

```bash
go run build/ci.go install -static ./cmd/geth
```

prefer a **glibc** image pair:

- **Builder**: `golang:*-bookworm`
- **Runtime**: `ubuntu` or `debian`

Alpine (`golang:*-alpine` + musl) static builds often fail linking the bundled `libgmp`, with linker errors such as `undefined reference to __fprintf_chk`. Before using Alpine, check the upstream repo for `Dockerfile.debian` or another glibc-based Dockerfile.



## Environment variables



### op-node L1 (required)

op-node does **not** read generic names. Use the `OP_NODE_`* prefix:


| Wrong (ignored) | Correct              |
| --------------- | -------------------- |
| `L1_RPC`        | `OP_NODE_L1_ETH_RPC` |
| `L1_BEACON`     | `OP_NODE_L1_BEACON`  |


If L1 vars are missing, op-node fails at startup with: `flag l1 is required`.

### op-node network preset

Prefer built-in network names when available:

```
OP_NODE_NETWORK=mode-mainnet   # or bob-mainnet
OP_NODE_ROLLUP_CONFIG=         # empty = use built-in preset
```

Bootnodes and static peers: [Conduit bootnodes (OP Stack)](#conduit-bootnodes-op-stack) when not using a built-in preset.

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

Both services mount the same `config/jwt.hex` (op-reth: `--authrpc.jwtsecret`; op-node: `OP_NODE_L2_ENGINE_AUTH`). Regenerating JWT requires restarting **both** containers. Do not use a custom entrypoint to write JWT at runtime unless necessary.

`create-jwt.sh` must make the bind-mounted secret readable by container UIDs (often non-root): **`chmod a+rX config`** (traverse) and **`chmod 644 config/jwt.hex`**. Without this, op-reth/op-node fail to open the JWT on first start. See also [First-start permissions](#first-start-permissions).

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
4. Set RPC **`GAS_CAP=600000000`** (env + client flag) unless the chain requires a different value — see [RPC gas cap](#rpc-gas-cap).
5. **Research snapshot sources** — check official docs, client repos, and node-operator guides for mainnet (and testnet, if supported) snapshots. Prefer documenting a restore path over full genesis sync when a reliable source exists.
6. **Add** `<chain>/README.md` — minimal start/snapshot/testnet steps (see Chain README above); include **Pruning Mode** / **State retention** when applicable.
7. **Update** root `README.md` — Supported Chains table (status, type, execution client); remove from Planned if applicable.
8. **Update** `CHAIN_LINKS.md` — official explorer (if any), docs, network specs, and client repo/release links.
9. Check `.gitignore` for secrets and generated files (`.env`, JWT, downloaded binaries).

### Prometheus / Grafana (when included in compose)

10. Document host datadir paths and first-start `chown` for Prometheus (`65534:65534`) and Grafana (`472:0`) in `<chain>/README.md` (see [Prometheus and Grafana](#prometheus-and-grafana-optional-monitoring)).

### OP Stack (op-node + execution client)

11. `create-jwt.sh` and mount shared JWT for Engine API auth.
12. Use `OP_NODE_L1_*` env vars in a single `.env`.
13. Set `OP_NODE_SAFEDB_PATH` and persist op-node datadir under `$HOME`.
14. Choose chain spec strategy (built-in `--chain=<name>` vs datadir genesis) and **do not mix** on an existing datadir.
15. Follow [Ports, connectivity, and P2P (L2)](#ports-connectivity-and-p2p-l2): `RPC_BIND_ADDR`, configurable host RPC ports, public P2P (TCP + UDP), op-node admin RPC on localhost, `configure.sh` for `EXT_IP` / `OP_NODE_P2P_ADVERTISE_IP`.

### Conduit OP Stack (additional)

16. Fetch bootnodes/static peers — [Conduit bootnodes (OP Stack)](#conduit-bootnodes-op-stack).
17. Fetch genesis/rollup from Conduit API; verify before committing.

### ZK Stack (external node, when applicable)

18. Follow [ZK Stack / ZKsync external nodes](#zk-stack--zksync-external-nodes) — `matterlabs/external-node`, PostgreSQL, `EN_*` env vars, snapshot bucket, and `ulimits.nofile`.

### Nitro (PathDB / PBSS)

19. Use `STATE_SCHEME=path`, `STATE_HISTORY=0`, and `--execution.caching.archive` for archive defaults (see [Arbitrum Nitro (PathDB / PBSS)](#arbitrum-nitro-pathdb--pbss)).
20. Add a **State retention** section to the chain README — warn that non-zero `state-history` prunes on change or snapshot restore.

