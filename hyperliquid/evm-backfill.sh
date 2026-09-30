#!/usr/bin/env bash
#
# Find and backfill HyperEVM blocks missing from hl-node's RPC DB, using the official
# S3 block archive (s3://hl-mainnet-evm-blocks) and sprites0/block-importer.
# Procedure and background: ../docs/hyperliquid-evm-backfill.md
#
# Usage: ./evm-backfill.sh setup                      clone + build the importer and the compare tool
#        ./evm-backfill.sh scan     START END [STEP]  list missing ranges (STEP>1: sample, bisect edges)
#        ./evm-backfill.sh download START END         fetch START-1..END+1 from S3, check every file
#        ./evm-backfill.sh import   START END         node stopped: backup, format check, import
#        ./evm-backfill.sh verify   START END         after restart: every block in the range is served
#        ./evm-backfill.sh run      START END         download, stop, import, start, verify
#        ./evm-backfill.sh restore  BACKUP_DIR        node stopped: put a backup back in place
#
# Reads HOST_DATADIR, HTTP_PORT and RPC_BIND_ADDR from .env. Other settings below can be
# overridden with environment variables.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

BIND="${RPC_BIND_ADDR:-127.0.0.1}"
[[ "${BIND}" == "0.0.0.0" ]] && BIND=127.0.0.1

HL_DATA="${HL_DATA:-${HOST_DATADIR:-${HOME}/hyperliquid-data}}"   # --db-dir (contains hyperliquid_data/)
RPC="${RPC:-http://${BIND}:${HTTP_PORT:-3001}/evm}"
BLOCKS_DIR="${BLOCKS_DIR:-${HOME}/evm-blocks}"                  # stable: re-runs reuse downloads
IMPORTER_DIR="${IMPORTER_DIR:-${HOME}/hl-importer-upstream}"
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}}"
COMPOSE_DIR="${COMPOSE_DIR:-${SCRIPT_DIR}}"
S3_BUCKET="${S3_BUCKET:-s3://hl-mainnet-evm-blocks}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"                      # bucket region; requester pays
PARALLEL="${PARALLEL:-16}"
WAIT_MAX="${WAIT_MAX:-1800}"                                    # seconds `run` waits for the RPC

DB="$HL_DATA/hyperliquid_data/db_hub/Rpc"
IMPORTER="$IMPORTER_DIR/target/release/block-importer"
UPSTREAM=https://github.com/sprites0/block-importer

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "'$1' not found in PATH"; }
confirm() { read -r -p "$1 [y/N] " a; [[ $a == [yY] ]] || die "aborted"; }

# Set while hl is stopped for import/restore. On a failed exit, remind the operator; never
# restart automatically (the DB may need a restore first).
NODE_STOPPED=0
on_exit() {
  local rc=$?
  (( rc != 0 && NODE_STOPPED == 1 )) || return 0
  printf '\n\033[33mhl-node is still STOPPED. Check the error above, then start it yourself:\033[0m\n' >&2
  printf '  cd %s && docker compose start\n' "$COMPOSE_DIR" >&2
}
trap on_exit EXIT

# S3 layout: block h lives in {(h-1)/1e6*1e6}/{(h-1)/1e3*1e3}/{h}.rmp.lz4
block_file() { local h=$1; echo "$BLOCKS_DIR/$(( (h-1)/1000000*1000000 ))/$(( (h-1)/1000*1000 ))/$h.rmp.lz4"; }

# Exact process names, so shells/editors whose command line merely mentions hl-node don't match.
hl_running() { pgrep -x hl-visor >/dev/null || pgrep -x hl-node >/dev/null; }

rpc() { curl -s -m 20 -H 'content-type: application/json' -d "$1" "$RPC"; }
rpc_head() {
  local h; h=$(rpc '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
    | sed -n 's/.*"result" *: *"\(0x[0-9a-fA-F]*\)".*/\1/p')
  [[ -n $h ]] && echo $((h))
}
block_ok() {
  rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf 0x%x "$1")\",false]}" \
    | grep -q '"number"'
}
export -f rpc block_ok; export RPC

build_env() {
  [[ -f $HOME/.cargo/env ]] && . "$HOME/.cargo/env"
  : "${LIBCLANG_PATH:=$(dirname "$(ls /usr/lib/llvm-*/lib/libclang.so* /usr/lib/*-linux-gnu/libclang*.so* 2>/dev/null | head -1)")}"
  : "${BINDGEN_EXTRA_CLANG_ARGS:=-I$(dirname "$(find /usr/lib/gcc -name stddef.h 2>/dev/null | head -1)")}"
  export LIBCLANG_PATH BINDGEN_EXTRA_CLANG_ARGS
}

# ---------------------------------------------------------------------------- setup
COMPARE_RS='// Compares one block stored in hl-node'"'"'s RPC DB with the S3 file for the same block.
// Usage: compare <db-dir> <s3-file.rmp.lz4> <block>   (opens the DB read-only)
use std::io::Read;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (db_dir, file, block): (&str, &str, u64) = (&a[1], &a[2], a[3].parse().unwrap());
    let db = rocksdb::DB::open_for_read_only(
        &rocksdb::Options::default(),
        format!("{db_dir}/hyperliquid_data/db_hub/Rpc"),
        false,
    )
    .expect("open DB read-only");
    let key = [b"Eb".as_slice(), &block.to_be_bytes()].concat();
    let stored = db.get(&key).unwrap().expect("block not in DB");

    let mut s3 = Vec::new();
    lz4_flex::frame::FrameDecoder::new(std::fs::File::open(file).unwrap())
        .read_to_end(&mut s3)
        .unwrap();
    // The importer stores the file minus its first byte (the 1-element array marker).
    let s3 = &s3[1..];

    println!("DB: {} bytes, S3: {} bytes", stored.len(), s3.len());
    if stored == s3 {
        println!("FORMAT MATCHES");
    } else {
        let at = stored.iter().zip(s3).position(|(x, y)| x != y).unwrap_or(stored.len().min(s3.len()));
        println!("DIFFERENT (first difference at byte {at})");
    }
}'

cmd_setup() {
  need git; build_env; need cargo
  if [[ ! -d $IMPORTER_DIR/.git ]]; then
    say "Cloning $UPSTREAM into $IMPORTER_DIR"
    git clone -q "$UPSTREAM" "$IMPORTER_DIR"
  fi
  mkdir -p "$IMPORTER_DIR/examples"
  printf '%s\n' "$COMPARE_RS" > "$IMPORTER_DIR/examples/compare.rs"
  say "Building importer and compare tool (first build compiles RocksDB: 5-15 min)"
  (cd "$IMPORTER_DIR" && cargo build -q --release --locked --target-dir target \
     && cargo build -q --release --locked --target-dir target --example compare)
  ls -l "$IMPORTER" "$IMPORTER_DIR/target/release/examples/compare"
}

# ----------------------------------------------------------------------------- scan
# Prints "MISSING a-b (n blocks)" for every gap. With STEP>1 only every STEP-th block is
# probed and each OK/FAIL edge is bisected to the exact block, so gaps shorter than STEP
# can be missed.
status() { block_ok "$1" && echo 1 || echo 0; }

cmd_scan() {
  local start=$1 end=$2 step=${3:-1} head
  head=$(rpc_head) || true
  [[ -n $head ]] || die "RPC $RPC is not answering"
  (( end > head )) && { echo "capping END at the node head $head"; end=$head; }
  say "Scanning $start..$end on $RPC (step $step)"

  local tmp; tmp=$(mktemp)
  { seq "$start" "$step" "$end"; echo "$end"; } | sort -un \
    | xargs -P "$PARALLEL" -I{} bash -c 'block_ok {} && echo "{} 1" || echo "{} 0"' \
    | sort -n > "$tmp"

  local gaps=0 prev_b="" prev_s="" gap_start="" b s lo hi mid
  while read -r b s; do
    if [[ -z $prev_b ]]; then
      [[ $s == 0 ]] && gap_start=$b
    elif [[ $s != "$prev_s" ]]; then
      lo=$prev_b; hi=$b                       # status(lo)=prev_s, status(hi)=s
      while (( hi - lo > 1 )); do
        mid=$(( (lo + hi) / 2 ))
        if [[ $(status $mid) == "$prev_s" ]]; then lo=$mid; else hi=$mid; fi
      done
      if [[ $s == 0 ]]; then gap_start=$hi
      else echo "MISSING $gap_start-$lo ($((lo - gap_start + 1)) blocks)"; gaps=$((gaps+1)); gap_start=""; fi
    fi
    prev_b=$b; prev_s=$s
  done < "$tmp"
  if [[ -n $gap_start ]]; then
    echo "MISSING $gap_start-$prev_b ($((prev_b - gap_start + 1)) blocks, runs to END)"; gaps=$((gaps+1))
  fi
  rm -f "$tmp"
  (( gaps == 0 )) && echo "no missing blocks found"
  return 0
}

# ------------------------------------------------------------------------- download
check_files() {
  local start=$1 end=$2 missing=0 h
  for h in $(seq "$start" "$end"); do
    [[ -s $(block_file "$h") ]] || { echo "missing file for block $h"; missing=$((missing+1)); }
  done
  echo "files missing for $start..$end: $missing"
  (( missing == 0 ))
}

cmd_download() {
  local start=$1 end=$2 top dir
  need aws
  say "Downloading blocks $((start-1))..$((end+1)) from $S3_BUCKET"
  # Folders covering START-1 (format-check neighbour) through END+1.
  for (( dir=(start-2)/1000*1000; dir<=end/1000*1000; dir+=1000 )); do
    top=$(( dir/1000000*1000000 ))
    echo "  $top/$dir/"
    aws s3 sync "$S3_BUCKET/$top/$dir/" "$BLOCKS_DIR/$top/$dir/" \
      --request-payer requester --region "$AWS_REGION" --only-show-errors
  done
  check_files "$start" "$end" || die "some blocks are not in S3 (yet?)"
  for h in $((start-1)) $((end+1)); do
    [[ -s $(block_file "$h") ]] || echo "note: neighbour block $h not downloaded; format check will use what exists"
  done
  du -sh "$BLOCKS_DIR"
}

# --------------------------------------------------------------------------- import
format_check() {
  # Compares DB vs S3 for the blocks just outside the range (they must exist in both).
  local backup=$1 start=$2 end=$3 root h out ok=0
  root=$(mktemp -d); mkdir -p "$root/hyperliquid_data/db_hub"
  ln -s "$backup" "$root/hyperliquid_data/db_hub/Rpc"
  for h in $((start-1)) $((end+1)); do
    [[ -s $(block_file "$h") ]] || { echo "  block $h: no S3 file, skipped"; continue; }
    out=$("$IMPORTER_DIR/target/release/examples/compare" "$root" "$(block_file "$h")" "$h" 2>&1) || true
    [[ $out == *"block not in DB"* ]] && { echo "  block $h: not in DB, skipped"; continue; }
    echo "  block $h: ${out//$'\n'/ | }"
    [[ $out == *"FORMAT MATCHES"* ]] && ok=$((ok+1))
    [[ $out == *DIFFERENT* ]] && { rm -rf "$root"; die "format mismatch on block $h: DO NOT import"; }
  done
  rm -rf "$root"
  (( ok >= 1 )) || die "format could not be checked (neighbour blocks missing from DB or S3)"
}

cmd_import() {
  local start=$1 end=$2 backup size avail
  hl_running && die "hl-visor/hl-node is running: stop it first (docker compose stop)"
  NODE_STOPPED=1
  [[ -f $DB/CURRENT ]] || die "$DB is not a RocksDB database (wrong HL_DATA?)"
  [[ -x $IMPORTER && -x $IMPORTER_DIR/target/release/examples/compare ]] || die "run '$0 setup' first"
  check_files "$start" "$end" || die "run '$0 download $start $end' first"

  say "Backing up $DB"
  size=$(du -sk "$DB" | cut -f1); avail=$(df -Pk "$BACKUP_ROOT" | awk 'NR==2{print $4}')
  (( avail > size * 11 / 10 )) || die "not enough space in $BACKUP_ROOT for a $((size/1024/1024)) GB backup"
  backup="$BACKUP_ROOT/hl-Rpc-backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "$DB" "$backup"
  du -sh "$backup"

  say "Format check (S3 file vs stored block, read-only on the backup)"
  echo "  (backup kept at $backup even if this check fails)"
  format_check "$backup" "$start" "$end"

  say "Importing $start..$end"
  hl_running && die "hl started while we were working: stop it and run import again"
  "$IMPORTER" --start-block "$start" --end-block "$end" --ingest-dir "$BLOCKS_DIR" --db-dir "$HL_DATA"

  echo
  echo "Imported. Backup: $backup"
  echo "Roll back if needed (hl stopped): $0 restore $backup"
}

# --------------------------------------------------------------------------- verify
cmd_verify() {
  local start=$1 end=$2 bad
  say "Verifying $start..$end on $RPC"
  bad=$(seq "$start" "$end" | xargs -P "$PARALLEL" -I{} bash -c 'block_ok {} || echo {}' | sort -n)
  if [[ -z $bad ]]; then
    echo "OK: all $((end - start + 1)) blocks are served"
  else
    echo "FAIL: $(wc -l <<<"$bad") blocks still missing, first: $(head -1 <<<"$bad")"
    return 1
  fi
}

# ------------------------------------------------------------------------------ run
wait_rpc() {
  local t=0
  until rpc_head >/dev/null; do
    (( t >= WAIT_MAX )) && die "RPC not answering after ${WAIT_MAX}s (check docker compose logs)"
    sleep 10; t=$((t+10)); printf '.'
  done
  echo
}

cmd_run() {
  local start=$1 end=$2 head_at_stop
  [[ -f $COMPOSE_DIR/docker-compose.yml ]] || die "no docker-compose.yml in $COMPOSE_DIR (set COMPOSE_DIR)"
  [[ -x $IMPORTER ]] || cmd_setup
  cmd_download "$start" "$end"

  head_at_stop=$(rpc_head || true)
  confirm "Stop hl-node (docker compose stop in $COMPOSE_DIR) and import $start..$end?"
  (cd "$COMPOSE_DIR" && docker compose stop)
  NODE_STOPPED=1
  for _ in $(seq 30); do hl_running || break; sleep 2; done
  hl_running && die "hl is still running after docker compose stop"

  cmd_import "$start" "$end"

  say "Starting hl-node"
  (cd "$COMPOSE_DIR" && docker compose start)
  NODE_STOPPED=0
  say "Waiting for the RPC (up to ${WAIT_MAX}s)"
  wait_rpc
  cmd_verify "$start" "$end"

  if [[ -n $head_at_stop ]]; then
    echo
    echo "Node head before the stop: $head_at_stop. A restart can leave a new gap there."
    echo "Once the node has caught up, check with:"
    echo "  $0 scan $((head_at_stop - 100)) \$(( $head_at_stop + 20000 ))"
  fi
}

# -------------------------------------------------------------------------- restore
cmd_restore() {
  local backup=$1 failed
  hl_running && die "hl is running: stop it first"
  NODE_STOPPED=1
  [[ -f $backup/CURRENT ]] || die "$backup is not a RocksDB backup"
  failed="$DB.failed-$(date +%Y%m%d-%H%M%S)"
  mv "$DB" "$failed"
  cp -a "$backup" "$DB"
  echo "Restored $backup -> $DB (previous DB kept at $failed; delete it once the node is healthy)"
}

# ----------------------------------------------------------------------------- main
usage() { sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
range_args() { [[ ${1:-} =~ ^[0-9]+$ && ${2:-} =~ ^[0-9]+$ && $1 -le $2 && $1 -ge 2 ]] || usage; }

case ${1:-} in
  setup)    cmd_setup ;;
  scan)     range_args "${2:-}" "${3:-}"; cmd_scan "$2" "$3" "${4:-1}" ;;
  download) range_args "${2:-}" "${3:-}"; cmd_download "$2" "$3" ;;
  import)   range_args "${2:-}" "${3:-}"; cmd_import "$2" "$3" ;;
  verify)   range_args "${2:-}" "${3:-}"; cmd_verify "$2" "$3" ;;
  run)      range_args "${2:-}" "${3:-}"; cmd_run "$2" "$3" ;;
  restore)  [[ -n ${2:-} ]] || usage; cmd_restore "$2" ;;
  *)        usage ;;
esac
