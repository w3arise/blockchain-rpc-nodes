# Blockchain RPC Nodes

Self-hosted RPC & archive nodes for EVM chains — Docker Compose setups for BSC, Arbitrum, Optimism & Linea. More chains added regularly.

## Structure

```
chain/
├── docker-compose.yml   # service definition (container, ports, volumes, command flags)
├── env.template         # configuration variables (copy to .env before use)
└── config/              # optional: JWT secrets, genesis files, rollup configs
```

## Supported Chains

| Chain | Type | Execution Client | Status |
| --- | --- | --- | --- |
| BSC | L1 | bsc-geth | ✅ Ready |
| Arbitrum | L2 (Nitro) | nitro | ✅ Ready |
| Optimism | L2 (OP Stack) | op-reth + op-node | ✅ Ready |
| Linea | L2 (ZK) | Besu / Nethermind + Maru | ✅ Ready |
| Bob | L2 (OP Stack) | op-reth | 🚧 Planned |
| Mode | L2 (OP Stack) | op-reth | 🚧 Planned |
| Ronin | L1 (Gaming) | ronin-geth | 🚧 Planned |
| Sonic | L1 | sonic-node | 🚧 Planned |
| XLayer | L2 (Polygon CDK) | xlayer-node | 🚧 Planned |
| Fantom (FTM) | L1 | go-opera | 🚧 Planned |
| Hyperliquid | L1 | hl-node | 🚧 Planned |
| Mantle | L2 (OP Stack) | mantle-node | 🚧 Planned |
| 0G | L1 | 0g-node | 🚧 Planned |
| Abstract | L2 (ZK Stack) | — | 🚧 Planned |
| Apechain | L2 (Arbitrum Orbit) | — | 🚧 Planned |
| Astar (L1) | L1 | — | 🚧 Planned |
| B² Network | L2 (Bitcoin) | — | 🚧 Planned |
| Berachain | L1 | — | 🚧 Planned |
| Bitlayer | L2 (Bitcoin) | — | 🚧 Planned |
| Bittensor | L1 | — | 🚧 Planned |
| Core | L1 | — | 🚧 Planned |
| Cronos | L1 | — | 🚧 Planned |
| Etherlink (Tezos) | L2 | — | 🚧 Planned |
| Gnosis Chain (xDai) | L1 | — | 🚧 Planned |
| Hashkey Chain | L2 (OP Stack) | — | 🚧 Planned |
| Hedera | L1 | — | 🚧 Planned |
| Hemi | L2 (Bitcoin/Ethereum) | — | 🚧 Planned |
| Kaia | L1 | — | 🚧 Planned |
| Katana (Polygon) | L2 (Polygon CDK) | — | 🚧 Planned |
| Lens | L2 (ZK Stack) | — | 🚧 Planned |
| Lisk | L2 (OP Stack) | — | 🚧 Planned |
| MegaETH | L2 | — | 🚧 Planned |
| Monad | L1 | — | 🚧 Planned |
| Morph | L2 | — | 🚧 Planned |
| Neo X | L1 (EVM-compatible) | — | 🚧 Planned |
| Nexon Henesys | L2 | — | 🚧 Planned |
| Pharos | L1 | — | 🚧 Planned |
| Robinhood Chain | L2 | — | 🚧 Planned |
| Scroll | L2 (ZK) | — | 🚧 Planned |
| Sei | L1 | — | 🚧 Planned |
| Soneium | L2 (OP Stack) | — | 🚧 Planned |
| Superseed | L2 (OP Stack) | — | 🚧 Planned |
| Tac | L2 | — | 🚧 Planned |
| Tempo | L1 | — | 🚧 Planned |
| Worldchain | L2 (OP Stack) | — | 🚧 Planned |
| XDC | L1 | — | 🚧 Planned |
| Zircuit | L2 (ZK) | — | 🚧 Planned |
| opBNB | L2 (OP Stack) | — | 🚧 Planned |

## Quick Start

```
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
- Status legend: ✅ Ready — Docker setup available and tested. 🚧 Planned — on the roadmap, not yet added.
