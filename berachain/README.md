# Berachain (bera-reth + beacon-kit)

Mainnet node. Chain data: `$HOME/berachain-beacond-data`, `$HOME/berachain-reth-data`.

## Start

```bash
cp env.template .env    # set EXT_IP
./init-database.sh
docker compose up -d
```

## Snapshot

Restore snapshot data into `$HOME/berachain-beacond-data` and `$HOME/berachain-reth-data`, then skip `init-database.sh`:

```bash
cp env.template .env    # set EXT_IP
./create-jwt.sh
./run-setup-initialisation.sh
docker compose up -d
```

Docs: [Node quickstart](https://docs.berachain.com/validators/operations/quickstart) · [berachain/beacon-kit](https://github.com/berachain/beacon-kit) · [berachain/bera-reth](https://github.com/berachain/bera-reth)
