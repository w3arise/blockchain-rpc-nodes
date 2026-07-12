# Berachain (bera-reth + beacon-kit)

## From scratch

```bash
cp env.template .env          # set EXT_IP
./init-database.sh
docker compose up -d
```

## From snapshot

```bash
cp env.template .env          # set EXT_IP
# restore snapshot into $HOME/berachain-beacond-data and $HOME/berachain-reth-data
./create-jwt.sh
./run-setup-initialisation.sh
docker compose up -d
```

Data lives under `$HOME/berachain-beacond-data` and `$HOME/berachain-reth-data`.
