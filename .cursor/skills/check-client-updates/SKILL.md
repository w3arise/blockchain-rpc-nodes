---
name: check-client-updates
description: Audits and bumps pinned blockchain client versions in this repo. Use when the user asks to check for updates, upgrade a chain, bump image tags or MONAD_VERSION, compare env.template pins to upstream, audit client/release versions, or infer whether a bump is tag-only vs needs config/datadir work.
---

# Check client updates

1. Read [`CLIENT_UPDATES.md`](../../../CLIENT_UPDATES.md) at the repo root **before** querying GitHub or Docker Hub. Follow its comparison policy and per-chain sources. Do not invent a generic “latest OP Labs / Nitro” target for chains that publish their own images.
2. Extract pins from `env.template` (or the path in that doc). Re-check upstream this run — do not reuse last week’s “latest” tags, and do not write them into `CLIENT_UPDATES.md`.
3. For every pin that is behind latest, **read release notes (or the git compare) from the pinned tag through latest** — GitHub `.../compare/PINNED...LATEST`, the chain’s upgrade docs, and official compose if that is the comparison source. Infer a class:
   - **pin-only** — binary/image swap; no compose flags, genesis/waypoint, JWT, snapshot wipe, or datadir migration.
   - **needs-config** — new/removed flags, genesis, snapshot recovery, schema/migration, paired-component bump, or “breaking / operator action required.”
   If notes are missing or ambiguous, class is **needs-config** (do not guess pin-only). Quote the evidence (release bullets, compare files).
4. Present findings (chain, client, pinned, latest stable, inferred class, evidence). Prefer a canvas for a full-repo audit. The YAML allowlist in [`scripts/auto-upgrade.yaml`](../../../scripts/auto-upgrade.yaml) is a prior human guess for the *series*; this notes check is the per-bump override:
   - Allowlisted + pin-only → safe to merge a tag-only PR / bump the pin.
   - Allowlisted + needs-config → **do not** treat as tag-only; say so; do not merge the auto-PR; recommend dropping or pausing the YAML row until a human bump lands.
   - `needs-review` in CLIENT_UPDATES + pin-only → still wait for the user to pick; you may *recommend* adding it to the allowlist after this series is pinned.
5. **Do not bump `needs-review` or needs-config chains until the user picks.** Then change `env.template` and any README / `CHAIN_LINKS.md` the upgrade path requires. Live-node steps stay in `<chain>/README.md`. Same-series YAML `tag-only` pins may also be proposed by `scripts/check-auto-upgrades.sh` (CI does **not** read notes — this agent check is what infers pin-only vs needs-config).
6. When adding a chain, add a **Sources** row to `CLIENT_UPDATES.md` (lookup only, not a version snapshot). If it is a same-series image swap with no config/datadir work, add a `tag-only` row to [`scripts/auto-upgrade.yaml`](../../../scripts/auto-upgrade.yaml); otherwise leave **Upgrade class** as `needs-review`.
