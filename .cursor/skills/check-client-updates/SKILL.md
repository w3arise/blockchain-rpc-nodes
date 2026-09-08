---
name: check-client-updates
description: Audits and bumps pinned blockchain client versions in this repo. Use when the user asks to check for updates, upgrade a chain, bump image tags or MONAD_VERSION, compare env.template pins to upstream, or audit client/release versions.
---

# Check client updates

1. Read [`CLIENT_UPDATES.md`](../../../CLIENT_UPDATES.md) at the repo root **before** querying GitHub or Docker Hub. Follow its comparison policy and per-chain sources. Do not invent a generic “latest OP Labs / Nitro” target for chains that publish their own images.
2. Extract pins from `env.template` (or the path in that doc). Re-check upstream this run — do not reuse last week’s “latest” tags, and do not write them into `CLIENT_UPDATES.md`.
3. Present findings (chain, client, pinned, latest stable, notes). Prefer a canvas for a full-repo audit.
4. **Do not bump until the user picks** chains/components. Then change `env.template` and any README / `CHAIN_LINKS.md` the upgrade path requires. Live-node steps stay in `<chain>/README.md`.
5. When adding a chain, add a **Sources** row to `CLIENT_UPDATES.md` (lookup only, not a version snapshot).
