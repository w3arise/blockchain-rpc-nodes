# Kaia (ken)

Mainnet Endpoint Node (full, pruned). Chain data: `$HOME/kaia-data`.

## Start

```bash
mkdir -p "$HOME/kaia-data"
./configure.sh            # .env + EXT_IP (P2P NAT applied at container start)
docker compose up -d
```

RPC: `http://127.0.0.1:8551` · WS: `ws://127.0.0.1:8552`

## Snapshot

Official pruned chaindata (state migrated or live pruning). Pick a tarball from [packages.kaia.io/mainnet/chaindata/](https://packages.kaia.io/mainnet/chaindata/) or [pruning-chaindata/](https://packages.kaia.io/mainnet/pruning-chaindata/), then:

```bash
mkdir -p "$HOME/kaia-data"
# download and extract into $HOME/kaia-data (see Kaia docs for layout)
./configure.sh            # skip if .env and kend.conf already set
docker compose up -d
```

Skip genesis sync; the node catches up from the snapshot height.

## Host ports

When running a public replica, allow inbound P2P (TCP + UDP): `P2P_PORT` (default `32323`). RPC stays localhost-only by default (`RPC_BIND_ADDR=127.0.0.1`).

Docs: [Install Endpoint Nodes](https://docs.kaia.io/nodes/endpoint-node/install-endpoint-nodes/) · [Docker setup](https://docs.kaia.io/nodes/endpoint-node/docker-setup/) · [Chaindata snapshots](https://docs.kaia.io/misc/operation/chaindata-snapshot/) · [kaiachain/kaia](https://github.com/kaiachain/kaia)
