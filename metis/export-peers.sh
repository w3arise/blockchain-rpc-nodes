#!/usr/bin/env bash
#
# Print a running l2geth's peers (via IPC) as a JSON array of enodes, for
# import-peers.sh on another node. Includes this node's own enode by default.
#
# Inbound peers are skipped unless --inbound: their enode carries the remote's
# ephemeral source port, not its listen port, so it is usually not dialable.
#
# Usage: ./export-peers.sh [-c CONTAINER] [-i IPC_PATH] [--no-self] [--inbound] > peers.json
#
set -euo pipefail

CONTAINER=metis-l2geth
IPC=""
WITH_SELF=1
WITH_INBOUND=0

usage() {
  sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-0}"
}

while (($#)); do
  case "$1" in
    -c) CONTAINER="$2"; shift 2 ;;
    -i) IPC="$2"; shift 2 ;;
    --no-self) WITH_SELF=0; shift ;;
    --inbound) WITH_INBOUND=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "${IPC}" ]]; then
  IPC="$(docker exec "${CONTAINER}" sh -c 'echo ${DATADIR:-/root/.ethereum}/geth.ipc')"
fi

# One line per node: "S <enode>" (self), "O <enode>" (outbound), "I <enode>" (inbound).
lines="$(docker exec "${CONTAINER}" geth attach "${IPC}" --exec \
  '["S " + admin.nodeInfo.enode].concat(admin.peers.map(function(p){return (p.network.inbound ? "I " : "O ") + p.enode})).join("\n")' \
  | tr -d '"' | sed 's/\\n/\n/g')"

enodes=()
while read -r kind enode; do
  [[ "${enode}" == enode://* ]] || continue
  enode="${enode%%\?*}" # drop ?discport=… suffix
  case "${kind}" in
    S)
      ((WITH_SELF)) || continue
      host="${enode#*@}"; host="${host%:*}"
      if [[ "${host}" =~ ^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
        echo "WARN: own enode advertises private IP ${host} (--nat any?); replace it with the public IP before importing" >&2
      fi
      ;;
    I)
      if ((!WITH_INBOUND)); then
        echo "skipped inbound peer ${enode#*@} (source port, not listen port)" >&2
        continue
      fi
      ;;
  esac
  enodes+=("${enode}")
done <<< "${lines}"

{
  echo "["
  for i in "${!enodes[@]}"; do
    sep=","; ((i == ${#enodes[@]} - 1)) && sep=""
    printf '"%s"%s\n' "${enodes[$i]}" "${sep}"
  done
  echo "]"
}
echo "exported ${#enodes[@]} enode(s) from ${CONTAINER}" >&2
