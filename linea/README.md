# Linea (Besu + Maru)

Mainnet node (Besu execution + Maru consensus). Chain data: `$HOME/besu-db`, `$HOME/linea-maru-db`.

Default compose file: `besu-compose.yml` (set `COMPOSE_FILE` in `.env` for Nethermind: `nether-compose.yml`).

## Start

```bash
./configure.sh
sudo chown -R 1000:1000 ~/besu-db    # first start only
docker compose up -d
```

Docs: [Run a Linea node](https://docs.linea.build/get-started/how-to/run-a-node) · [Consensys/linea-monorepo](https://github.com/Consensys/linea-monorepo)
