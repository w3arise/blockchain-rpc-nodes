# Cronos (cronosd)

Mainnet full RPC node (`cronosmainnet_25-1`). Chain data: `$HOME/cronos-data`.

## Start

```bash
./configure.sh            # .env + EXT_IP + BUILD_UID/GID for the image
docker compose build      # image runs as your host user
./init-database.sh        # cronosd init + genesis
./patch-config.sh         # config.toml + app.toml
docker compose up -d
```

`patch-config.sh` is **idempotent** — safe to re-run after snapshots or `.env` changes. It sets `app.toml` to `pruning = "default"`, `minimum-gas-prices = "1basecro"`, `logs-cap` / `block-range-cap = 100000`, and `gas-cap = 600000000`. Start uses `--home /data` (host `$HOME/cronos-data`). Peer discovery often takes 1–2 minutes after each restart.

RPC: `http://127.0.0.1:8545` · WS: `ws://127.0.0.1:8546`

## Snapshot

Prefer a **default** LevelDB snapshot from [snapshot.cronos.com](https://snapshot.cronos.com/) (matches `pruning=default`). Links expire (~14 days); grab a fresh URL from the site.

```bash
./configure.sh
docker compose build
./init-database.sh          # creates config + genesis; do not wipe after restore
# download .tar.lz4 from snapshot.cronos.com (default / leveldb)
# stop if running: docker compose down
# unpack into $HOME/cronos-data (layout includes data/); keep existing config/
./patch-config.sh             # re-apply if snapshot overwrote config
docker compose up -d
```

Skip genesis sync; the node catches up from the snapshot height.

## Pruning Mode

| `pruning` | Role | Storage (approx.) |
| --- | --- | --- |
| `default` (this setup) | Full RPC | ~1T and growing |
| `nothing` | Archive | multi-TB |
| `everything` | Pruned / validator-style | smallest |

Change only on a fresh datadir or matching snapshot type. Do not switch an archive datadir to `default`/`everything` unless you intend to discard history.

## Host ports

| Port | Bind | Role |
| --- | --- | --- |
| 8545 | localhost | EVM JSON-RPC HTTP |
| 8546 | localhost | EVM JSON-RPC WS |
| 26657 | localhost | Tendermint RPC |
| 1317 | localhost | Cosmos REST API |
| 9090 | localhost | gRPC |
| 26656 | public TCP+UDP | CometBFT P2P |

Change `RPC_BIND_ADDR` in `.env` to `0.0.0.0` only if you need LAN access to RPC. Open inbound **26656/tcp** and **26656/udp** for peers.

Docs: [Cronos mainnet](https://docs.cronos.com/for-node-hosts/running-nodes/cronos-mainnet) · [Native snapshots](https://docs.cronos.com/for-node-hosts/running-nodes/cronos-evm-snapshots/cronos-native-snapshots) · [crypto-org-chain/cronos](https://github.com/crypto-org-chain/cronos)
