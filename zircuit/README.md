# Zircuit (conduit-op-reth + op-node)

Mainnet OP Stack L2 on **Conduit** infrastructure (chain ID **48900**). Chain data: `$HOME/zircuit-op-reth-data`, `$HOME/zircuit-op-node-data`.

**Client:** [`conduit-op-reth`](https://github.com/conduitxyz/conduit-op-reth) (Conduit op-reth build; GCS snapshots match this client).

**Sync mode:** `OP_NODE_SYNCMODE=execution-layer` — op-node drives op-reth over the Engine API.

**Migration (Aug 2026):** Zircuit mainnet moved from `zircuit1/l2-geth` to Conduit. Pre-Conduit history is served via [`../zircuit-legacy/`](../zircuit-legacy/README.md) + `--rollup.historicalrpc`. Wipe pre-migration l2-geth datadirs before using op-reth; layouts are incompatible.

**Pruning mode:** op-reth **archive** (no `--full` / `--prune.*` flags) — full block, receipt, and log history plus historical state from the Conduit snapshot tip forward.

## Derivation anchor and genesis

`config/rollup.json` anchors derivation at the Conduit migration point, L2 block **32956468** (`genesis.l2.number` — must match `config.bedrockBlock` in `genesis.json`). op-node derives forward from that anchor only, so op-reth must **already contain that block** (Conduit snapshot required):

```
failed to find the L2 Heads to start from: ... could not get payload: not found
```

Blocks below **32956468** are not in the op-reth datadir and are not derivable from L1 under this rollup config.

### `bedrockBlock` (required for historical RPC)

op-reth only proxies to `--rollup.historicalrpc` when the requested block is **below** `config.bedrockBlock`. If it is `0` or missing, pre-fork queries return `null` / header-not-found locally and are **never** forwarded.

For Zircuit mainnet, `config/genesis.json` must have:

```json
"bedrockBlock": 32956468
```

This must match `genesis.l2.number` in `config/rollup.json`. Conduit's API download may still ship `bedrockBlock: 0` — keep **`32956468`** in this repo's genesis after refreshing from Conduit.

**Do not reuse the same genesis for both clients.** Legacy l2-geth uses the original pre-fork chain spec (`bedrockBlock: 0`, built-in `--network=mainnet`). op-reth uses this Conduit genesis with **`32956468`**.

Set **`HISTORICAL_RPC`** in `.env` to a full pre-fork archive (local legacy node: `http://host.docker.internal:11565` or `http://172.17.0.1:11565` from the default bridge). Restart op-reth after genesis or URL changes — **no resync required**.

## Start

```bash
./configure.sh          # .env + EXT_IP / P2P advertise IP
# set OP_NODE_L1_ETH_RPC, OP_NODE_L1_BEACON, HISTORICAL_RPC in .env
./create-jwt.sh
./restore-snapshot.sh   # required — see Derivation anchor above
docker compose up -d
```

When L1 runs on the Docker host, `host.docker.internal` works for L1 URLs (compose sets `extra_hosts`).

After Conduit network upgrades, refresh `config/rollup.json` from the [Conduit API](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) (slug **`zircuit-mainnet`**) and re-apply **`bedrockBlock: 32956468`** in `genesis.json` if the download resets it.

## Snapshot

Conduit requester-pays GCS (required — no genesis sync path):

```bash
# set GCP_PROJECT in .env first
./restore-snapshot.sh
docker compose up -d
```

Manual: `gs://conduit-networks-snapshots/zircuit-mainnet/latest.tar` into `$HOME/zircuit-op-reth-data`. Liquify lz4 snapshots are for **legacy l2-geth** only — see [`../zircuit-legacy/`](../zircuit-legacy/README.md).

## Verify historical RPC

Probe a block well below the fork (e.g. **`0x1000064`** / 16777316) through **op-reth** RPC — all should succeed when legacy is reachable and synced:

```bash
# eth_getBalance
curl -s http://127.0.0.1:11585 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0x0000000000000000000000000000000000000000","0x1000064"],"id":1}'

# eth_call, eth_getTransactionReceipt, debug_traceBlockByNumber — same block; pick a block with txs for traces
```

Gotchas:

- Many early Zircuit blocks are empty — an empty trace result can be legitimate; use a block that contains a transaction.
- Compare a historical `eth_call` with the same call at head; identical values may mean you are silently receiving head state.

If `bedrockBlock` is correct but history still fails, confirm op-reth can reach `HISTORICAL_RPC` from inside its container and the legacy node is fully synced.

## Testnet (Garfield)

Chain ID **48898**. Conduit slug **`zircuit-garfield-testnet`**. Refresh `config/` from the Conduit API, set L1 to Sepolia, `SEQUENCER_HTTP=https://garfield-testnet.zircuit.com`, update P2P bootnodes/static peers, and snapshot `gs://conduit-networks-snapshots/zircuit-garfield-testnet/latest.tar`.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default **11588**) and `OP_NODE_P2P_PORT` (op-node, default **9228**). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Conduit — Run an OP Stack node](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) · [Zircuit RPCs](https://docs.zircuit.com/infra/rpcs) · [Conduit Hub](https://hub.conduit.xyz/)
