#!/usr/bin/env bash
#
# Refresh override_gossip_config.json. Root peers, in order:
#   1. RESERVED_PEER_IPS from .env (also written as reserved_peer_ips)
#   2. SEED_PEER_IPS (default: upstream hyperliquid-dex/node README root peer table)
#   3. gossipRootIps from the public info API
# Every candidate is kept only when TCP 4001 accepts a connection from this host.
#
# Usage: ./override-gossip.sh
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Mainnet root peers from https://github.com/hyperliquid-dex/node (README table).
DEFAULT_SEED_PEER_IPS="64.31.48.111,64.31.51.137,180.189.55.18,180.189.55.19,72.46.86.185,72.46.86.159,13.230.78.76,52.195.133.97,52.68.71.160,13.114.116.44,79.127.159.173,199.254.199.194,23.81.40.69,212.95.58.62,109.123.230.189,31.223.196.172,31.223.196.238,72.46.87.141,199.254.199.12,35.74.132.113,35.79.2.229,23.81.41.3,15.235.231.247,199.254.199.48,64.34.83.57"
SEED_PEER_IPS="${SEED_PEER_IPS:-$DEFAULT_SEED_PEER_IPS}"

CONNECT_TIMEOUT=2

split_csv() {
  printf '%s\n' "${1:-}" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed '/^$/d'
}

mapfile -t RESERVED < <(split_csv "${RESERVED_PEER_IPS:-}")
mapfile -t SEEDS < <(split_csv "${SEED_PEER_IPS}")
mapfile -t API < <(
  curl -sf -X POST --header "Content-Type: application/json" \
    --data '{ "type": "gossipRootIps" }' https://api.hyperliquid.xyz/info \
    | jq -r '.[]'
)
if ((${#API[@]} == 0)); then
  echo "WARN: gossipRootIps API returned no peers" >&2
fi

# Ordered, de-duplicated candidate list.
declare -A SEEN=()
CANDIDATES=()
for ip in "${RESERVED[@]}" "${SEEDS[@]}" "${API[@]}"; do
  [[ -n "${SEEN[$ip]:-}" ]] && continue
  SEEN[$ip]=1
  CANDIDATES+=("$ip")
done

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
for ip in "${CANDIDATES[@]}"; do
  (
    if timeout "${CONNECT_TIMEOUT}" bash -c ">/dev/tcp/${ip}/4001" 2>/dev/null; then
      : > "${TMP}/${ip}"
    fi
  ) &
done
wait

declare -A IS_RESERVED=()
for ip in "${RESERVED[@]}"; do IS_RESERVED[$ip]=1; done

ROOTS=()
REACHABLE_RESERVED=()
for ip in "${CANDIDATES[@]}"; do
  if [[ -f "${TMP}/${ip}" ]]; then
    ROOTS+=("$ip")
    [[ -n "${IS_RESERVED[$ip]:-}" ]] && REACHABLE_RESERVED+=("$ip")
  else
    echo "${ip}: TCP 4001 unreachable, skipped" >&2
  fi
done

if ((${#ROOTS[@]} == 0)); then
  echo "ERROR: no reachable peers; leaving override_gossip_config.json unchanged" >&2
  exit 1
fi

jq -n \
  --arg roots "$(IFS=,; printf '%s' "${ROOTS[*]}")" \
  --arg reserved "$(IFS=,; printf '%s' "${REACHABLE_RESERVED[*]:-}")" '
    def csv: split(",") | map(select(length > 0));
    {
      root_node_ips: ($roots | csv | map({"Ip": .})),
      try_new_peers: true,
      chain: "Mainnet",
      n_gossip_peers: 20,
      reserved_peer_ips: ($reserved | csv)
    }
  ' > override_gossip_config.json

echo "wrote override_gossip_config.json (${#ROOTS[@]} roots of ${#CANDIDATES[@]} candidates, ${#REACHABLE_RESERVED[@]} reserved)"
