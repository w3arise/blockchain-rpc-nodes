---
name: check-client-updates
description: Audits and bumps pinned blockchain client versions in this repo. Use when the user asks to check for updates, upgrade a chain, bump image tags or MONAD_VERSION, compare env.template pins to upstream, audit client/release versions, infer pin-only vs needs-config, or apply a pin on a host.
---

# Check client updates

1. Read [`CLIENT_UPDATES.md`](../../../CLIENT_UPDATES.md) **and** [`AUTO_UPGRADES.md`](../../../AUTO_UPGRADES.md) (start with **Current status**) before querying GitHub or Docker Hub. Follow the comparison policy and per-chain **Sources** row. Do not invent a generic “latest OP Labs / Nitro” target for chains that publish their own images.
2. Extract pins from `env.template` (or the path in that doc). Re-check upstream this run — do not reuse last week’s “latest” tags, and do not write them into `CLIENT_UPDATES.md`. Allowlisted chains: `./scripts/check-auto-upgrades.sh` (no `--write`) is a useful same-series tag check; it does **not** read release notes.
3. For every pin behind latest, **read release notes / git compare from the pinned tag through latest**, plus the chain’s upgrade docs and official compose when that is the comparison source. Infer a class:
   - **pin-only** — image/binary swap; no compose flags, genesis/waypoint, JWT, snapshot wipe, or datadir/schema migration (including one-way DB: cannot open with the old tag).
   - **needs-config** — new/removed flags, genesis, snapshot recovery, schema/Flyway, paired-component bump, “breaking / operator action required,” or a **major.minor series jump** (Aptos `1.48`→`1.49`, Nitro `3.7`→`3.11`, EN `v29`→`v31`) even if the notes look like a hotfix.
   Missing or unclear notes → **needs-config**. Quote evidence. Crossing series is never pin-only.
4. Present findings (chain, client, pinned, latest stable, YAML allowlist yes/no, inferred class, evidence). Prefer a canvas for a full-repo audit. YAML [`scripts/auto-upgrade.yaml`](../../../scripts/auto-upgrade.yaml) is a prior human guess for the *series*; this notes check is the per-bump override:
   - Allowlisted + pin-only → CI may already have a pin PR; **still wait for the user** before merge/bump. Then hosts: `./scripts/apply-tag-only.sh <id>`.
   - Allowlisted + needs-config → not tag-only; do not merge the auto-PR; recommend pausing/dropping the YAML row.
   - `needs-review` + pin-only → wait for the user; you may *recommend* a YAML row after this series is pinned (do not add it unless they ask).
   - `needs-review` + needs-config → wait for the user; host steps in `<chain>/README.md` (backup / manual `.env` pin). **Never** `apply-tag-only.sh` without a YAML row.
5. **Do not bump any pin, edit YAML, or run host apply until the user picks.** After they pick: `env.template` (and README / `CHAIN_LINKS.md` if the upgrade path or docs change). Keep CLIENT_UPDATES **Upgrade class** in sync with YAML. Live-node steps stay in `<chain>/README.md`. Committing `env.template` does not update host `.env` — tag-only: `apply-tag-only.sh`; otherwise copy **only** the pin line into `.env` (do not recopy the whole template).
6. When adding a chain: Sources row in `CLIENT_UPDATES.md` (lookup only). YAML `tag-only` row **only if the user asked** and the series is a same-series image swap with no compose/datadir work; otherwise **Upgrade class** stays `needs-review`.
