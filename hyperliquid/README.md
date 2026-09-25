# Hyperliquid (hl-visor)

Mainnet non-validator. Serves HyperEVM JSON-RPC (`/evm`) and the local info API (`/info`). Chain data: `$HOME/hyperliquid-data` (override with `HOST_DATADIR`). Non-validator size: 16 vCPU, 128 GB RAM, 500 GB SSD.

## Start

```bash
./configure.sh
docker compose build
sudo chown -R 10000:10000 "$HOME/hyperliquid-data"   # first start only (container UID)
docker compose up -d
```

Entrypoint: `hl-visor run-non-validator --replica-cmds-style recent-actions`. Compose adds `--serve-eth-rpc` and `--serve-info`. Extra `--write-*` flags go on the `node` service `command:` list in `docker-compose.yml`.

`./configure.sh` writes the host public IP to `$HOST_DATADIR/override_public_ip_address`. hl-visor advertises that address. Re-run `./configure.sh` after the public IP changes.

Refresh gossip roots (overwrites `override_gossip_config.json`). Reserved peers from `RESERVED_PEER_IPS` are included only when TCP 4001 accepts a connection:

```bash
./override-gossip.sh
docker compose up -d --force-recreate node
```

## Snapshot

There is no official chaindata tarball. The node streams from peers after visor starts. Logs such as `applied block X` mean it is streaming live data.

## Pruning Mode

`--replica-cmds-style recent-actions` keeps the two latest replica-command height files. The `pruner` service deletes files under the data directory older than `PRUNE_RETENTION_HOURS` (default **48**). It skips `visor_child_stderr`. Default node output is about **100 GB of logs per day**.

HyperEVM `/evm` serves this node's local EVM state. Upstream does not ship a genesis receipt and log archive. The local info server answers requests that are a function of local state. Historical time series and websockets are unsupported. Longer HyperCore history is the `--write-*` output, when those files are kept.

hl-visor has no RPC gas-cap flag. Block gas limits are the chain's small-block and large-block caps.

HyperEVM transaction submission is `eth_sendRawTransaction` on `/evm`. HyperCore orders use the exchange API.

## Testnet

The Dockerfile and `visor.json` in the image target **Mainnet** (`HL_VISOR_URL` in `env.template`). Testnet uses `https://binaries.hyperliquid-testnet.xyz/Testnet/hl-visor` and `{"chain": "Testnet"}` in `visor.json`. Change those, rebuild, and set gossip config `chain` to `Testnet`.

## Host ports

Ubuntu 24.04 is the supported OS.

| Port | Role |
| --- | --- |
| `HTTP_PORT` (default **3001**) | Host port for `/evm` and `/info`. Bind is `RPC_BIND_ADDR` (default `127.0.0.1`). Container listen port is **3001**. |
| **4001**, **4002** (TCP) | Gossip. Published on all interfaces. Must be reachable from the internet, or peers deprioritize this node. |

`n_gossip_peers` in `override_gossip_config.json` is **20** (allowed range 8–100). That change does not require a restart.

For lowest latency, run in Tokyo.

Latest block:

```bash
curl -X POST --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' http://127.0.0.1:3001/evm
```

Info requests go to `http://127.0.0.1:3001/info` ([info endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)). Ping `exchangeStatus` and ignore the response when the L1 timestamp is stale.

Crash logs: `$HOST_DATADIR/data/visor_child_stderr/{date}/{node_binary_index}`.

Docs: [Run a node](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/nodes) · [hyperliquid-dex/node](https://github.com/hyperliquid-dex/node)
