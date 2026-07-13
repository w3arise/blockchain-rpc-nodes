# Linea (Besu + Maru)

```bash
./configure.sh
docker compose up -d
```

Besu data is stored at `$HOME/besu-db`. Before first start, set ownership for the mounted volume:

```bash
sudo chown -R 1000:1000 ~/besu-db
```

Maru data lives at `$HOME/linea-maru-db`.
