# Ronin (conduit-op-reth + op-node + EigenDA)

Mainnet OP Stack rollup with EigenDA Alt-DA. Chain data: `$HOME/ronin-reth-datadir`, `$HOME/ronin-op-node-datadir`.

## Start

```bash
cp env.template .env    # set L1_RPC, L1_BEACON, EXT_IP
./init-datadirs.sh      # jwt.hex, genesis.json, rollup.json + alt_da patch
docker compose up -d
```

## Saigon (testnet)

Set `RONIN_NETWORK=saigon` in `.env`, then swap L1 endpoints (Sepolia), sequencer, and P2P static peer — see comments in `env.template`. Re-run:

```bash
./init-datadirs.sh --force
docker compose up -d
```

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `OP_NODE_P2P_PORT` (default `9222`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Conduit Ronin docs](https://docs.conduit.xyz/chains/ronin) · [Conduit Hub](https://hub.conduit.xyz/) · [Ronin docs](https://www.roninchain.com/) · [EigenDA proxy](https://github.com/Layr-Labs/eigenda-proxy)
