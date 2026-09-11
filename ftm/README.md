# Fantom Opera (sonicd / legacy)

Mainnet full node running Sonic client on the legacy Fantom Opera chain. Chain data: `$HOME/.sonic`.

This setup uses `network_mode: host` — the node binds directly to host interfaces.

## Start

```bash
cd ftm
cp env.template .env
# Edit .env: set EXT_IP (public IP for P2P)
docker compose build
docker compose up -d
```

## Pruning Mode

The node runs in RPC mode (`--mode=rpc`) which keeps full block/receipt/log history. State is not pruned by default.

## Heal watcher

A sidecar (`ftm-watcher`) monitors the node logs for `dirty state` errors. When detected, it triggers `ftm-heal.sh` to run the built-in `--healdb all` repair. This is a known Fantom/Sonic recovery pattern.

## Host ports

| Port | Protocol | Role |
| --- | --- | --- |
| `HTTP_PORT` (18545) | TCP | JSON-RPC HTTP |
| `WS_PORT` (18546) | TCP | JSON-RPC WebSocket |
| `P2P_PORT` (25010) | TCP+UDP | P2P |

RPC binds to `HTTP_ADDR` / `WS_ADDR` (default `0.0.0.0` — use a firewall).

## Official docs

- [Fantom migration](https://docs.fantom.foundation/sonic-migration/overview)
- [0xsoniclabs/sonic](https://github.com/0xsoniclabs/sonic)
- [Fantom-foundation/go-opera](https://github.com/Fantom-foundation/go-opera)
