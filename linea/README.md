# Linea (Besu + Maru)

Mainnet node (Besu execution + Maru consensus). Chain data: `$HOME/besu-db`, `$HOME/linea-maru-db`.

Two compose files — pick one execution client:

- **Besu** (default): `besu-compose.yml` — `docker compose up -d`
- **Nethermind**: set `COMPOSE_FILE=nether-compose.yml` in `.env`

## Start

```bash
./configure.sh
sudo chown -R 1000:1000 ~/besu-db    # first start only
docker compose up -d
```

Docs: [Run a Linea node](https://docs.linea.build/get-started/how-to/run-a-node) · [Consensys/linea-monorepo](https://github.com/Consensys/linea-monorepo)
