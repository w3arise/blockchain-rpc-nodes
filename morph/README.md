# Morph (morph-geth + morph-node)

Mainnet MPT full/archive node. Chain data: `$HOME/morph-geth-data`, `$HOME/morph-node-data`.

## Start

```bash
./configure.sh
# edit .env — set L1_ETH_RPC
./init-database.sh
./create-jwt.sh
docker compose up -d
```

## Snapshot

Download and extract a snapshot from [snapshot.morphl2.io](https://snapshot.morphl2.io/) (see [run-morph-node README](https://github.com/morph-l2/run-morph-node#snapshot-information)). Latest mainnet archive: `snapshot-archive-20260701-1`.

```bash
wget -O /tmp/morph-snapshot.tar.gz \
  https://snapshot.morphl2.io/mainnet/snapshot-archive-20260701-1.tar.gz
tar -xzf /tmp/morph-snapshot.tar.gz -C /tmp
mv /tmp/snapshot-archive-20260701-1/geth $HOME/morph-geth-data/
mkdir -p $HOME/morph-node-data/data
mv /tmp/snapshot-archive-20260701-1/data/* $HOME/morph-node-data/data/
./init-database.sh    # stages config/ into $HOME/morph-node-data/config
./create-jwt.sh
docker compose up -d
```

Set `L1_MSG_START_HEIGHT` in `.env` to match the snapshot table in the official README.

## Testnet

```bash
./configure.sh hoodi
# edit .env — set L1_ETH_RPC (Ethereum Hoodi)
./init-database.sh hoodi
./create-jwt.sh
docker compose up -d
```

Uses separate datadirs (`$HOME/morph-hoodi-geth-data`, `$HOME/morph-hoodi-node-data`) so mainnet data is untouched.

## Verify

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8441

curl -s http://127.0.0.1:12657/status | jq '.result.sync_info.catching_up'
```

Docs: [run-morph-node](https://github.com/morph-l2/run-morph-node) · [Run full node (Docker)](https://docs.morph.network/docs/build-on-morph/developer-resources/node-operation/full-node/run-in-docker)
