# Shared helpers for Conduit genesis check/upgrade scripts.
# Sourced by <chain>/check-genesis.sh — do not run directly.

check_genesis_require_cmd() {
  local bin
  for bin in curl jq diff; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "ERROR: ${bin} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

check_genesis_fetch_remote() {
  local slug="$1"
  local dest="$2"
  local url="https://api.conduit.xyz/file/v1/optimism/genesis/${slug}"

  echo "Fetching published genesis (${slug})..."
  if ! curl -fsSL --retry 5 --retry-delay 5 "$url" -o "$dest"; then
    echo "ERROR: failed to download genesis from ${url}" >&2
    exit 1
  fi

  if ! jq empty "$dest" >/dev/null 2>&1; then
    echo "ERROR: downloaded genesis is not valid JSON (${url})" >&2
    exit 1
  fi
}

check_genesis_fetch_fork_timestamps() {
  local slug="$1"
  local dest="$2"
  local url="https://api.conduit.xyz/file/v1/optimism/forkTimestamps/${slug}"

  if curl -fsSL --retry 3 --retry-delay 3 "$url" -o "$dest" 2>/dev/null \
    && jq empty "$dest" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_genesis_show_fork_summary() {
  local label="$1"
  local file="$2"

  echo ""
  echo "${label} fork fields (.config):"
  jq -r '.config | {
    chainId,
    bedrockBlock,
    isthmusTime,
    jovianTime,
    karstTime
  }' "$file"
}

check_genesis_config_diff() {
  local local_file="$1"
  local remote_file="$2"

  echo ""
  echo "Config diff (local vs published, after any chain-specific patches):"
  diff -u \
    <(jq -S '.config' "$local_file") \
    <(jq -S '.config' "$remote_file") \
    || true
}

check_genesis_configs_match() {
  local local_file="$1"
  local remote_file="$2"

  diff -q \
    <(jq -S '.config' "$local_file") \
    <(jq -S '.config' "$remote_file") \
    >/dev/null 2>&1
}

check_genesis_print_override_hints() {
  local slug="$1"
  local fork_file="$2"

  echo ""
  echo "op-node fork override hints (from Conduit forkTimestamps/${slug}):"
  local karst jovian isthmus
  karst="$(jq -r '.karst_time // empty' "$fork_file")"
  jovian="$(jq -r '.jovian_time // empty' "$fork_file")"
  isthmus="$(jq -r '.isthmus_time // empty' "$fork_file")"

  if [[ -n "$karst" && "$karst" != "null" ]]; then
    echo "  OP_NODE_OVERRIDE_KARST=${karst}"
  else
    echo "  OP_NODE_OVERRIDE_KARST=  (not published yet — re-check before the fork)"
  fi
  if [[ -n "$jovian" && "$jovian" != "null" && "$jovian" != "0" ]]; then
    echo "  OP_NODE_OVERRIDE_JOVIAN=${jovian}"
  fi
  if [[ -n "$isthmus" && "$isthmus" != "null" && "$isthmus" != "0" ]]; then
    echo "  OP_NODE_OVERRIDE_ISTHMUS=${isthmus}"
  fi
}

check_genesis_print_fork_readiness() {
  echo ""
  echo "Before the fork, verify in .env:"
  echo "  - op-node >= v1.19.3"
  echo "  - op-reth >= v2.1.2 (or current conduit-op-reth for Conduit builds)"
  echo "  - OP_NODE_OVERRIDE_KARST set when Conduit publishes karst_time"
}

check_genesis_print_restart_hint() {
  local chain_dir="$1"

  echo ""
  echo "Restart execution + rollup clients to pick up genesis changes:"
  echo "  cd ${chain_dir}"
  echo "  docker compose down && docker compose up -d"
  check_genesis_print_fork_readiness
}

check_genesis_confirm_replace() {
  local prompt="$1"
  read -r -p "${prompt} [y/N] " reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

check_genesis_backup_and_replace() {
  local local_file="$1"
  local remote_file="$2"
  local backup="${local_file}.bak.$(date +%Y%m%d-%H%M%S)"

  cp -a "$local_file" "$backup"
  cp -a "$remote_file" "$local_file"
  echo "Backed up local genesis to: ${backup}"
  echo "Updated: ${local_file}"
}

# Main entry — callers set these before invoking:
#   CHECK_GENESIS_SLUG, CHECK_GENESIS_LOCAL, CHECK_GENESIS_CHAIN_DIR
# Optional:
#   CHECK_GENESIS_PATCH_REMOTE_CMD — shell command mutating $1 (remote temp path)
run_check_conduit_genesis() {
  check_genesis_require_cmd

  local slug="${CHECK_GENESIS_SLUG:?CHECK_GENESIS_SLUG not set}"
  local local_file="${CHECK_GENESIS_LOCAL:?CHECK_GENESIS_LOCAL not set}"
  local chain_dir="${CHECK_GENESIS_CHAIN_DIR:?CHECK_GENESIS_CHAIN_DIR not set}"

  local tmp_remote fork_file
  tmp_remote="$(mktemp)"
  fork_file="$(mktemp)"
  trap 'rm -f "$tmp_remote" "$fork_file"' EXIT

  check_genesis_fetch_remote "$slug" "$tmp_remote"

  if [[ -n "${CHECK_GENESIS_PATCH_REMOTE_CMD:-}" ]]; then
    # shellcheck disable=SC2086
    eval "$CHECK_GENESIS_PATCH_REMOTE_CMD" "$tmp_remote"
  fi

  if check_genesis_fetch_fork_timestamps "$slug" "$fork_file"; then
    check_genesis_print_override_hints "$slug" "$fork_file"
  else
    echo ""
    echo "WARNING: could not fetch forkTimestamps for ${slug}."
  fi

  echo ""
  check_genesis_show_fork_summary "Published" "$tmp_remote"

  if [[ ! -f "$local_file" ]]; then
    echo ""
    echo "Local genesis not found: ${local_file}"
    if check_genesis_confirm_replace "Download published genesis to ${local_file}?"; then
      mkdir -p "$(dirname "$local_file")"
      cp -a "$tmp_remote" "$local_file"
      echo "Wrote ${local_file}"
      check_genesis_print_restart_hint "$chain_dir"
    else
      echo "Aborted."
      exit 1
    fi
    return 0
  fi

  echo ""
  check_genesis_show_fork_summary "Local" "$local_file"

  if check_genesis_configs_match "$local_file" "$tmp_remote"; then
    echo ""
    echo "OK: local genesis .config matches published Conduit genesis."
    echo "No genesis update needed."
    check_genesis_print_fork_readiness
    return 0
  fi

  check_genesis_config_diff "$local_file" "$tmp_remote"

  echo ""
  if check_genesis_confirm_replace "Replace ${local_file} with published genesis?"; then
    check_genesis_backup_and_replace "$local_file" "$tmp_remote"
    check_genesis_print_restart_hint "$chain_dir"
  else
    echo "No changes made."
    exit 1
  fi
}
