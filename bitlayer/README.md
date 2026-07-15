# Bitlayer (bitlayer-l2 geth)

Mainnet RPC node (Bitlayer PoS V1). Chain data: `$HOME/bitlayer-data`.

## Start

```bash
./configure.sh
docker compose build
./init-database.sh
docker compose up -d
```

## Snapshot

No official public snapshot is published. Sync from genesis via P2P (snap sync by default).

## Archive

For archive RPC (e.g. The Graph), set in `.env`:

```
SYNC_MODE=full
GCMODE=archive
```

Also set `SyncMode = "full"` in `config/config.toml`.

Docs: [Compile, Run and Deploy](https://docs.bitlayer.org/docs/Build/GettingStarted/CompileAndRun/) · [bitlayer-org/bitlayer-l2](https://github.com/bitlayer-org/bitlayer-l2)
