# Etherlink (octez-evm-node)

Mainnet full observer (blocks/txs/receipts/logs from genesis; recent state only). Chain data: `$HOME/etherlink-data`.

HW (official): 16 GB RAM / 300 GB disk minimum; **32 GB / 1 TB** recommended.

## Start

```bash
./configure.sh
sudo chown -R 1000:1000 "$HOME/etherlink-data"
docker compose up -d
```

First start imports a Nomadic Labs snapshot (`--init-from-snapshot`) for `HISTORY_MODE`, then catches up from the relay.

RPC: `http://127.0.0.1:42793` · WS: `ws://127.0.0.1:42793/ws`

## Snapshot

Snapshots: [snapshotter-sandbox.nomadic-labs.eu/etherlink-mainnet](https://snapshotter-sandbox.nomadic-labs.eu/etherlink-mainnet/) (`full` matches this setup).

Default path uses compose `--init-from-snapshot` on an empty datadir. To import a URL or file manually:

```bash
./configure.sh
sudo chown -R 1000:1000 "$HOME/etherlink-data"
docker compose run --rm --entrypoint octez-evm-node etherlink-evm \
  snapshot import <SNAPSHOT_URL_OR_FILE> --data-dir=/data
docker compose up -d
```

Skip `init-from-snapshot` concerns once `/data` already has a store — the flag only bootstraps fresh directories.

## Pruning Mode

| Mode | Flag | Retention |
| --- | --- | --- |
| **Full (default)** | `--history full:N` | **All** SQL blocks / txs / blueprints (receipts & logs). Irmin **state** older than N days is pruned. |
| Archive | `--history archive` | All data including unlimited state (~1–2 TB). |
| Rolling | `--history rolling:N` | Drops blocks/txs older than N days — not for historical log RPC. |

This setup uses **`full:1`**. Do not switch an existing full datadir to `rolling` if you need long receipt/log history. Archive → full is supported; full → archive is not without a new datadir/snapshot.

## Testnet

Set in `.env` before configure/start:

```
NETWORK=shadownet
HOST_DATADIR=$HOME/etherlink-shadownet-data
```

Then `./configure.sh`, `chown`, and `docker compose up -d`.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 42793 | localhost | HTTP JSON-RPC + WebSocket (`/ws`) |

No inbound P2P — the observer follows the public relay (`relay.mainnet.etherlink.com`). Change `RPC_BIND_ADDR` to `0.0.0.0` only when LAN access is intentional.

This compose trusts the sequencer (`--dont-track-rollup-node`). To verify blocks, run a [Smart Rollup node](https://docs.etherlink.com/network/smart-rollup-nodes/) and replace that flag with `--rollup-node-endpoint=<SR_RPC>`.

Docs: [EVM node](https://docs.etherlink.com/network/evm-nodes/) · [Network info](https://docs.etherlink.com/get-started/network-information/) · [GitLab releases](https://gitlab.com/tezos/tezos/-/releases)
