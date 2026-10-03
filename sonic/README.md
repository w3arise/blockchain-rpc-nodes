# Sonic (sonicd)

Mainnet RPC node. Chain data: `$HOME/sonic-data`.

## Start

```bash
./configure.sh
docker compose build
./sonic-init.sh
docker compose up -d
```

`./configure.sh` creates `.env`, sets `EXT_IP`, and creates `$HOME/sonic-data`. `./sonic-init.sh` downloads `GENESIS_URL` (default pruned mainnet) and primes the datadir. The file stays under `$HOME/sonic-snapshot-tmp`. An existing `chaindata` and `carmen` pair skips the download and the import.

RPC: `http://127.0.0.1:18545` · WS: `ws://127.0.0.1:18546`

## Upgrade

Copy `SONIC_VERSION` into `.env`, `docker compose build`, recreate the container. [v2.2.2](https://github.com/0xsoniclabs/sonic/releases/tag/v2.2.2) is a stability release (shutdown races, memory, `eth_feeHistory` API fields). No genesis re-import on an existing datadir.

## Snapshot

Sonic primes the database from a genesis file published at [genesis.soniclabs.com](https://genesis.soniclabs.com/). `./sonic-init.sh` downloads `GENESIS_URL` and sets `GENESIS_FILE`. Then:

```bash
docker compose build          # skip when the image is already built
./sonic-init.sh
docker compose up -d
```

The default URL is the pruned genesis. History covers the epoch in that file. For full history, set `GENESIS_URL=https://genesis.soniclabs.com/latest-sonic-archive.g` in `.env` and run `./sonic-init.sh` on an empty datadir.

The genesis archive is left on disk under `$HOME/sonic-snapshot-tmp` (or `SNAPSHOT_TMPDIR`). Remove it when you no longer need it.

## Pruning Mode

Sonic pruning is controlled by `--mode`, not a separate prune flag.

| Mode | Used for | Pruning |
| --- | --- | --- |
| `rpc` (default) | RPC / archive nodes | No live pruning; keeps history |
| `validator` | Validators only | Live pruning; most RPC calls disabled |

This compose setup does **not** pass `--mode`, so `sonicd` runs in **`rpc` mode**. Do not add `--mode validator` for an archive node.

When priming with `./sonic-init.sh`, use an **archive** genesis (`latest-sonic-archive.g`) for full history. A **pruned** genesis limits history to the epoch in that file even in `rpc` mode. `./sonic-init.sh` leaves an existing datadir unchanged when both `chaindata` and `carmen` are present. Re-priming starts from an empty datadir: remove those two directories first. A `chaindata/unfinished` file means the previous import stopped early.

## Testnet

Set `GENESIS_URL` to a testnet file (for example `https://genesis.soniclabs.com/latest-testnet-pruned.g`) and a separate `HOST_DATADIR` in `.env`, then run `./sonic-init.sh`.

## Host ports

Compose uses `network_mode: host`. P2P: port 5050 (TCP + UDP, sonicd default). RPC: `HTTP_PORT` (default `18545`) / `WS_PORT` (default `18546`) are bound by `HTTP_ADDR` / `WS_ADDR` (default `0.0.0.0`).

Docs: [Archive node](https://docs.soniclabs.com/sonic/node-deployment/archive-node) · [Genesis files](https://genesis.soniclabs.com/) · [0xsoniclabs/sonic](https://github.com/0xsoniclabs/sonic)
