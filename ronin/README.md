# Ronin (conduit-op-reth + op-node + EigenDA)

Mainnet OP Stack rollup with EigenDA Alt-DA. Chain data: `$HOME/ronin-reth-datadir`, `$HOME/ronin-op-node-datadir`.

**Sync mode:** `OP_NODE_SYNCMODE=execution-layer`. From op-node v1.19.1, missed blocks are fetched by op-reth.

**Peers:** op-reth dials `OP_RETH_TRUSTED_PEERS` (Conduit [`elPeers`](https://api.conduit.xyz/public/network/elPeers/ronin-mainnet-bfz9fadqzl) for slug `ronin-mainnet-bfz9fadqzl`). There is no execution-layer discovery mesh, so `net_peerCount` of 1 is expected. op-node follows the tip from `OP_NODE_P2P_STATIC` ([`staticPeers`](https://api.conduit.xyz/public/network/staticPeers/ronin-mainnet-bfz9fadqzl)) with consensus discovery disabled. Copy both values from `env.template` into an existing `.env` and recreate the containers when they change. The trusted peer closes gaps; it does not replace a snapshot. On EigenDA, a gap older than the peer's rolling window cannot be rebuilt from L1.

## Start

```bash
./configure.sh          # create .env, set EXT_IP and P2P advertise IP
# edit .env — set L1_RPC and L1_BEACON
./init-datadirs.sh      # jwt.hex, genesis.json, rollup.json + alt_da patch
docker compose up -d
```

## Saigon (testnet)

Set `RONIN_NETWORK=saigon` in `.env`, then swap L1 endpoints (Sepolia), the sequencer, `OP_RETH_TRUSTED_PEERS`, and `OP_NODE_P2P_STATIC` — see comments in `env.template` (Conduit slug `saigon-testnet-cc58e966ql`). Re-run:

```bash
./init-datadirs.sh --force
docker compose up -d
```

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (op-reth, default `48547`) and `OP_NODE_P2P_PORT` (op-node, default `9222`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Conduit — Run an OP Stack node](https://docs.conduit.xyz/chains/getting-started/run-a-node/op-stack-nodes) · [Conduit Hub](https://hub.conduit.xyz/) · [Ronin docs](https://www.roninchain.com/) · [EigenDA proxy](https://github.com/Layr-Labs/eigenda-proxy)
