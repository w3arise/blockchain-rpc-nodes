# Blockchain RPC Nodes

Self-hosted RPC and archive nodes for EVM chains, packaged as Docker Compose setups.

Pick a chain below, open its README, and follow the steps there — setup varies by client and network.

## Structure

```
chain/
├── docker-compose.yml   # service definition (ports, volumes, command flags)
├── env.template         # configuration variables (copy to .env before use)
├── README.md            # minimal start steps for this chain
├── configure.sh         # optional: create .env, set EXT_IP
├── init-database.sh     # optional: genesis / datadir init
├── Dockerfile           # optional: local image build
├── create-jwt.sh        # OP Stack only: shared Engine API JWT
└── config/              # genesis, rollup, JWT, chain params
```

Not every chain uses every file. Chain data is stored under `$HOME` on the host, not inside the repo.

## Ready

| Chain | Directory | Type | Execution Client | Setup |
| --- | --- | --- | --- | --- |
| Arbitrum | `arbitrum/` | L2 (Nitro) | nitro | [README](arbitrum/README.md) |
| Berachain | `berachain/` | L1 | bera-reth + beacon-kit | [README](berachain/README.md) |
| Bob | `bob/` | L2 (OP Stack) | op-reth + op-node | [README](bob/README.md) |
| BSC | `bsc/` | L1 | bsc-geth | [README](bsc/README.md) |
| Gnosis Chain (xDai) | `gnosis/` | L1 | reth_gnosis + lighthouse | [README](gnosis/README.md) |
| Linea | `linea/` | L2 (ZK) | Besu / Nethermind + Maru | [README](linea/README.md) |
| Neo X | `neox/` | L1 (EVM-compatible) | bane-labs geth | [README](neox/README.md) |
| Optimism | `optimism/` | L2 (OP Stack) | op-reth + op-node | [README](optimism/README.md) |
| Soneium | `soneium/` | L2 (OP Stack) | op-reth + op-node | [README](soneium/README.md) |
| XLayer | `xlayer/` | L2 (OP Stack) | op-geth + op-node + cdk-erigon (archival) | [README](xlayer/README.md) |
| XLayer (op-reth) | `xlayer-reth/` | L2 (OP Stack) | xlayer-reth + op-node | [README](xlayer-reth/README.md) |

## Planned

| Chain | Type | Execution Client |
| --- | --- | --- |
| 0G | L1 | 0g-node |
| Abstract | L2 (ZK Stack) | — |
| Apechain | L2 (Arbitrum Orbit) | — |
| Astar (L1) | L1 | — |
| B² Network | L2 (Bitcoin) | — |
| Bitlayer | L2 (Bitcoin) | — |
| Bittensor | L1 | — |
| Core | L1 | — |
| Cronos | L1 | — |
| Etherlink (Tezos) | L2 | — |
| Fantom (FTM) | L1 | go-opera |
| Hashkey Chain | L2 (OP Stack) | — |
| Hedera | L1 | — |
| Hemi | L2 (Bitcoin/Ethereum) | — |
| Hyperliquid | L1 | hl-node |
| Kaia | L1 | — |
| Katana (Polygon) | L2 (Polygon CDK) | — |
| Lens | L2 (ZK Stack) | — |
| Lisk | L2 (OP Stack) | — |
| Mantle | L2 (OP Stack) | mantle-node |
| MegaETH | L2 | — |
| Mode | L2 (OP Stack) | op-reth |
| Monad | L1 | — |
| Morph | L2 | — |
| Nexon Henesys | L2 | — |
| opBNB | L2 (OP Stack) | — |
| Pharos | L1 | — |
| Robinhood Chain | L2 | — |
| Ronin | L1 (Gaming) | ronin-geth |
| Scroll | L2 (ZK) | — |
| Sei | L1 | — |
| Sonic | L1 | sonic-node |
| Superseed | L2 (OP Stack) | — |
| Tac | L2 | — |
| Tempo | L1 | — |
| Worldchain | L2 (OP Stack) | — |
| XDC | L1 | — |
| Zircuit | L2 (ZK) | — |

## Quick Start

```bash
cd <chain>    # e.g. neox, bsc, bob
# follow <chain>/README.md
```

Repo-wide reminders:

- Chain datadirs live under `$HOME` on the host.
- `.env` files are gitignored — never commit secrets or private keys.
- OP Stack chains need a shared JWT and L1 RPC/beacon URLs.

## Notes

- Ready — Docker setup available. Planned — on the roadmap, not yet added.
- Linea: Besu (`besu-compose.yml`) or Nethermind (`nether-compose.yml`).
- XLayer: `xlayer/` (op-geth + archival cdk-erigon) or `xlayer-reth/` (op-reth). Run one or both — ports don't clash.

## Related docs

- [CHAIN_LINKS.md](CHAIN_LINKS.md) — official documentation and client repositories
- [AGENTS.md](AGENTS.md) — conventions for adding and maintaining chains
