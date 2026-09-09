# Client version updates

Playbook for auditing and bumping pinned client versions. **Lookup rules only** — do not store “latest as of …” tags here; re-check upstream each run.

When adding a chain, add a row to [Sources](#sources). Pin values live in `env.template` (or the path in that row). Tag-only auto-upgrades (same-series image swap, no config/datadir work) also need a row in [`scripts/auto-upgrade.yaml`](scripts/auto-upgrade.yaml) — architecture: [AUTO_UPGRADES.md](AUTO_UPGRADES.md).

## Procedure

1. Extract pins from `**/env.template*` (`*_IMAGE`, `*_VERSION`, `*_IMAGE_TAG`) and from compose when a chain has no env pin (e.g. `celo-geth/`).
2. Compare each pin using the [policy](#comparison-policy) and the [Sources](#sources) row — not a generic GitHub “latest” if the chain publishes its own images.
3. Present findings (chain, client, pinned, latest stable, **inferred class**, notes). For each bump, read release notes / git compare (pin → latest) and class **pin-only** vs **needs-config** — see [AUTO_UPGRADES.md](AUTO_UPGRADES.md#agent-release-notes-check). **Do not bump `needs-review` or needs-config until the user picks.** YAML `tag-only` chains may also get a CI pin PR (`scripts/check-auto-upgrades.sh`); that script does not read notes.
4. After a bump: update `env.template` (and README / `CHAIN_LINKS.md` when the upgrade path or official docs change). Follow `<chain>/README.md` for live-node steps (datadir migrations, genesis, JWT). Hosts apply merged tag-only pins with [`scripts/apply-tag-only.sh`](scripts/apply-tag-only.sh).

Optional: dump the audit table to a Cursor canvas. Do not commit a living “pinned vs latest” markdown.

Local cache (gitignored): [`scripts/.client-audit-cache.json`](scripts/.client-audit-cache.json). It stores the last notes-check table plus `checked_at`. Agents may reuse it for the overview table when it is within `fresh_hours` (default 24) **and** each row’s `pinned` still matches `env.template`. Re-read pins from git every time (cheap). Re-fetch GitHub/compose only for stale/drifted rows, or when the user asks for a fresh audit. Same-series YAML tags can still be checked with `./scripts/check-auto-upgrades.sh` (no notes). After a full audit, rewrite the cache and bump `checked_at`.

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
| ZK Stack EN | Docker Hub `matterlabs/external-node`. Abstract: helm `charts/abstract-node/values.yaml` (`image.tag` + `image.digest`). Lens: `lens-protocol/lens-chain-node` compose. Never generic Matter Labs latest. |

Need `gh` / GitHub API (`full_network`). Docker Hub: `https://hub.docker.com/v2/repositories/<ns>/<name>/tags?page_size=20`.

## Tag-only auto-upgrades

Architecture, diagrams, host apply, and the GitHub Actions PR permission: **[AUTO_UPGRADES.md](AUTO_UPGRADES.md)**.

Allowlist: [`scripts/auto-upgrade.yaml`](scripts/auto-upgrade.yaml). Keep the [Sources](#sources) **Upgrade class** column in sync (`tag-only` vs `needs-review`).

## Sources

| Chain | Pin | Compare against | Upgrade class |
| --- | --- | --- | --- |
| AB Core | `GETH_VERSION` | `ABFoundationGlobal/abcore` releases | needs-review |
| Abstract | `EN_VERSION`, `EN_DIGEST` | `Abstract-Foundation/abstract-node` helm `charts/abstract-node/values.yaml` (`image.tag` + `image.digest`). Same pin in `docker/external-node.yml`. Ignore `.env.mainnet` and generic EN latest. | needs-review |
| ApeChain | `NITRO_IMAGE` | [ApeChain run-node docs](https://docs.apechain.com/run-node) image `apechain-3.9.9` (Caldera ECR). GitHub replica-guide may lag. | needs-review |
| Aptos | `APTOS_IMAGE` | `aptos-labs/aptos-core` tags `aptos-node-v*` (ignore `aptos-cli-v*`) | tag-only |
| Arbitrum | `NITRO_IMAGE` | `OffchainLabs/nitro` (mainline) | tag-only |
| Berachain | `BERA_RETH_IMAGE`, `BEACON_KIT_IMAGE` | `berachain/bera-reth`, `berachain/beacon-kit` — bera-reth is tag-only; beacon-kit stays needs-review | tag-only |
| Bitlayer | `GETH_VERSION` | `bitlayer-org/bitlayer-l2` | needs-review |
| B² Network | `OP_GETH_IMAGE`, `OP_NODE_IMAGE` | [B² rollup node docs](https://docs.bsquared.network/for-developers/running_rollup_node) / `b2network/docs` — **not** generic OP Labs | needs-review |
| Bob | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain (OP Labs) | tag-only |
| BSC | `BSC_IMAGE` | `bnb-chain/bsc` (`ghcr.io/bnb-chain/bsc`) | needs-review |
| Celo | `OP_RETH_IMAGE`, `OP_NODE_IMAGE`, `EIGENDA_PROXY_IMAGE` | `celo-org/celo-l2-node-docker-compose` (`celo-v*` on Celo registry). EigenDA: Celo compose, not monorepo latest | needs-review |
| Celo (op-geth) | `celo-geth/docker-compose.yml` | Deprecated stack — prefer `celo/` | needs-review |
| Core | `GETH_VERSION` | `coredao-org/core-chain` | tag-only |
| Cronos | `CRONOS_VERSION` | `crypto-org-chain/cronos` | needs-review |
| Etherlink | `EVM_IMAGE` | GitLab `tezos/tezos` tags `octez-evm-node-v*`; Docker Hub `tezos/tezos-bare` | needs-review |
| Fantom (FTM) | `SONIC_VERSION` | Legacy Opera. Live chain is `sonic/` | needs-review |
| Gnosis Chain | `GNOSIS_RETH_IMAGE`, `LIGHTHOUSE_IMAGE` | `gnosischain/reth_gnosis`, `sigp/lighthouse` | needs-review |
| HashKey Chain | `OP_GETH_IMAGE`, `OP_NODE_IMAGE` | `HashKeyChain/fullnode-sync` README required `NODE_IMAGE` — **not** generic Superchain op-node | needs-review |
| Hedera | `MIRROR_NODE_VERSION`, `RELAY_VERSION` | `hiero-ledger/hiero-mirror-node`, `hiero-ledger/hiero-json-rpc-relay`. Run `hedera/check-upgrade.sh` when present | needs-review |
| Hemi | `OP_GETH_IMAGE`, `OP_NODE_IMAGE`, `BSSD_IMAGE` | `hemilabs/hemi-node` `mainnet/docker-compose.yml` (SHA tags). `hemilabs/heminetwork` GitHub `v2` may not match compose | needs-review |
| Kaia | `KAIA_IMAGE` | `kaiachain/kaia` | needs-review |
| Katana | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Conduit op-reth + OP Labs op-node | tag-only |
| Lens | `EN_VERSION` | `lens-protocol/lens-chain-node` `mainnet-external-node.yml` (often older than Matter Labs Docker) | needs-review |
| Linea | `BESU_IMAGE`, `MARU_IMAGE`, `NETHERMIND_VERSION` | `Consensys/linea-monorepo` getting-started compose + `linea-besu-package` releases. Besu tags are `N.N.N-YYYYMMDD-sha`, not the old `beta-v4.4-rc*` scheme. Nethermind: Linea-recommended, not generic `NethermindEth/nethermind` | needs-review |
| Lisk | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain (this repo uses op-reth; `LiskHQ/lisk-node` may still pin op-geth) | tag-only |
| Mode | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain. `op-node` v1.19.3+ required for Mode `--network` Karst gas configs | tag-only |
| Monad | `MONAD_VERSION` | `category-labs/monad` + [upgrade instructions](https://docs.monad.xyz/node-ops/upgrade-instructions). APT pin; 0.16.1+ needs a page-encoded TrieDB | needs-review |
| Morph | `GETH_IMAGE`, `NODE_IMAGE` | `morph-l2/go-ethereum` (`morph-v*` tags vs compose `2.2.x`), `morph-l2/morph` | needs-review |
| Neo X | `GETH_VERSION` | `bane-labs/go-ethereum` | tag-only |
| opBNB | `OP_GETH_IMAGE_TAG`, `OP_NODE_IMAGE_TAG` | `bnb-chain/op-geth`, `bnb-chain/opbnb` | needs-review |
| Optimism | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain | tag-only |
| Pharos | `PHAROS_IMAGE` | `PharosNetwork/resources` + image tag `pharos_community_v*` | needs-review |
| Plume | `NITRO_IMAGE` | Conduit/Plume docs first; mainline Nitro only if they track it (`*-validator` suffix) | tag-only |
| Polygon PoS | `BOR_IMAGE` in `polygon-bor/env.template.mainnet` (and `.amoy`) | `0xPolygon/bor` | needs-review |
| Robinhood Chain | `NITRO_IMAGE` | `OffchainLabs/nitro` (mainline) | tag-only |
| Ronin | `RONIN_RETH_IMAGE`, `OP_NODE_IMAGE`, `EIGENDA_PROXY_IMAGE` | Conduit op-reth + OP Labs op-node + EigenDA monorepo. Reth/op-node are tag-only; EigenDA stays needs-review | tag-only |
| Sei | `SEID_VERSION` | `sei-protocol/sei-chain` | tag-only |
| Soneium | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Shared Superchain | needs-review |
| Sonic | `SONIC_VERSION` | `0xsoniclabs/sonic` | needs-review |
| Tac | `TACCHAIN_VERSION` | `TacBuild/tacchain` (ignore `-beta` / `-manual` unless requested) | needs-review |
| Tempo | `TEMPO_IMAGE` | `tempoxyz/tempo` releases; `ghcr.io/tempoxyz/tempo` (image tag omits git `v`) | tag-only |
| Worldchain | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Stock Superchain pins in this repo. Official compose uses `ghcr.io/worldcoin/world-chain`, not stock op-reth | tag-only |
| XDC | `XDC_VERSION` | `XinFinOrg/XDPoSChain` (ignore `*-testnet`) | needs-review |
| XLayer | `OP_STACK_IMAGE_TAG`, `OP_GETH_IMAGE_TAG`, `ERIGON_VERSION` | Docker Hub `xlayer/op-node`, `xlayer/op-geth`. `okx/xlayer-erigon` may be private | needs-review |
| XLayer (op-reth) | `OP_STACK_IMAGE_TAG`, `OP_RETH_IMAGE_TAG` | Docker Hub `xlayer/op-node`, `xlayer/xlayer-reth`; `okx/xlayer-reth` (treat `v0.0.7` as pre until a non-pre release) | needs-review |
| Zircuit | `OP_RETH_IMAGE`, `OP_NODE_IMAGE` | Conduit op-reth + OP Labs op-node | tag-only |
| Zircuit (legacy) | `L2_GETH_IMAGE` | Docker Hub `zircuit1/l2-geth`. Historical only; live chain is `zircuit/` | needs-review |

## Gotchas

- **Linea Besu** moved from `beta-v4.4-rc*` to `consensys/linea-besu-package:<semver>-<date>-<sha>`.
- **Worldchain** official compose uses `world-chain`, not stock `op-reth`.
- **HashKey / B²** freeze OP Labs tags in their own docs; bumping generic Superchain will desync from their genesis/rollup.
- **Celo** images are `celo-v*` on `us-west1-docker.pkg.dev/devopsre/celo-blockchain-public/`, not OP Labs.
- **Aptos** release feed mixes node, CLI, and `-rc` tags — filter `aptos-node-v*` and skip `-rc` unless asked.
- **Morph geth** GitHub tags are `morph-v2.2.x`; compose/GHCR often `2.2.x` without the prefix.
- **Hemi** pins git SHAs with digests; `heminetwork` GitHub `v2.0.0` is not automatically the compose `bssd` tag.
- **Abstract vs Lens** can pin different `matterlabs/external-node` tags; never copy one onto the other. Abstract `.env.mainnet` `EN_VERSION` can lag helm; follow helm tag+digest.
- **EigenDA v2** releases are on `Layr-Labs/eigenda`, not the archived proxy repo.
- **Nitro Orbit** (ApeChain, Plume) may require a vendor tag (`apechain-3.9.9` / older `apechain-v*`, `*-validator`).
- **Monad** APT `MONAD_VERSION`; 0.16.1+ will not start without a page-encoded TrieDB (MIP-8 Phase A or post-fork snapshot). See `monad/README.md`.
- **op-node v1.19.2** is below the Mode/Metal/Zora Karst gas-config floor (`v1.19.3+`) for built-in `--network` configs.
- **Nitro 3.8 / 3.10** one-way datadir (cannot open with 3.7.x / 3.9.x). Arbitrum One replica is pinned at `v3.11.3` and allowlisted for **`v3.11.*` patches** (`image_tag_from: release_body`). A `v3.12` series jump stays `needs-review`. See `arbitrum/README.md`.

## After an upgrade (code)

- Keep `GAS_CAP=600000000` unless the chain requires otherwise.
- OP Stack: bump op-reth and op-node together when release notes require it; refresh Conduit genesis/rollup/bootnodes if the chain is Conduit.
- Nitro: PathDB archive defaults unchanged (`STATE_SCHEME=path`, `STATE_HISTORY=0` + archive flag) unless the user asked for pruned.
- Do not mix `--chain=<preset>` vs genesis file on an existing op-reth datadir (`AGENTS.md`).
- Tag-only pins: land the bump in git, then hosts run `./scripts/apply-tag-only.sh <chain>` (do not re-run `configure.sh` to pick up the pin).
