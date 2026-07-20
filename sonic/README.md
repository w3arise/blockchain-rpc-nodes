# Sonic (sonicd)

Mainnet RPC node. Chain data: `$HOME/sonic-data`.

## Start

```bash
mkdir -p "$HOME/sonic-data"
./configure.sh
curl -JLO https://genesis.soniclabs.com/latest-sonic-pruned.g
mv latest-sonic-pruned.g "$HOME/sonic.g"
docker compose build
./sonic-init.sh
docker compose up -d
```

RPC: `http://127.0.0.1:18545` · WS: `ws://127.0.0.1:18546`

## Snapshot

Sonic uses genesis files to prime the database to a recent state (not a raw chaindata tarball). Download a pruned or archive genesis from [genesis.soniclabs.com](https://genesis.soniclabs.com/), then:

```bash
mkdir -p "$HOME/sonic-data"
./configure.sh              # skip if .env already set
curl -JLO https://genesis.soniclabs.com/latest-sonic-pruned.g
mv latest-sonic-pruned.g "$HOME/sonic.g"
docker compose build
./sonic-init.sh
docker compose up -d
```

Use `latest-sonic-archive.g` for an archive node (larger download and datadir).

## Pruning Mode

Sonic pruning is controlled by `--mode`, not a separate prune flag.

| Mode | Used for | Pruning |
| --- | --- | --- |
| `rpc` (default) | RPC / archive nodes | No live pruning; keeps history |
| `validator` | Validators only | Live pruning; most RPC calls disabled |

This compose setup does **not** pass `--mode`, so `sonicd` runs in **`rpc` mode**. Do not add `--mode validator` for an archive node.

When priming with `./sonic-init.sh`, use an **archive** genesis (`latest-sonic-archive.g`) for full history. A **pruned** genesis limits history to the epoch in that file even in `rpc` mode. Do not re-run `sonic-init.sh` with a pruned genesis against an existing archive datadir.

## Testnet

Download a testnet genesis from [genesis.soniclabs.com](https://genesis.soniclabs.com/) (e.g. `latest-testnet-pruned.g`), point `./sonic-init.sh` at that file, and set a separate `HOST_DATADIR` in `.env` if running both networks.

Docs: [Archive node](https://docs.soniclabs.com/sonic/node-deployment/archive-node) · [Genesis files](https://genesis.soniclabs.com/) · [0xsoniclabs/sonic](https://github.com/0xsoniclabs/sonic)
