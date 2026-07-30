# XDC (XDPoSChain)

Mainnet RPC node — **hash-full** (`GC_MODE=full`): full blocks/receipts/logs, pruned state. Chain data: `$HOME/xdc-data`.

## Start

```bash
./configure.sh
docker compose pull
./restore-snapshot.sh    # preferred; or ./init-database.sh for genesis sync
docker compose up -d
```

## Snapshot

Official **full** mainnet tarball from [rpc.xdc.network/snapshots](https://rpc.xdc.network/snapshots/mainnet/full/) (~859 GB download; plan **≥1.5–2 TB** disk). URL in `.env` (`SNAPSHOT_URL`). `./restore-snapshot.sh` downloads/extracts into `$HOME/xdc-data`. Skip `init-database.sh` after restore.

Archive (full historical state) snapshots are separate: [mainnet/archive](https://rpc.xdc.network/snapshots/mainnet/archive/) — use only with `GC_MODE=archive`.

## Pruning Mode

| Mode | Flags | Receipts / logs | State |
| --- | --- | --- | --- |
| **Hash full (this setup)** | `SYNC_MODE=full` `GC_MODE=full` | Full | Recent only (~128 blocks) |
| Hash archive | `GC_MODE=archive` | Full | Full (much heavier; ≥2 TB) |

This client is the legacy XDPoSChain line (geth ~1.8.3 fork with EIP backports) — no PBSS/`--state.scheme`. Do not point a modern-geth / path-scheme binary at this datadir.

## Host ports

Inbound P2P: **30101** TCP+UDP. HTTP/WS: localhost **8989** / **8888**.

Docs: [Run a node](https://docs.xdc.network/xdcchain/developers/node_operators/masternode/) · [XDPoSChain](https://github.com/XinFinOrg/XDPoSChain) · [XinFin-Node](https://github.com/XinFinOrg/XinFin-Node)
