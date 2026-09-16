# Stellar (stellar-rpc)

Mainnet Stellar RPC node (Soroban smart contracts + general Stellar transactions). Chain data: `$HOME/stellar-data`.

This is **not** an EVM JSON-RPC endpoint. Queries use Stellar RPC methods (`getEvents`, `getLedgerEntries`, `simulateTransaction`, …) and writes use `sendTransaction` with signed Stellar **XDR** envelopes.

## Start

```bash
./configure.sh
docker compose up -d
```

First start runs captive **stellar-core** catchup from public history archives; allow time and disk (~350 GiB at default retention).

JSON-RPC: `http://127.0.0.1:8000` · Admin: `http://127.0.0.1:6061`

```bash
curl -s http://127.0.0.1:8000 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth","params":{}}'
```

Pin the image with `STELLAR_RPC_IMAGE` in `.env` (see [releases](https://github.com/stellar/stellar-rpc/releases)). Re-run `./configure.sh` after editing retention or network vars.

## Snapshot

No chaindata tarball. Sync uses configured **history archives** (pubnet/testnet presets via `STELLAR_NETWORK`). Captive Core state and the RPC SQLite DB live under `HOST_DATADIR`.

## State retention

Default `HISTORY_RETENTION_WINDOW=120960` ledgers (~7 days). RPC serves `getEvents`, `getTransactions`, and `getLedgers` only within that window. Longer history requires Horizon, Hubble, or a custom indexer — out of scope for this minimal RPC setup.

Each extra retention day adds roughly 40 GiB disk per SDF guidance. Keep retention at or below 7 days unless you accept the storage cost.

## Testnet

Set `STELLAR_NETWORK=testnet` in `.env`, re-run `./configure.sh`, wipe or use a separate `HOST_DATADIR`, then `docker compose up -d`.

## Host ports

| Port (default) | Bind | Role |
| --- | --- | --- |
| 8000 | `RPC_BIND_ADDR` (127.0.0.1) | Stellar JSON-RPC |
| 6061 | `RPC_BIND_ADDR` | Admin / metrics |

No public P2P port — captive Core syncs from history archives, not as a network validator.

Docs: [Stellar RPC admin guide](https://developers.stellar.org/docs/data/apis/rpc/admin-guide/running) · [RPC methods](https://developers.stellar.org/docs/data/apis/rpc/api-reference/methods/overview)
