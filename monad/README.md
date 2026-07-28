# Monad (monad-bft + monad-execution + monad-rpc)

Mainnet **public full node** on bare metal (systemd). Chain data: `/home/monad` on the host, TrieDB on a dedicated NVMe at `/dev/triedb`.

Official deployment is **not Docker** — run these steps on an Ubuntu 24.04+ bare-metal server as `root`.

## Requirements

- 16-core CPU @ 4.5 GHz+, 32 GB+ RAM, HT/SMT disabled in BIOS
- 2 TB dedicated NVMe for TrieDB + 500 GB for BFT/OS (PCIe Gen4 x4+)
- Linux kernel ≥ 6.8.0.60 (avoid 6.8.0.136)
- Inbound P2P: **8000** and **8001** (TCP + UDP on 8000)
- RPC: **8080** (localhost by default)

Cloud VMs are not officially supported. See [hardware requirements](https://docs.monad.xyz/node-ops/hardware-requirements).

## Start

1. Clone this repo on the host and enter `monad/`.

2. Configure:

```bash
cp env.template .env
# set NODE_NAME (e.g. full_acme-1) and TRIEDB_DRIVE (verify with lsblk)
./configure.sh
```

3. Install the pinned APT package (`MONAD_VERSION` in `.env`, currently `0.15.1`):

```bash
./install-package.sh
```

4. Initialize TrieDB (destructive — erases the target):

```bash
./init-triedb.sh              # prompts for the device, defaults to TRIEDB_DRIVE
./init-triedb.sh /dev/nvme1n1p1   # or pass it directly
```

Accepts a whole device (relabelled GPT with one `triedb` partition) or an existing partition on that device (used as-is, rest of the disk untouched). Either way the result is published as `/dev/triedb` via udev and the choice is saved to `.env`.

5. Create keystores and sign the peer-discovery name record:

```bash
./generate-keystores.sh
# back up /opt/monad/backup/* off-host, together with KEYSTORE_PASSWORD from .env —
# the keystores cannot be decrypted without it
./sign-name-record.sh
```
6. Open firewall for P2P (if using UFW) and drop undersized UDP on the P2P port for spam hardening ([docs](https://docs.monad.xyz/node-ops/full-node-installation#configure-firewall-rules)):

```bash
ufw allow ssh
ufw allow 8000
ufw allow 8001
ufw enable

iptables -I INPUT -p udp --dport 8000 -m length --length 0:1400 -j DROP
```

The iptables rule is lost on reboot — persist it with `iptables-persistent` or your own mechanism.

7. Restore snapshot and start:

```bash
./restore-snapshot.sh
systemctl enable monad-bft monad-execution monad-rpc
systemctl start monad-bft monad-execution monad-rpc
```

8. Verify (RPC is active after statesync completes):

```bash
curl -s http://127.0.0.1:8080/ -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

RPC: `http://127.0.0.1:8080` · Chain ID **143**

## Snapshot

Fast path is hard reset + official MF snapshot (requires `aria2`):

```bash
./restore-snapshot.sh
systemctl start monad-bft monad-execution monad-rpc
```

Alternative provider: [Category Labs R2 scripts](https://pub-b0d0d7272c994851b4c8af22a766f571.r2.dev). Mainnet TrieDB restore typically takes 1–5 minutes, then statesync/blocksync catch-up.

Re-run `./configure.sh` after a public IP change, then `./sign-name-record.sh` (it re-signs at the next `self_record_seq_num` so peers accept the new address) and restart `monad-bft`.

## Upgrade

`install-package.sh` installs exactly `MONAD_VERSION` and `apt-mark hold`s the package, so `apt upgrade` cannot move it. Upgrade only after the official announcement, and read that release's [upgrade instructions](https://docs.monad.xyz/node-ops/upgrade-instructions) first — some releases change `node.toml` or RPC behaviour.

```bash
systemctl stop monad-bft monad-execution monad-rpc
# set MONAD_VERSION=<new version> in .env
./install-package.sh
monad-mpt --storage /dev/triedb --upgrade   # one-time DB migration, existing datadir only
systemctl start monad-bft monad-execution monad-rpc
monad-rpc -V
```

The migration is required on an existing TrieDB when coming from `0.14.5` or earlier; fresh installs and nodes already on `0.15.0`+ skip it. Skipping it is not destructive — the services abort at startup with an "upgrade needed" log until it runs.

## State retention

Synced full nodes retain limited execution history in TrieDB (not a full archive). Historical RPC requires external archive backends — see [Archive Data Setup](https://docs.monad.xyz/node-ops/archive-data).

For RPC workflows, enable `--trace_calls` on `monad-execution` via `systemctl edit monad-execution` (merge with the package `ExecStart` flags).

## Host ports

| Port | Exposure | Role |
| --- | --- | --- |
| 8080 | localhost (default) | JSON-RPC |
| 8000 | public (TCP + UDP) | Consensus P2P |
| 8001 | public | Authenticated UDP |

Docs: [Full node installation](https://docs.monad.xyz/node-ops/full-node-installation) · [Hard reset](https://docs.monad.xyz/node-ops/node-recovery/hard-reset)
