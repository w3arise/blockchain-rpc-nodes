#!/usr/bin/env bash
#
# System-level dispatcher for multi-user bare metal hosts.
#
# Fetches the repo once (as root or a shared user), then triggers per-user
# upgrades by running auto-apply-if-merged.sh as each chain's owner.
#
# This script is designed to run via root cron or systemd timer. It discovers
# which users have running chain containers and triggers upgrades for them.
#
# Usage:
#   sudo ./scripts/auto-apply-dispatcher.sh
#
# Configuration:
#   /etc/blockchain-nodes.conf (optional) — map chains to users and repo paths:
#
#     # Format: chain_or_group:username:repo_path
#     aptos:aptos:/home/aptos/blockchain-rpc-nodes
#     arbitrum:arbitrum:/home/arbitrum/blockchain-rpc-nodes
#     katana:opstack:/home/opstack/blockchain-rpc-nodes
#     bob:opstack:/home/opstack/blockchain-rpc-nodes
#
#   If no config file exists, the script auto-discovers by scanning running
#   Docker containers and matching them to chain compose directories.
#
# Environment:
#   CONFIG_FILE       path to config (default: /etc/blockchain-nodes.conf)
#   SHARED_REPO       shared repo path for git fetch (default: first user's repo)
#   DRY_RUN=1         print what would be run without executing
#   SKIP_FETCH=1      skip the shared git fetch
#
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/blockchain-nodes.conf}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_FETCH="${SKIP_FETCH:-0}"
SHARED_REPO="${SHARED_REPO:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_PY="${SCRIPT_DIR}/lib/auto-upgrade-yaml.py"
YAML_FILE="${SCRIPT_DIR}/auto-upgrade.yaml"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  log "ERROR: $*" >&2
}

# Discover chain owner by finding who owns the running container
discover_chain_owner() {
  local compose_dir="$1"
  local project_name
  project_name="$(basename "${compose_dir}")"
  
  # Find a running container for this project
  local container_id
  container_id="$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null \
    | grep -E " ${project_name}[-_]" \
    | head -n1 \
    | awk '{print $1}')" || true
  
  if [[ -z "${container_id}" ]]; then
    return 1
  fi
  
  # Get the compose file path from container labels
  local compose_file
  compose_file="$(docker inspect "${container_id}" \
    --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)" || true
  
  if [[ -z "${compose_file}" || ! -d "${compose_file}" ]]; then
    return 1
  fi
  
  # Find the repo root (parent of compose_dir)
  local repo_path="${compose_file}"
  while [[ "${repo_path}" != "/" ]]; do
    if [[ -d "${repo_path}/.git" ]]; then
      break
    fi
    repo_path="$(dirname "${repo_path}")"
  done
  
  if [[ "${repo_path}" == "/" ]]; then
    return 1
  fi
  
  # Get the owner of the repo
  local owner
  owner="$(stat -c '%U' "${repo_path}" 2>/dev/null)" || return 1
  
  echo "${owner}:${repo_path}"
}

# Load config or auto-discover
declare -A CHAIN_USER
declare -A CHAIN_REPO

load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    log "Loading config from ${CONFIG_FILE}"
    while IFS=: read -r chain user repo || [[ -n "${chain}" ]]; do
      # Skip comments and empty lines
      [[ "${chain}" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${chain// }" ]] && continue
      
      chain="${chain// }"
      user="${user// }"
      repo="${repo// }"
      
      if [[ -n "${chain}" && -n "${user}" && -n "${repo}" ]]; then
        CHAIN_USER["${chain}"]="${user}"
        CHAIN_REPO["${chain}"]="${repo}"
      fi
    done < "${CONFIG_FILE}"
  else
    log "No config file at ${CONFIG_FILE}, auto-discovering..."
    
    # Get all apply targets from YAML
    mapfile -t APPLY_TARGETS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list-apply | awk '{print $1}')
    
    for target in "${APPLY_TARGETS[@]}"; do
      local first_id
      first_id="$(python3 "${YAML_PY}" --file "${YAML_FILE}" apply-ids "${target}" | head -n1)"
      local compose_dir
      compose_dir="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${first_id}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["compose_dir"])')"
      
      local discovery
      if discovery="$(discover_chain_owner "${compose_dir}")"; then
        local user repo
        user="${discovery%%:*}"
        repo="${discovery#*:}"
        CHAIN_USER["${target}"]="${user}"
        CHAIN_REPO["${target}"]="${repo}"
        log "  Discovered: ${target} -> ${user} @ ${repo}"
      fi
    done
  fi
}

# Group chains by user and repo
declare -A USER_REPO_CHAINS

group_by_user() {
  for chain in "${!CHAIN_USER[@]}"; do
    local user="${CHAIN_USER[${chain}]}"
    local repo="${CHAIN_REPO[${chain}]}"
    local key="${user}:${repo}"
    
    if [[ -n "${USER_REPO_CHAINS[${key}]:-}" ]]; then
      USER_REPO_CHAINS["${key}"]="${USER_REPO_CHAINS[${key}]} ${chain}"
    else
      USER_REPO_CHAINS["${key}"]="${chain}"
    fi
  done
}

# Main
main() {
  if [[ "${EUID}" -ne 0 && -z "${SUDO_USER:-}" ]]; then
    log "Warning: not running as root. May not be able to switch users."
  fi
  
  load_config
  
  if [[ ${#CHAIN_USER[@]} -eq 0 ]]; then
    log "No chains discovered or configured. Nothing to do."
    exit 0
  fi
  
  group_by_user
  
  # Determine shared repo for initial fetch
  if [[ -z "${SHARED_REPO}" ]]; then
    for key in "${!USER_REPO_CHAINS[@]}"; do
      SHARED_REPO="${key#*:}"
      break
    done
  fi
  
  # Single fetch for the shared repo (if accessible)
  if [[ "${SKIP_FETCH}" != "1" && -d "${SHARED_REPO}/.git" ]]; then
    log "Fetching ${SHARED_REPO}..."
    if [[ "${DRY_RUN}" == "1" ]]; then
      log "[DRY_RUN] Would fetch in ${SHARED_REPO}"
    else
      (cd "${SHARED_REPO}" && git fetch origin main --quiet) || true
    fi
  fi
  
  # Trigger per-user upgrades
  local failed=()
  for key in "${!USER_REPO_CHAINS[@]}"; do
    local user="${key%%:*}"
    local repo="${key#*:}"
    local chains="${USER_REPO_CHAINS[${key}]}"
    
    log "Triggering upgrade for user '${user}' @ ${repo}"
    log "  Chains: ${chains}"
    
    local apply_script="${repo}/scripts/auto-apply-if-merged.sh"
    if [[ ! -x "${apply_script}" ]]; then
      error "Script not found or not executable: ${apply_script}"
      failed+=("${user}")
      continue
    fi
    
    local cmd="cd '${repo}' && SKIP_FETCH=1 ./scripts/auto-apply-if-merged.sh ${chains}"
    
    if [[ "${DRY_RUN}" == "1" ]]; then
      log "[DRY_RUN] Would run as ${user}: ${cmd}"
    else
      if [[ "${EUID}" -eq 0 ]]; then
        if ! su - "${user}" -c "${cmd}"; then
          error "Upgrade failed for user ${user}"
          failed+=("${user}")
        fi
      else
        # Not root, try to run directly (assumes current user has access)
        if ! bash -c "${cmd}"; then
          error "Upgrade failed: ${cmd}"
          failed+=("${user}")
        fi
      fi
    fi
    
    echo
  done
  
  if [[ ${#failed[@]} -gt 0 ]]; then
    error "Failed users: ${failed[*]}"
    exit 1
  fi
  
  log "Dispatcher complete."
}

main "$@"
