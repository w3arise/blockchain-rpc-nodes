# Gravity (gravity_node)

Mainnet L1 public full node. Chain ID `127001`. Execution is gravity-reth (Grevm) inside `gravity_node`, with AptosBFT consensus. Chain data: `$HOME/gravity-data`. Logs: `$HOME/gravity-logs`.

## Start

```bash
./configure.sh
./restore-snapshot.sh
sudo chown -R 10001:10001 "$HOME/gravity-data" "$HOME/gravity-logs" config
sudo chmod 600 config/identity.yaml
docker compose up -d
```

`./configure.sh` writes `.env`, fetches genesis and waypoint for the pinned SDK tag, generates `config/identity.yaml`, and renders the node config. The container image runs as uid **10001**.

RPC: `http://127.0.0.1:12745` (HTTP), `ws://127.0.0.1:12746` (WS).

## State retention

`NODE_TYPE=archive` keeps receipts and logs. State history is bounded the same way as Celo:

- `--prune.account-history.distance 10064`
- `--prune.storage-history.distance 10064`

At Gravity's ~250 ms blocks, 10064 blocks is about 42 minutes of account and storage history. Receipts, logs, and transaction lookup stay. `--full` is a different profile: it also prunes receipts to that window. Switching a live datadir to `--full` prunes that history on the next start.

## Snapshot

`./restore-snapshot.sh` downloads the public PFN cut (~105 GiB uncompressed tar):

`https://gravity-snapshots.b-cdn.net/gravity-mainnet-data/latest.tar`

The archive stays under `$HOME/gravity-snapshot-tmp` (override with `SNAPSHOT_TMPDIR`, on the same volume as the datadir). It extracts `consensus_db/`, `quorumstoreDB/`, and `reth/` into `$HOME/gravity-data/data`. Skip the script only when that datadir is already populated. Docs do not label the cut archive or `--full`. Archive mode will not restore receipts that the snapshot already pruned.

## Host ports

Compose publishes ports on a bridge network. `./configure.sh` sets `EXT_IP`, and gravity-reth advertises it with `--nat=extip`. Allow inbound P2P: `PUBLIC_PORT` (consensus, TCP, default `26180`) and `RETH_P2P_PORT` (execution listen and discovery v4/v5, TCP + UDP, default `12724`). RPC stays on localhost (`RPC_BIND_ADDR=127.0.0.1`, host `HTTP_PORT` `12745`).

## Upgrade

Stop the node, copy `GRAVITY_IMAGE` and `GRAVITY_SDK_REF` from `env.template` into `.env`, re-run `./configure.sh` if the genesis tag changed, `docker compose pull`, then `docker compose up -d`. Check the local head against `https://mainnet-rpc.gravity.xyz`.

Hardfork times are compiled into the binary. See [Gravity Mainnet Hardforks](https://docs.gravity.xyz/gravity-networks/mainnet-hardforks).

Docs: [Gravity Mainnet](https://docs.gravity.xyz/gravity-networks/l1-mainnet) · [PFN with Docker](https://docs.gravity.xyz/gravity-networks/run-a-mainnet-pfn-with-docker) · [Galxe/gravity-sdk](https://github.com/Galxe/gravity-sdk) · [Galxe/gravity-reth](https://github.com/Galxe/gravity-reth)
