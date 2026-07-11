# Blockchain RPC Nodes

Self-hosted RPC & archive nodes for EVM chains — Docker Compose setups for BSC, Arbitrum, Optimism, and Linea. More chains coming.

## Structure

```
chain/
├── docker-compose.yml   # service definition (container, ports, volumes, command flags)
├── env.template         # configuration variables (copy to .env before use)
└── config/              # optional: JWT secrets, genesis files, rollup configs
```

## Supported Chains

| Chain | Type | Execution Client |
|-------|------|-----------------|
| BSC | L1 | bsc-geth |
| Arbitrum | L2 (Nitro) | nitro |
| Optimism | L2 (OP Stack) | op-reth + op-node |
| Linea | L2 (ZK) | Besu / Nethermind + Maru |

## Quick Start

```bash
# 1. Choose a chain
cd <chain>

# 2. Configure environment
cp env.template .env
# edit .env — at minimum set EXT_IP and any credentials

# 3. Start the node
docker compose up -d
```

## Notes

- Chain data is stored on the host (typically `$HOME/chain-data`), not inside the container.
- `.env` files are gitignored — never commit secrets or private keys.
- OP Stack chains require a shared JWT for Engine API authentication between `op-node` and `op-reth`.
- Environment variables are documented inline in each `env.template`.
- Linea provides two execution client options: Besu (`besu-compose.yml`) or Nethermind (`nether-compose.yml`).
