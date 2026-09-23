#!/usr/bin/env bash
#
# Refresh override_gossip_config.json from the public gossipRootIps API.
# RESERVED_PEER_IPS in .env is prepended to root_node_ips and set as
# reserved_peer_ips, but only when TCP 4001 accepts a connection.
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

CONNECT_TIMEOUT=2

mapfile -t CANDIDATES < <(
  printf '%s\n' "${RESERVED_PEER_IPS:-}" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed '/^$/d'
)

REACHABLE=()
if ((${#CANDIDATES[@]})); then
  TMP="$(mktemp -d)"
  pids=()
  for ip in "${CANDIDATES[@]}"; do
    (
      if timeout "${CONNECT_TIMEOUT}" bash -c ">/dev/tcp/${ip}/4001" 2>/dev/null; then
        printf '%s\n' "$ip" > "${TMP}/${ip}"
      fi
    ) &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
  for ip in "${CANDIDATES[@]}"; do
    if [[ -f "${TMP}/${ip}" ]]; then
      REACHABLE+=("$ip")
      echo "reserved ${ip}: TCP 4001 open"
    else
      echo "reserved ${ip}: TCP 4001 unreachable, skipped" >&2
    fi
  done
  rm -rf "${TMP}"
fi

REACHABLE_CSV=""
if ((${#REACHABLE[@]})); then
  REACHABLE_CSV=$(IFS=,; printf '%s' "${REACHABLE[*]}")
fi

curl -sf -X POST --header "Content-Type: application/json" \
  --data '{ "type": "gossipRootIps" }' https://api.hyperliquid.xyz/info \
  | jq -c --arg peers "$REACHABLE_CSV" '
      ($peers | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $static
      | {
          root_node_ips: (($static | map({"Ip": .})) + [(.[] | {"Ip": .})]),
          try_new_peers: false,
          chain: "Mainnet",
          reserved_peer_ips: $static
        }
    ' \
  > override_gossip_config.json

echo "wrote override_gossip_config.json ($(jq '.root_node_ips | length' override_gossip_config.json) roots, $(jq '.reserved_peer_ips | length' override_gossip_config.json) reserved)"
