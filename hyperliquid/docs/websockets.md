# Hyperliquid WebSockets

`hl-node` does not serve WebSockets. For WebSocket access, run a sidecar that reads this node's output files. Setup steps are in [../README.md](../README.md).

## What `hl-node` serves

HTTP only, on container port `3001` (host `RPC_BIND_ADDR:HTTP_PORT`):

| Path | Flag | Protocol |
| --- | --- | --- |
| `/evm` | `--serve-eth-rpc` | HyperEVM JSON-RPC, `POST` only |
| `/info` | `--serve-info` | Info API subset that depends only on local state |

A WebSocket upgrade fails: `/ws` returns `404`, and `/evm` returns `405` with `allow: POST`. Upstream: "historical time series queries and websockets are not currently supported."

## Pick by use case

| Need | Sidecar | Serves | Reads from this node |
| --- | --- | --- | --- |
| HyperEVM `eth_subscribe` (`newHeads`, `logs`), receipt/log history, tracing | [nanoreth](https://github.com/hl-archive-node/nanoreth) (`reth-hl`) | `ws://` + HTTP JSON-RPC (reth flags) | `evm_block_and_receipts` output |
| HyperCore order book and trades (public API `/ws` format) | [order_book_server](https://github.com/hyperliquid-dex/order_book_server) | WebSocket on its own address and port | Node `--write-*` output and `/info` |

## HyperEVM: nanoreth

nanoreth is a reth-based HyperEVM archive node. It is what providers expose as a `/nanoreth` path next to `/evm`. Providers support WebSockets and tracing on `/nanoreth` only ([Chainstack](https://chainstack.com/hyperevm-evm-vs-nanoreth/)).

Block sources:

| Source | Flags | Notes |
| --- | --- | --- |
| This node's files | `--ingest-dir <dir> --local-ingest-dir <path>` | Point at `hl-node`'s `evm_block_and_receipts` (here: `$HOST_DATADIR/data/evm_block_and_receipts`) |
| S3 | `--s3` | Needs AWS credentials. Hyperliquid buckets are requester-pays |
| Another nanoreth | `--block-source=rpc://host:port` | Serving node runs `--enable-sync-server` |

Example (upstream README):

```bash
reth-hl node --http --http.addr 0.0.0.0 --http.api eth,ots,net,web3 \
  --ws --ws.addr 0.0.0.0 --ws.origins '*' --ws.api eth,ots,net,web3 \
  --ingest-dir ~/evm-blocks --local-ingest-dir <path> --ws.port 8545
```

Subscribe:

```json
{"jsonrpc":"2.0","id":1,"method":"eth_subscribe","params":["newHeads"]}
```

Before running it next to this node:

- The `pruner` deletes files under `data/` older than `PRUNE_RETENTION_HOURS` (default 48). nanoreth must ingest faster than that, or exclude `evm_block_and_receipts` from pruning.
- Upstream does not document hardware or disk needs, or `eth_sendRawTransaction` behavior. Check both before exposing it as an RPC endpoint. Repo rules require write RPC on every shipped endpoint.
- Keep binds on `RPC_BIND_ADDR`, not `0.0.0.0`, unless LAN access is intended.

## HyperCore: order_book_server

Serves the public API WebSocket format for `l2Book` (optional `n_levels` up to 100), `trades`, and `l4Book`:

```json
{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC"}}
```

```bash
cargo run --release --bin websocket_server -- --address 0.0.0.0 --port 8000
```

Node requirements: `--batch-by-block`, `--write-fills`, `--write-order-statuses`, `--write-raw-book-diffs`, `--serve-info`. Those output files add to the ~100 GB/day of logs the node already writes.

Caveats (upstream): not maintained by the core team ("as is", no commitment to fix), no spot order books, no untriggered trigger orders, and block batching adds a few milliseconds of latency.

## References

- [hyperliquid-dex/node README](https://github.com/hyperliquid-dex/node/blob/main/README.md): `--serve-eth-rpc`, `--serve-info`, info server limits
- [hl-archive-node/nanoreth](https://github.com/hl-archive-node/nanoreth)
- [hyperliquid-dex/order_book_server](https://github.com/hyperliquid-dex/order_book_server)
- [Chainstack: HyperEVM /evm vs /nanoreth](https://chainstack.com/hyperevm-evm-vs-nanoreth/)
- [Chainstack: Hyperliquid infrastructure FAQ](https://docs.chainstack.com/docs/hyperliquid-infrastructure-faq)
