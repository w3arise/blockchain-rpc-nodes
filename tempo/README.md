# Tempo (tempo)

Mainnet archive RPC node (Reth SDK execution + Simplex BFT). Chain data: `$HOME/tempo-data`.

Execution data must be on **local NVMe** — network volumes (EBS, GCP PD, etc.) are not supported. See [system requirements](https://docs.tempo.xyz/guide/node/system-requirements).

## Start

```bash
./configure.sh
./restore-snapshot.sh
docker compose up -d
```

RPC: `http://127.0.0.1:42175` · WS: `ws://127.0.0.1:42176`

## Snapshot

Official modular snapshots: [snapshots.tempoxyz.dev](https://snapshots.tempoxyz.dev/). `./restore-snapshot.sh` runs `tempo download --archive` into `$HOME/tempo-data` (set `SNAPSHOT_PROFILE` in `.env`). Then:

```bash
./configure.sh              # skip if .env already set
docker compose up -d        # skip restore-snapshot.sh when datadir is already populated
```

Use `./restore-snapshot.sh --force` only when intentionally replacing snapshot data in an existing datadir.

## State retention

Reth-style profiles via snapshot / prune config:

| Profile | Flag / snapshot | Retention |
| --- | --- | --- |
| Archive (default RPC) | `--archive` snapshot; no `--full`/`--minimal` at runtime | Full history (blocks, receipts/logs, state) |
| Full | `SNAPSHOT_PROFILE=full` | Recent window (~10k blocks) for receipts / state history |
| Minimal | `SNAPSHOT_PROFILE=minimal` | Aggressive prune — validators only |

This compose setup is **archive**: do not add `--full` or `--minimal` on the running node. Switching an archive datadir to a pruned profile destroys history.

## Testnet

Set in `.env` before configure/restore:

```
CHAIN=moderato
FOLLOW_URL=wss://rpc.moderato.tempo.xyz
HOST_DATADIR=$HOME/tempo-moderato-data
```

Then `./restore-snapshot.sh` and `docker compose up -d`.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 42175 | localhost | HTTP JSON-RPC |
| 42176 | localhost | WebSocket |
| 9000 | localhost | Prometheus metrics |
| 30303 | public | Execution P2P (TCP + UDP) |

Change `RPC_BIND_ADDR` to `0.0.0.0` only when LAN access to RPC is intentional.

Docs: [RPC nodes](https://docs.tempo.xyz/guide/node/rpc) · [Install](https://docs.tempo.xyz/guide/node/installation) · [tempoxyz/tempo](https://github.com/tempoxyz/tempo)
