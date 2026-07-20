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

- [CHAIN_LINKS.md](CHAIN_LINKS.md) — official documentation and client repositories

## Ready


| Chain               | Directory      | Type                                | Execution Client                          | Setup                           |
| ------------------- | -------------- | ----------------------------------- | ----------------------------------------- | ------------------------------- |
| AB Core             | `ab/`          | L1 (EVM-compatible)                 | abcore geth                               | [README](ab/README.md)          |
| ApeChain            | `apechain/`    | L3 (Arbitrum Orbit)                 | Caldera nitro                             | [README](apechain/README.md)    |
| Arbitrum            | `arbitrum/`    | L2 (Nitro)                          | nitro                                     | [README](arbitrum/README.md)    |
| Berachain           | `berachain/`   | L1                                  | bera-reth + beacon-kit                    | [README](berachain/README.md)   |
| Bitlayer            | `bitlayer/`    | L2 (Bitcoin)                        | bitlayer-l2 geth                          | [README](bitlayer/README.md)    |
| Bob                 | `bob/`         | L2 (OP Stack)                       | op-reth + op-node                         | [README](bob/README.md)         |
| BSC                 | `bsc/`         | L1                                  | bsc-geth                                  | [README](bsc/README.md)         |
| Celo                | `celo/`        | L2 (OP Stack / EigenDA)             | celo-op-reth + op-node + eigenda-proxy    | [README](celo/README.md)        |
| Celo (op-geth)      | `celo-geth/`   | L2 (OP Stack / EigenDA, deprecated) | op-geth + op-node + eigenda-proxy         | [README](celo-geth/README.md)   |
| Fantom (FTM)        | `ftm/`         | L1                                  | go-opera (Sonic)                          | —                               |
| Gnosis Chain (xDai) | `gnosis/`      | L1                                  | reth_gnosis + lighthouse                  | [README](gnosis/README.md)      |
| HashKey Chain       | `hashkey/`     | L2 (OP Stack / CGT)                 | op-geth + op-node                         | [README](hashkey/README.md)     |
| Hemi                | `hemi/`        | L2 (OP Stack / Bitcoin)             | hemi op-geth + op-node + bssd             | [README](hemi/README.md)        |
| Kaia                | `kaia/`        | L1                                  | ken (Endpoint Node)                       | [README](kaia/README.md)        |
| Katana              | `katana/`      | L2 (OP Stack / Agglayer CDK)        | conduit-op-reth + op-node                 | [README](katana/README.md)      |
| Linea               | `linea/`       | L2 (ZK)                             | Besu / Nethermind + Maru                  | [README](linea/README.md)       |
| Morph               | `morph/`       | L2 (Optimistic + ZK)                | morph-geth + morph-node                   | [README](morph/README.md)       |
| Neo X               | `neox/`        | L1 (EVM-compatible)                 | bane-labs geth                            | [README](neox/README.md)        |
| Optimism            | `optimism/`    | L2 (OP Stack)                       | op-reth + op-node                         | [README](optimism/README.md)    |
| Robinhood Chain     | `robinhood/`   | L2 (Arbitrum Nitro)                 | nitro                                     | [README](robinhood/README.md)   |
| Ronin               | `ronin/`       | L2 (OP Stack / EigenDA)             | conduit-op-reth + op-node + eigenda-proxy | [README](ronin/README.md)       |
| Soneium             | `soneium/`     | L2 (OP Stack)                       | op-reth + op-node                         | [README](soneium/README.md)     |
| Sonic               | `sonic/`       | L1                                  | sonic-node                                | [README](sonic/README.md)       |
| Worldchain          | `worldchain/`  | L2 (OP Stack)                       | op-reth + op-node                         | [README](worldchain/README.md)  |
| XLayer              | `xlayer/`      | L2 (OP Stack)                       | op-geth + op-node + cdk-erigon (archival) | [README](xlayer/README.md)      |
| XLayer (op-reth)    | `xlayer-reth/` | L2 (OP Stack)                       | xlayer-reth + op-node                     | [README](xlayer-reth/README.md) |
| Abstract            | `abstract/`    | L2 (ZK Stack)                       | external-node + postgres                  | [README](abstract/README.md)    |
| Lens                | `lens/`        | L2 (ZK Stack)                       | external-node + postgres                  | [README](lens/README.md)        |
| opBNB               | `opbnb/`       | L2 (OP Stack)                       | op-geth + op-node                         | [README](opbnb/README.md)       |


## Planned


| Chain             | Type                  | Execution Client |
| ----------------- | --------------------- | ---------------- |
| 0G                | L1                    | 0g-node + 0g-geth |
| Astar (L1)        | L1                    | —                |
| B² Network        | L2 (Bitcoin)          | —                |
| Bittensor         | L1                    | —                |
| Core              | L1                    | —                |
| Cronos            | L1                    | —                |
| Etherlink (Tezos) | L2                    | —                |
| Hedera            | L1                    | —                |
| Hyperliquid       | L1                    | hl-node (visor)  |
| Lisk              | L2 (OP Stack)         | —                |
| Mantle            | L2 (OP Stack)         | mantle-op-geth + mantle-op-node |
| MegaETH           | L2                    | stateless-validator |
| Mode              | L2 (OP Stack)         | op-reth + op-node |
| Monad             | L1                    | —                |
| Nexon Henesys     | L2                    | —                |
| Pharos            | L1                    | —                |
| Scroll            | L2 (ZK)               | —                |
| Sei               | L1                    | —                |
| Superseed         | L2 (OP Stack)         | —                |
| Tac               | L2                    | —                |
| Tempo             | L1                    | —                |
| XDC               | L1                    | —                |
| Zircuit           | L2 (ZK)               | —                |


## Quick Start

```bash
cd <chain>    # e.g. neox, bsc, bob
# follow <chain>/README.md
```

Repo-wide reminders:

- Chain datadirs live under `$HOME` on the host.
- `.env` files are gitignored — never commit secrets or private keys.
- OP Stack and Morph chains need a shared JWT and L1 RPC URLs (Morph: execution RPC only).

## Related docs

- [AGENTS.md](AGENTS.md) — conventions for adding and maintaining chains

