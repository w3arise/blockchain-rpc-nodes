#!/usr/bin/env bash
#
# Offload closed Geth-family chain-freezer receipts.*.cdat and bodies.*.cdat
# files to another filesystem and replace them with symlinks. This does not
# prune history. Other freezer tables (headers, hashes, diffs, *.rdat, …)
# are left in place.
#
# Works for any client that uses the geth freezer layout (Bor, geth,
# op-geth, …). Run with the execution client STOPPED.
#
# Safe to re-run (idempotent): already-linked files are skipped; a partial
# dest copy is thrown away and redone; a regular source is never replaced
# with a symlink until dest cmp-matches source.
#
# Usage:
#   SRC=/path/to/chaindata/ancient/chain \
#   DEST=/other/partition/ancients \
#   ./scripts/offload-ancients.sh
#
# Optional:
#   MIN_MTIME=1735603200   # only files with mtime < this (unix); default = 2024-12-31 00:00:00 UTC
#   MIN_MTIME=             # empty = all closed receipts/bodies *.cdat files
#   DRY_RUN=1
#
set -euo pipefail

SRC="${SRC:?set SRC to ancient/chain (the freezer dir with receipts.*.cdat / bodies.*.cdat)}"
DEST="${DEST:?set DEST to the offload directory}"
MIN_MTIME="${MIN_MTIME-1735603200}"
DRY_RUN="${DRY_RUN:-0}"

abs() {
  local p="$1"
  (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$p")")
}

is_closed_segment() {
  # table.NNNN.ext — closed if a higher NNNN exists for the same table+ext.
  local f="$1" base table num ext
  base="$(basename "$f")"
  [[ "$base" =~ ^(.+)\.([0-9]+)\.(c|r)dat$ ]] || return 1
  table="${BASH_REMATCH[1]}"
  num=$((10#${BASH_REMATCH[2]}))
  ext="${BASH_REMATCH[3]}dat"
  local dir sibling higher=0
  dir="$(dirname "$f")"
  for sibling in "${dir}/${table}".*."${ext}"; do
    [[ -e "$sibling" ]] || continue
    local b n
    b="$(basename "$sibling")"
    [[ "$b" =~ \.([0-9]+)\.${ext}$ ]] || continue
    n=$((10#${BASH_REMATCH[1]}))
    if (( n > num )); then
      higher=1
      break
    fi
  done
  (( higher == 1 ))
}

already_linked() {
  local f="$1" dest="$2"
  [[ -L "$f" ]] || return 1
  local target
  target="$(readlink -f "$f" 2>/dev/null || true)"
  [[ -n "$target" && "$target" == "$(readlink -f "$dest" 2>/dev/null || true)" ]]
}

copy_verified() {
  local src="$1" dest="$2" partial="${2}.partial"
  if [[ -e "$dest" ]]; then
    if [[ -f "$src" && ! -L "$src" ]] && cmp -s "$src" "$dest"; then
      return 0
    fi
    # dest is leftover/truncated from a killed run
    rm -f "$dest"
  fi
  rm -f "$partial"
  cp -a "$src" "$partial"
  sync -f "$partial" 2>/dev/null || sync
  if ! cmp -s "$src" "$partial"; then
    echo "ERROR: copy mismatch ${src} -> ${partial}" >&2
    rm -f "$partial"
    return 1
  fi
  mv -T "$partial" "$dest"
}

swap_to_symlink() {
  local src="$1" dest="$2" tmp="${1}.offload-link"
  ln -s "$dest" "$tmp"
  mv -T "$tmp" "$src"
}

mkdir -p "$DEST"
SRC="$(abs "$SRC")"
DEST="$(abs "$DEST")"

if [[ "$SRC" == "$DEST" || "$SRC"/ == "$DEST"/* ]]; then
  echo "ERROR: DEST must not be SRC or inside SRC" >&2
  exit 1
fi

shopt -s nullglob
moved=0
skipped=0
linked=0

for f in "$SRC"/receipts.*.cdat "$SRC"/bodies.*.cdat; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  dest="$DEST/$base"

  if already_linked "$f" "$dest"; then
    skipped=$((skipped + 1))
    continue
  fi

  if [[ -L "$f" ]]; then
    echo "ERROR: ${f} is a symlink to unexpected target: $(readlink "$f")" >&2
    exit 1
  fi

  if [[ -n "$MIN_MTIME" ]] && [[ "$(stat -c %Y "$f")" -ge "$MIN_MTIME" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  if ! is_closed_segment "$f"; then
    echo "keep (head/open) $base"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "would offload $base"
    moved=$((moved + 1))
    continue
  fi

  copy_verified "$f" "$dest"
  swap_to_symlink "$f" "$dest"

  if ! already_linked "$f" "$dest" || [[ ! -r "$f" ]]; then
    echo "ERROR: swap failed or unreadable $base" >&2
    exit 1
  fi
  echo "linked $base"
  linked=$((linked + 1))
done

broken=0
for f in "$SRC"/receipts.*.cdat "$SRC"/bodies.*.cdat; do
  [[ -e "$f" || -L "$f" ]] || continue
  if [[ -L "$f" && ! -e "$f" ]]; then
    echo "broken: $f -> $(readlink "$f")" >&2
    broken=$((broken + 1))
  fi
done

echo "linked=${linked} skipped=${skipped} broken=${broken} dest=${DEST}"
[[ "$broken" -eq 0 ]]
