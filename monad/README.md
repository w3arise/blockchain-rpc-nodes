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

1. Raise the root file descriptor limit (the `monad` package's installer warns below 4096; 16384 gives headroom):

```bash
echo "root hard nofile 16384" >> /etc/security/limits.conf
echo "root soft nofile 16384" >> /etc/security/limits.conf
```

`/etc/security/limits.conf` is applied by PAM at **login** — there is no sysctl reload for it. Start a fresh root login session (`su - root`, or disconnect and SSH in again), then check `ulimit -n` is at least 4096 before `./install-package.sh`.

2. Clone this repo on the host and enter `monad/`.

3. Configure:

```bash
cp env.template .env
# set NODE_NAME (e.g. full_acme-1) and TRIEDB_DRIVE (verify with lsblk)
./configure.sh
```

4. Install the pinned APT package (`MONAD_VERSION` in `.env`, currently `0.15.1`):

```bash
./install-package.sh
```

5. Initialize TrieDB (destructive — erases the target):

```bash
./init-triedb.sh              # prompts for the device, defaults to TRIEDB_DRIVE
./init-triedb.sh /dev/nvme1n1p1   # or pass it directly
```

Accepts a whole device (relabelled GPT with one `triedb` partition) or an existing partition on that device (used as-is, rest of the disk untouched). Either way the result is published as `/dev/triedb` via udev and the choice is saved to `.env`.

6. Create keystores and sign the peer-discovery name record:

```bash
./generate-keystores.sh
# back up /opt/monad/backup/* off-host, together with KEYSTORE_PASSWORD from .env —
# the keystores cannot be decrypted without it
./sign-name-record.sh
```
7. Open firewall for P2P (if using UFW) and drop undersized UDP on the P2P port for spam hardening ([docs](https://docs.monad.xyz/node-ops/full-node-installation#configure-firewall-rules)):

```bash
ufw allow ssh
ufw allow 8000 comment 'monad consensus P2P'
ufw allow 8001 comment 'monad authenticated UDP'
ufw enable

# Drop undersized UDP on consensus P2P (spam hardening; see Monad full-node install docs)
iptables -I INPUT -p udp --dport 8000 -m length --length 0:1400 \
  -m comment --comment 'monad drop undersized UDP on P2P' -j DROP
```

The iptables rule is lost on reboot — persist it with `iptables-persistent` or your own mechanism.

8. Restore snapshot and start:

```bash
./restore-snapshot.sh
systemctl enable monad-bft monad-execution monad-rpc
systemctl start monad-bft monad-execution monad-rpc
```

9. Verify (RPC is active after statesync completes):

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

## Host ports and runtime

All long-running daemons run as the **`monad`** user via **systemd** on the host (from the `monad` APT package). This repo does not run Docker for the node itself.

### Ports

| Port | Protocol | Exposure | Service | Purpose |
| --- | --- | --- | --- | --- |
| 8080 | TCP | localhost by default (`127.0.0.1`) | `monad-rpc` | JSON-RPC (and WS where enabled). Bind is package/default; use a firewall or `systemctl edit monad-rpc` if you expose it beyond localhost. |
| 8000 | TCP + UDP | public (firewall) | `monad-bft` | Consensus P2P — peer discovery, raptorcast, blocksync. Must be reachable from the internet on a public full node. |
| 8001 | UDP | public (firewall) | `monad-bft` | Authenticated UDP for peer discovery (`authenticated_bind_address_port` in `node.toml`). |

Inbound **SSH** is separate (e.g. `ufw allow ssh`). Engine/internal IPC between `monad-bft`, `monad-execution`, and `monad-rpc` stays on the host and is not listed here.

### systemd services and timers (healthy full node)

After `./install-package.sh`, `./restore-snapshot.sh`, and `systemctl enable/start` in the Start steps, expect:

| Unit | Kind | Steady state | Role |
| --- | --- | --- | --- |
| `monad-bft.service` | service | **active (running)** | Consensus client; P2P, statesync/blocksync, coordinates with execution. |
| `monad-execution.service` | service | **active (running)** | Execution client; state on `/dev/triedb`. |
| `monad-rpc.service` | service | **active (running)** | RPC front-end (HTTP on 8080 by default). RPC may lag until statesync finishes after a snapshot. |
| `monad-cruft.timer` | timer | **active (waiting)** | Fires **hourly** (enabled by the `monad` package). |
| `monad-cruft.service` | oneshot | **inactive (dead)** between runs | Runs `/opt/monad/scripts/clear-old-artifacts.sh`; retention from `/home/monad/.env` (`RETENTION_*` set by `./configure.sh`). |

**Not running continuously** (normal):

| Unit | When it runs |
| --- | --- |
| `monad-mpt.service` | One-shot TrieDB format during `./init-triedb.sh`, or manual `monad-mpt --storage /dev/triedb --upgrade` during version upgrades. |

**Optional (upstream docs, not part of this repo’s Start steps):** `otelcol.service` — OpenTelemetry metrics on `:8889/metrics` if you install the collector per [full node installation](https://docs.monad.xyz/node-ops/full-node-installation#configure-otel-collector).

Quick check:

```bash
systemctl is-active monad-bft monad-execution monad-rpc
systemctl is-enabled monad-cruft.timer
systemctl list-timers --all | grep -i cruft
journalctl -u monad-bft -u monad-execution -u monad-rpc -n 30 --no-pager
```

Docs: [Full node installation](https://docs.monad.xyz/node-ops/full-node-installation) · [Hard reset](https://docs.monad.xyz/node-ops/node-recovery/hard-reset) · [General operations](https://docs.monad.xyz/node-ops/general-operations)
