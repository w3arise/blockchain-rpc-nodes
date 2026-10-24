#!/usr/bin/env bash
#
# Merge enodes into an l2geth container's static-nodes.json and trusted-nodes.json.
# Input: a JSON array (export-peers.sh output) or one enode per line, from FILE,
# "-" / a pipe, or pasted into the console (end with Ctrl-D).
#
# Metis l2geth ignores admin.addPeer / admin.addTrustedPeer (no-op stubs), so the
# lists only take effect after a restart (--restart, or docker restart yourself).
# Existing entries are kept; a new enode replaces an old one with the same key.
#
# Usage: ./import-peers.sh [-c CONTAINER] [-d DATADIR] [--static-only] [--restart] [FILE|-]
#
set -euo pipefail

CONTAINER=metis-l2geth
DATADIR=""
STATIC_ONLY=0
RESTART=0
INPUT=""

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-0}"
}

while (($#)); do
  case "$1" in
    -c) CONTAINER="$2"; shift 2 ;;
    -d) DATADIR="$2"; shift 2 ;;
    --static-only) STATIC_ONLY=1; shift ;;
    --restart) RESTART=1; shift ;;
    -h|--help) usage 0 ;;
    -) INPUT="-"; shift ;;
    -*) echo "unknown argument: $1" >&2; usage 1 ;;
    *) INPUT="$1"; shift ;;
  esac
done

ENODE_RE='enode://[0-9a-fA-F]{128}@[^",[:space:]]+'

if [[ -n "${INPUT}" && "${INPUT}" != "-" ]]; then
  raw="$(cat "${INPUT}")"
else
  [[ -t 0 ]] && echo "Paste enodes (JSON array or one per line), then Ctrl-D:" >&2
  raw="$(cat)"
fi

new="$(grep -oE "${ENODE_RE}" <<< "${raw}" | sed 's/?.*//' || true)"
if [[ -z "${new}" ]]; then
  echo "ERROR: no enode:// entries found in input" >&2
  exit 1
fi

if [[ -z "${DATADIR}" ]]; then
  DATADIR="$(docker exec "${CONTAINER}" sh -c 'echo ${DATADIR:-/root/.ethereum}')"
fi
GETH_DIR="${DATADIR}/geth"

# Skip this node's own enode (best effort; needs the node running).
self_pub="$(docker exec "${CONTAINER}" geth attach "${DATADIR}/geth.ipc" --exec 'admin.nodeInfo.enode' 2>/dev/null \
  | grep -oE 'enode://[0-9a-fA-F]{128}' | cut -c9- || true)"
[[ -n "${self_pub}" ]] || echo "WARN: could not read own enode via IPC; not filtering self" >&2

existing="$(docker exec "${CONTAINER}" sh -c "cat '${GETH_DIR}/static-nodes.json' 2>/dev/null" \
  | grep -oE "${ENODE_RE}" || true)"

# New entries first so they win on duplicate keys; drop self; keep first per key.
merged="$(printf '%s\n%s\n' "${new}" "${existing}" | awk -v self="${self_pub}" '
  /^enode:\/\// {
    key = substr($0, 9, 128)
    if (key == self || seen[key]++) next
    print
  }')"

count_new="$(comm -13 <(sort -u <<< "${existing}") <(sort -u <<< "${merged}") | grep -c . || true)"
total="$(grep -c . <<< "${merged}" || true)"

json="$(awk 'BEGIN { print "[" } { lines[NR] = $0 } END {
  for (i = 1; i <= NR; i++) printf "\"%s\"%s\n", lines[i], (i < NR ? "," : "")
  print "]" }' <<< "${merged}")"

files=("${GETH_DIR}/static-nodes.json")
((STATIC_ONLY)) || files+=("${GETH_DIR}/trusted-nodes.json")
for f in "${files[@]}"; do
  docker exec -i "${CONTAINER}" sh -c "cat > '${f}'" <<< "${json}"
  echo "wrote ${f} (${total} enode(s), ${count_new} new or changed)" >&2
done

if ((RESTART)); then
  docker restart "${CONTAINER}" >/dev/null
  echo "restarted ${CONTAINER}" >&2
else
  echo "Lists load at startup. Apply with: docker restart ${CONTAINER}" >&2
fi
