# AB Core (abcore geth)

Mainnet full RPC node (PoA / Clique). Chain data: `$HOME/ab-data`.

## Start

```bash
./configure.sh
docker compose build
./init-database.sh
docker compose up -d
```

## Snapshot

No official chaindata snapshot is documented. Sync from genesis via P2P after `init-database.sh`.

## State retention

Full node with `--history.state=90000` (~75 hours at 3s blocks), matching [ab-deploy](https://github.com/ABFoundationGlobal/ab-deploy) defaults. This is not an archive node.

## Testnet

```bash
./init-database.sh testnet
```

Set `NETWORK_ID=26888`, `MAX_PEERS=50`, and testnet bootnodes from `ab-deploy` `abcore/testnet/conf/node.toml` in `.env` before starting.

Docs: [AB Core technical info](https://docs.ab.org/docs/) · [Node deployment](https://github.com/ABFoundationGlobal/ab-deploy)

## Port already in use (33333)

The compose file is fine — this is usually Docker still holding the publish, not a missing `netstat` line.

```bash
docker ps -a --filter name=ab
sudo ss -tlnp 'sport = :33333'
sudo ss -ulnp 'sport = :33333'
docker rm -f ab-node
docker compose down --remove-orphans
docker compose up -d
```

`netstat -tpln` is TCP-only; P2P also binds UDP 33333. Use `ss` with sudo to see `docker-proxy`.

