# Linea (Besu + Maru)

Mainnet node (Linea Besu package + Maru consensus). Chain data: `$HOME/besu-db`, `$HOME/linea-maru-db`.

Two compose files — pick one execution client:

- **Besu** (default): `besu-compose.yml` — `docker compose up -d`
- **Nethermind**: set `COMPOSE_FILE=nether-compose.yml` in `.env` (Linea-recommended `1.32.4`)

Besu uses the image profile `--profile=advanced-mainnet` (`linea_estimateGas` / `LINEA` APIs). Operator ports, P2P, JWT, gas cap, and Bonsai history are compose CLI overrides. Do not remount a local Besu toml.

## Start

```bash
./configure.sh
sudo chown -R 1000:1000 ~/besu-db    # first start only
docker compose up -d
```

Existing node: copy only `BESU_IMAGE`, `MARU_IMAGE`, `NETHERMIND_VERSION`, and `GAS_CAP` from `env.template` into `.env`, then `docker compose up -d`. Do not recopy the whole template.

## Snapshot

No official snapshot. Sync from P2P / genesis.

## Pruning Mode

Bonsai + `SNAP`. `--bonsai-historical-block-limit` bounds **state** (default `5000` blocks). Receipts/logs stay available for RPC. Linea’s advanced profile keeps parallel tx processing **off**.

## Host ports

Besu+Maru use host networking. JSON-RPC `HTTP_PORT` / `WS_PORT` (defaults `38545` / `38546`). P2P `P2P_PORT` (`31303`, TCP+UDP). Engine API `8550` on localhost. Maru P2P `9000` TCP+UDP.

Docs: [Run a Linea node](https://docs.linea.build/network/how-to/run-a-node) · [Linea Besu](https://docs.linea.build/network/how-to/run-a-node/linea-besu) · [getting-started compose](https://github.com/Consensys/linea-monorepo/blob/main/docs/getting-started/linea-mainnet/docker-compose.yml)
