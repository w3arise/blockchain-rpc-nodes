# Client version updates

Playbook for auditing and bumping pinned client versions. **Lookup rules only** — do not store “latest as of …” tags here; re-check upstream each run.

When adding a chain, add a row to [Sources](#sources). Pin values live in `env.template` (or the path in that row).

## Procedure

1. Extract pins from `**/env.template*` (`*_IMAGE`, `*_VERSION`, `*_IMAGE_TAG`) and from compose when a chain has no env pin (e.g. `celo-geth/`).
2. Compare each pin using the [policy](#comparison-policy) and the [Sources](#sources) row — not a generic GitHub “latest” if the chain publishes its own images.
3. Present findings (chain, client, pinned, latest stable, notes). **Do not bump until the user picks** which chains and components to upgrade.
4. After a bump: update `env.template` (and README / `CHAIN_LINKS.md` when the upgrade path or official docs change). Follow `<chain>/README.md` for live-node steps (datadir migrations, genesis, JWT).

Optional: dump the audit table to a Cursor canvas. Do not commit a living “pinned vs latest” markdown.

## Comparison policy

- **Chain-official wins.** If the project publishes its own compose, image tags, or required `NODE_IMAGE`, that is the comparison target — even when generic OP Labs / Nitro / Matter Labs is newer.
- **Stable only.** Ignore prereleases (`alpha`, `rc`, `beta`, `-unsafe`, `-testnet`) unless that is all the chain ships.
- **Bump related components together** when the chain requires it (op-reth + op-node; mirror + relay; bera-reth + beacon-kit).
- **Shared Superchain images** (stock `us-docker.pkg.dev/oplabs-tools-artifacts/images/op-*`): compare to `ethereum-optimism/optimism` tags `op-reth/v*` and `op-node/v*` (and `ethereum-optimism/op-geth` when still used). Do not apply that latest to HashKey, B², Celo, Hemi, or XLayer — those use chain images.

### Shared stacks

| Stack | Where to look |
| --- | --- |
| OP Labs op-reth / op-node | `ethereum-optimism/optimism` git tags `op-reth/v*` / `op-node/v*`; images `us-docker.pkg.dev/oplabs-tools-artifacts/images/{op-reth,op-node}:v*` |
| OP Labs op-geth (legacy Superchain) | `ethereum-optimism/op-geth` releases. End of support for Superchain Karst — prefer op-reth unless the chain still requires op-geth. |
| Conduit op-reth | `conduitxyz/conduit-op-reth` releases; `ghcr.io/conduitxyz/conduit-op-reth` |
| Nitro | `OffchainLabs/nitro` releases; `offchainlabs/nitro-node`. Orbit/Caldera chains may pin a fork tag — compare to **that** image, not mainline Nitro, unless the chain docs say otherwise. |
| EigenDA proxy | `Layr-Labs/eigenda` (proxy lives in the monorepo; `Layr-Labs/eigenda-proxy` is archived). Image `ghcr.io/layr-labs/eigenda-proxy`. Celo compose may lag the monorepo — Celo-official wins for `celo/`. |
| ZK Stack EN | Docker Hub `matterlabs/external-node`. Chain-official compose (`Abstract-Foundation/abstract-node`, `lens-protocol/lens-chain-node`) wins over generic Matter Labs tags. |

Need `gh` / GitHub API (`full_network`). Docker Hub: `https://hub.docker.com/v2/repositories/<ns>/<name>/tags?page_size=20`.

## Sources

| Chain | Pin | Compare against |
| --- | --- | --- |
| AB Core | `GETH_VERSION` | `ABFoundationGlobal/abcore` releases |
| Abstract | `EN_VERSION` | `Abstract-Foundation/abstract-node` `docker/.env.mainnet` (not generic EN latest unless Abstract moved) |
| ApeChain | `NITRO_IMAGE` | `ConstellationCrypto/replica-guide-apechain-mainnet` compose (`apechain-v*` on Caldera ECR) |
| Aptos | `APTOS_IMAGE` | `aptos-labs/aptos-core` tags `aptos-node-v*` (ignore `aptos-cli-v*`) |
| Arbitrum | `NITRO_IMAGE` | `OffchainLabs/nitro` (mainline) |
| Berachain | `BERA_RETH_IMAGE`, `BEACON_KIT_IMAGE` | `berachain/bera-reth`, `berachain/beacon-kit` — bump as a pair |
| Bitlayer | `GETH_VERSION` | `bitlayer-org/bitlayer-l2` |
| B² Network | `OP_GETH_IMAGE`, `OP_NODE_IMAGE` | [B² rollup node docs](https://docs.bsquared.network/for-developers/running_rollup_node) / `b2network/docs` — **not** generic OP Labs |
| Bob | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain (OP Labs) |
| BSC | `BSC_IMAGE` | `bnb-chain/bsc` (`ghcr.io/bnb-chain/bsc`) |
| Celo | `OP_RETH_IMAGE`, `OP_NODE_IMAGE`, `EIGENDA_PROXY_IMAGE` | `celo-org/celo-l2-node-docker-compose` (`celo-v*` on Celo registry). EigenDA: Celo compose, not monorepo latest |
| Celo (op-geth) | `celo-geth/docker-compose.yml` | Deprecated stack — prefer `celo/` |
| Core | `GETH_VERSION` | `coredao-org/core-chain` |
| Cronos | `CRONOS_VERSION` | `crypto-org-chain/cronos` |
| Etherlink | `EVM_IMAGE` | GitLab `tezos/tezos` tags `octez-evm-node-v*`; Docker Hub `tezos/tezos-bare` |
| Fantom (FTM) | `SONIC_VERSION` | Legacy Opera. Live chain is `sonic/` |
| Gnosis Chain | `GNOSIS_RETH_IMAGE`, `LIGHTHOUSE_IMAGE` | `gnosischain/reth_gnosis`, `sigp/lighthouse` |
| HashKey Chain | `OP_GETH_IMAGE`, `OP_NODE_IMAGE` | `HashKeyChain/fullnode-sync` README required `NODE_IMAGE` — **not** generic Superchain op-node |
| Hedera | `MIRROR_NODE_VERSION`, `RELAY_VERSION` | `hiero-ledger/hiero-mirror-node`, `hiero-ledger/hiero-json-rpc-relay`. Run `hedera/check-upgrade.sh` when present |
| Hemi | `OP_GETH_IMAGE`, `OP_NODE_IMAGE`, `BSSD_IMAGE` | `hemilabs/hemi-node` `mainnet/docker-compose.yml` (SHA tags). `hemilabs/heminetwork` GitHub `v2` may not match compose |
| Kaia | `KAIA_IMAGE` | `kaiachain/kaia` |
| Katana | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Conduit op-reth + OP Labs op-node |
| Lens | `EN_VERSION` | `lens-protocol/lens-chain-node` `mainnet-external-node.yml` (often older than Matter Labs Docker) |
| Linea | `BESU_IMAGE`, `MARU_IMAGE`, `NETHERMIND_VERSION` | `Consensys/linea-monorepo` getting-started compose + `linea-besu-package` releases. Besu tags are `N.N.N-YYYYMMDD-sha`, not the old `beta-v4.4-rc*` scheme. Nethermind: Linea-recommended, not generic `NethermindEth/nethermind` |
| Lisk | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain (this repo uses op-reth; `LiskHQ/lisk-node` may still pin op-geth) |
| Mode | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain. `op-node` v1.19.3+ required for Mode `--network` Karst gas configs |
| Monad | `MONAD_VERSION` | `category-labs/monad` + [upgrade instructions](https://docs.monad.xyz/node-ops/upgrade-instructions). APT pin; 0.16.1+ needs a page-encoded TrieDB |
| Morph | `GETH_IMAGE`, `NODE_IMAGE` | `morph-l2/go-ethereum` (`morph-v*` tags vs compose `2.2.x`), `morph-l2/morph` |
| Neo X | `GETH_VERSION` | `bane-labs/go-ethereum` |
| opBNB | `OP_GETH_IMAGE_TAG`, `OP_NODE_IMAGE_TAG` | `bnb-chain/op-geth`, `bnb-chain/opbnb` |
| Optimism | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain |
| Pharos | `PHAROS_IMAGE` | `PharosNetwork/resources` + image tag `pharos_community_v*` |
| Plume | `NITRO_IMAGE` | Conduit/Plume docs first; mainline Nitro only if they track it (`*-validator` suffix) |
| Polygon PoS | `BOR_IMAGE` in `polygon-bor/env.template.mainnet` (and `.amoy`) | `0xPolygon/bor` |
| Robinhood Chain | `NITRO_IMAGE` | `OffchainLabs/nitro` (mainline) |
| Ronin | `RONIN_RETH_IMAGE`, `OP_NODE_IMAGE`, `EIGENDA_PROXY_IMAGE` | Conduit op-reth + OP Labs op-node + EigenDA monorepo |
| Sei | `SEID_VERSION` | `sei-protocol/sei-chain` |
| Soneium | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain |
| Sonic | `SONIC_VERSION` | `0xsoniclabs/sonic` |
| Tac | `TACCHAIN_VERSION` | `TacBuild/tacchain` (ignore `-beta` / `-manual` unless requested) |
| Tempo | `TEMPO_IMAGE` | `tempoxyz/tempo` releases; `ghcr.io/tempoxyz/tempo` |
| Worldchain | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | `worldcoin-foundation/simple-worldchain-node` — official EL is `ghcr.io/worldcoin/world-chain`, not stock op-reth |
| XDC | `XDC_VERSION` | `XinFinOrg/XDPoSChain` (ignore `*-testnet`) |
| XLayer | `OP_STACK_IMAGE_TAG`, `OP_GETH_IMAGE_TAG`, `ERIGON_VERSION` | Docker Hub `xlayer/op-node`, `xlayer/op-geth`. `okx/xlayer-erigon` may be private |
| XLayer (op-reth) | `OP_STACK_IMAGE_TAG`, `OP_RETH_IMAGE_TAG` | Docker Hub `xlayer/op-node`, `xlayer/xlayer-reth`; `okx/xlayer-reth` (treat `v0.0.7` as pre until a non-pre release) |
| Zircuit | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Conduit op-reth + OP Labs op-node |
| Zircuit (legacy) | `L2_GETH_IMAGE` | Docker Hub `zircuit1/l2-geth`. Historical only; live chain is `zircuit/` |

## Gotchas

- **Linea Besu** moved from `beta-v4.4-rc*` to `consensys/linea-besu-package:<semver>-<date>-<sha>`.
- **Worldchain** official compose uses `world-chain`, not stock `op-reth`.
- **HashKey / B²** freeze OP Labs tags in their own docs; bumping generic Superchain will desync from their genesis/rollup.
- **Celo** images are `celo-v*` on `us-west1-docker.pkg.dev/devopsre/celo-blockchain-public/`, not OP Labs.
- **Aptos** release feed mixes node, CLI, and `-rc` tags — filter `aptos-node-v*` and skip `-rc` unless asked.
- **Morph geth** GitHub tags are `morph-v2.2.x`; compose/GHCR often `2.2.x` without the prefix.
- **Hemi** pins git SHAs with digests; `heminetwork` GitHub `v2.0.0` is not automatically the compose `bssd` tag.
- **Abstract vs Lens** can pin different `matterlabs/external-node` tags; never copy one onto the other.
- **EigenDA v2** releases are on `Layr-Labs/eigenda`, not the archived proxy repo.
- **Nitro Orbit** (ApeChain, Plume) may require a vendor tag (`apechain-v*`, `*-validator`).
- **Monad** APT `MONAD_VERSION`; 0.16.1+ will not start without a page-encoded TrieDB (MIP-8 Phase A or post-fork snapshot). See `monad/README.md`.
- **op-node v1.19.2** is below the Mode/Metal/Zora Karst gas-config floor (`v1.19.3+`) for built-in `--network` configs.

## After an upgrade (code)

- Keep `GAS_CAP=600000000` unless the chain requires otherwise.
- OP Stack: bump op-reth and op-node together when release notes require it; refresh Conduit genesis/rollup/bootnodes if the chain is Conduit.
- Nitro: PathDB archive defaults unchanged (`STATE_SCHEME=path`, `STATE_HISTORY=0` + archive flag) unless the user asked for pruned.
- Do not mix `--chain=<preset>` vs genesis file on an existing op-reth datadir (`AGENTS.md`).
