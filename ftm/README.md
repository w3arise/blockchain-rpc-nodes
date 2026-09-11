# Fantom Opera (go-opera / sonicd)

Mainnet RPC node using the Fantom-foundation Sonic client (Opera mainnet fork). Chain data: `$HOME/.sonic`.

This setup includes a watcher that automatically detects and heals "dirty state" corruption.

## Start

```bash
./configure.sh          # create .env, set EXT_IP
docker compose build
docker compose up -d
```

RPC: `http://<host>:18545` · WS: `ws://<host>:18546`

The compose uses `network_mode: host`, so ports bind directly to the host.

## Snapshot

Genesis files for Opera are no longer published by the Fantom Foundation. Sync from P2P using the bootnodes in `env.template`.

For faster sync, community snapshots may be available — check Fantom Discord or node operator channels.

## Pruning Mode

Sonic pruning is controlled by `--mode`, not a separate prune flag.

| Mode | Used for | Pruning |
| --- | --- | --- |
| `rpc` (default) | RPC / archive nodes | No live pruning; keeps history |
| `validator` | Validators only | Live pruning; most RPC calls disabled |

This compose runs in **`rpc` mode** (default). Do not add `--mode validator` for an RPC node.

## Heal Watcher

The `ftm-watcher` service monitors logs for "dirty state" errors and automatically runs `sonictool heal` via `docker-compose-heal.yml`. On detection:

1. Stops the `ftm` container
2. Runs `ftm-heal` (heal command)
3. Restarts `ftm` after heal completes

Manual heal (if needed):

```bash
docker compose stop ftm
docker compose -f docker-compose-heal.yml run --rm ftm-heal
docker compose up -d ftm
```

## Host Ports

| Port | Protocol | Service |
| --- | --- | --- |
| 18545 | TCP | HTTP RPC |
| 18546 | TCP | WebSocket |
| 25010 | TCP+UDP | P2P |

All ports bind via `network_mode: host` — firewall P2P port for incoming peers.

Docs: [Fantom migration](https://docs.fantom.foundation/sonic-migration/overview) · [Fantom-foundation/Sonic](https://github.com/Fantom-foundation/Sonic)
