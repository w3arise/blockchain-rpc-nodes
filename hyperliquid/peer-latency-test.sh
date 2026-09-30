#!/bin/bash

CONFIG="override_gossip_config.json"

IPS=$(jq -r '
  [.root_node_ips[].Ip, .reserved_peer_ips[]] | unique | .[]
' "$CONFIG")

echo "============================================"
echo " TCP handshake latency on port 4001"
echo "============================================"

TMPDIR=$(mktemp -d)

for IP in $IPS; do
  (
    RESULT=$(curl -s \
      --connect-timeout 1 \
      --max-time 1 \
      -o /dev/null \
      -w "%{time_connect}" \
      "http://$IP:4001" 2>/dev/null)

    MS=$(awk "BEGIN {printf \"%.2f\", $RESULT * 1000}")

    if [ "$RESULT" = "0.000000" ] || [ -z "$RESULT" ]; then
      echo "$IP UNREACHABLE" > "$TMPDIR/$IP"
    else
      echo "$IP $MS" > "$TMPDIR/$IP"
    fi
  ) &
done

wait

printf "%-20s %s\n" "IP" "TCP Handshake"
echo "--------------------------------------------"

cat "$TMPDIR"/* | sort -k2 -n -t' ' | while read IP LATENCY; do
  if [ "$LATENCY" = "UNREACHABLE" ]; then
    printf "%-20s %s\n" "$IP" "UNREACHABLE"
  else
    printf "%-20s %s ms\n" "$IP" "$LATENCY"
  fi
done

echo "============================================"
rm -rf "$TMPDIR"