# Polygon PoS (Heimdall v2)

Pruned sentry for mainnet (`heimdallv2-137`). Bor in [`polygon-bor/`](../polygon-bor/README.md) reads this REST API. Chain data: `$HOME/polygon-heimdall-data`.

Sentry only: `heimdalld start` with REST on. No `--bridge` and no RabbitMQ.

## Start

```bash
./configure.sh mainnet
./init-database.sh          # init, then genesis download + sha512
./restore-snapshot.sh       # SNAPSHOT_URL = pruned Heimdall tarball
./patch-config.sh
docker compose pull
docker compose up -d
```

Wait until CometBFT is caught up, then start Bor:

```bash
curl -s localhost:26657/status
curl -s localhost:1317/bor/span/1
```

`catching_up` must be false and the span endpoint must return JSON. Heimdall logs a Bor dial error until `polygon-bor` is up on `127.0.0.1:8745`; the sentry still syncs.

## Snapshot

Set `SNAPSHOT_URL` to a **pruned** Heimdall tarball (`.tar.lz4`, `.tar.zst`, or `.tar.gz`). Community sources, listed from the official snapshot page:

- [Official snapshot docs](https://docs.polygon.technology/pos/how-to/snapshots/)
- [All4nodes Polygon](https://all4nodes.io/Polygon)
- [PublicNode Polygon](https://publicnode.com/snapshots#polygon)

`./restore-snapshot.sh` replaces `data/` only and leaves `config/` (genesis, node key, toml). Run `./patch-config.sh` after restore. `min-retain-blocks=2000000` prunes a larger restored blockstore down to that window on first start.

Download staging is `$HOME/polygon-heimdall-snapshot-tmp` (override with `SNAPSHOT_TMPDIR`), on the same volume as the datadir. The script keeps the tarball and the genesis file; delete them when you no longer need them.

Plan Heimdall on the same disk as `$HOME/polygon-bor-data`. Official combined guidance is about **8 TB** for Bor plus Heimdall.

## Pruning Mode

| Setting | Value | What it keeps |
| --- | --- | --- |
| `pruning` | `default` | Recent app-state versions (spans, checkpoints, and clerk records stay in current state) |
| `min-retain-blocks` | `2000000` | CometBFT blockstore window. The client raises any lower non-zero value to this floor. |
| `indexer` | `null` | No tx index. `/tx` and `/tx_search` stay disabled. |

Heimdall v2 block history starts at the migration height in genesis (mainnet initial height `24404501`), not at Polygon genesis. Bor receipts and logs stay in the Bor datadir.

The client floor is `2000000`. A higher `MIN_RETAIN_BLOCKS` keeps a longer window from the next prune onward; blocks already removed stay gone.

## Testnet (Amoy)

```bash
./configure.sh amoy
./init-database.sh
./restore-snapshot.sh
./patch-config.sh
docker compose pull
docker compose up -d
```

This copies `env.template.amoy` to `.env`: container **`heimdall-amoy`**, project **`polygon-heimdall-amoy`**, `$HOME/polygon-heimdall-amoy-data`, chain `heimdallv2-80002`. REST **1318**, CometBFT **26667**, P2P **26666**, metrics **26670**.

Both can run on one host. Start mainnet, then `./configure.sh amoy` and bring Amoy up — that overwrites `.env` and leaves `heimdall` running. `docker compose down` only stops the project named in the current `.env`. To recreate mainnet, run `./configure.sh mainnet` first.

`polygon-bor` Amoy uses the public Heimdall API. Point its `HEIMDALL_URL` at `http://127.0.0.1:1318` when you want the local Amoy sentry instead.

## Host ports

Host network. The container runs as the uid/gid `./configure.sh` writes into `.env`.

| Port | Bind | Role |
| --- | --- | --- |
| 1317 | localhost | Mainnet REST (`polygon-bor` `HEIMDALL_URL`) |
| 26657 | localhost | Mainnet CometBFT RPC |
| 26660 | localhost | Mainnet Prometheus |
| 26656 | public TCP+UDP | Mainnet P2P |
| 1318 / 26667 / 26670 / 26666 | localhost, P2P public | Amoy REST, CometBFT, metrics, P2P |

Open inbound **26656/tcp** and **26656/udp** (Amoy: **26666**) for peers. Change `RPC_BIND_ADDR` only when LAN access to REST is intentional. Metrics stay on `METRICS_BIND_ADDR`.

## Upgrade

Stop the container, copy `HEIMDALL_IMAGE` from `env.template.mainnet` (or `.amoy`) into `.env`, then:

```bash
docker compose pull
docker compose up -d
```

Confirm `catching_up` is false and the span URL on `API_PORT` returns JSON.

Docs: [Full node (Docker)](https://docs.polygon.technology/pos/how-to/full-node/full-node-docker) · [0xPolygon/heimdall-v2](https://github.com/0xPolygon/heimdall-v2) · [Releases](https://github.com/0xPolygon/heimdall-v2/releases)
