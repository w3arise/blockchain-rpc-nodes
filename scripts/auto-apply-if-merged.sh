#!/usr/bin/env bash
#
# Pull-based automatic upgrade: fetch origin/main, detect merged tag-only pin
# bumps, and apply them with apply-tag-only.sh.
#
# Designed for bare metal hosts where multiple chains run under different Linux
# users. Each user runs this script via cron; it auto-detects which chains are
# running locally (via Docker) and only upgrades those.
#
# Usage:
#   ./scripts/auto-apply-if-merged.sh              # auto-detect and apply
#   ./scripts/auto-apply-if-merged.sh aptos katana # filter to specific chains
#   ./scripts/auto-apply-if-merged.sh --list-local # list locally running chains
#
# Environment:
#   REPO_DIR          path to the repo checkout (default: script's parent dir)
#   REMOTE            git remote to fetch (default: origin)
#   BRANCH            branch to track (default: main)
#   DRY_RUN=1         print what would be applied without running
#   SKIP_FETCH=1      use local HEAD vs origin without fetching
#   SKIP_DETECT=1     skip auto-detection, apply all changed chains
#   FORCE_APPLY=1     apply even if containers not detected (useful for first start)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_FETCH="${SKIP_FETCH:-0}"
SKIP_DETECT="${SKIP_DETECT:-0}"
FORCE_APPLY="${FORCE_APPLY:-0}"

YAML_PY="${SCRIPT_DIR}/lib/auto-upgrade-yaml.py"
YAML_FILE="${SCRIPT_DIR}/auto-upgrade.yaml"

cd "${REPO_DIR}"

if [[ ! -f "${YAML_FILE}" ]]; then
  echo "ERROR: missing ${YAML_FILE}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found" >&2
  exit 1
fi

# Check if a chain's Docker containers are running locally.
# Returns 0 if at least one container from the compose project is running.
chain_is_running() {
  local compose_dir="$1"
  local compose_file="${REPO_DIR}/${compose_dir}/docker-compose.yml"
  
  if [[ ! -f "${compose_file}" ]]; then
    return 1
  fi
  
  # Try docker compose ps first (modern)
  if docker compose -f "${compose_file}" ps --status running 2>/dev/null | grep -qv '^NAME'; then
    return 0
  fi
  
  # Fallback: check if any container with project name prefix is running
  local project_name
  project_name="$(basename "${compose_dir}")"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${project_name}[-_]"; then
    return 0
  fi
  
  return 1
}

# List all locally running chains (for --list-local)
list_local_chains() {
  mapfile -t APPLY_TARGETS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list-apply | awk '{print $1}')
  
  local running=()
  for target in "${APPLY_TARGETS[@]}"; do
    local first_id
    first_id="$(python3 "${YAML_PY}" --file "${YAML_FILE}" apply-ids "${target}" | head -n1)"
    local compose_dir
    compose_dir="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${first_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["compose_dir"])')"
    
    if chain_is_running "${compose_dir}"; then
      running+=("${target}")
    fi
  done
  
  if [[ ${#running[@]} -eq 0 ]]; then
    echo "No chains detected running locally."
  else
    echo "Locally running chains:"
    for chain in "${running[@]}"; do
      echo "  ${chain}"
    done
  fi
}

# Handle --list-local flag
if [[ "${1:-}" == "--list-local" ]]; then
  list_local_chains
  exit 0
fi

mapfile -t FILTER_CHAINS < <(printf '%s\n' "$@")

if [[ "${SKIP_FETCH}" != "1" ]]; then
  git fetch "${REMOTE}" "${BRANCH}" --quiet
fi

LOCAL="$(git rev-parse HEAD)"
REMOTE_REF="$(git rev-parse "${REMOTE}/${BRANCH}")"

if [[ "${LOCAL}" == "${REMOTE_REF}" ]]; then
  echo "Already up to date (${LOCAL:0:8})."
  exit 0
fi

if ! git merge-base --is-ancestor "${LOCAL}" "${REMOTE_REF}"; then
  echo "ERROR: local HEAD ${LOCAL:0:8} is not an ancestor of ${REMOTE}/${BRANCH} ${REMOTE_REF:0:8}" >&2
  echo "Manual intervention required (rebase or reset)." >&2
  exit 1
fi

CHANGED_FILES="$(git diff --name-only "${LOCAL}..${REMOTE_REF}")"
CHANGED_TEMPLATES="$(echo "${CHANGED_FILES}" | grep '/env.template$' || true)"

if [[ -z "${CHANGED_TEMPLATES}" ]]; then
  echo "No env.template changes between ${LOCAL:0:8} and ${REMOTE_REF:0:8}."
  git pull --ff-only --quiet
  exit 0
fi

mapfile -t ALL_IDS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list)
mapfile -t APPLY_TARGETS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list-apply | awk '{print $1}')

declare -A GROUP_ENV_FILE
declare -A GROUP_COMPOSE_DIR
for chain_id in "${ALL_IDS[@]}"; do
  env_file="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${chain_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["env_file"])')"
  compose_dir="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${chain_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["compose_dir"])')"
  group="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${chain_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("apply_group") or "")')"
  if [[ -n "${group}" ]]; then
    GROUP_ENV_FILE["${group}"]="${env_file}"
    GROUP_COMPOSE_DIR["${group}"]="${compose_dir}"
  else
    GROUP_ENV_FILE["${chain_id}"]="${env_file}"
    GROUP_COMPOSE_DIR["${chain_id}"]="${compose_dir}"
  fi
done

GROUPS_TO_APPLY=()
SKIPPED_NOT_RUNNING=()

for target in "${APPLY_TARGETS[@]}"; do
  env_file="${GROUP_ENV_FILE[${target}]:-}"
  compose_dir="${GROUP_COMPOSE_DIR[${target}]:-}"
  
  if [[ -z "${env_file}" ]]; then
    continue
  fi
  
  # Check if this chain's env.template was changed
  if ! echo "${CHANGED_TEMPLATES}" | grep -qxF "${env_file}"; then
    continue
  fi
  
  # Apply filter if specified
  if [[ ${#FILTER_CHAINS[@]} -gt 0 ]]; then
    match=0
    for filter in "${FILTER_CHAINS[@]}"; do
      if [[ "${target}" == "${filter}" ]]; then
        match=1
        break
      fi
    done
    if [[ "${match}" -eq 0 ]]; then
      continue
    fi
  fi
  
  # Auto-detect: skip chains not running locally (unless SKIP_DETECT or FORCE_APPLY)
  if [[ "${SKIP_DETECT}" != "1" && "${FORCE_APPLY}" != "1" ]]; then
    if ! chain_is_running "${compose_dir}"; then
      SKIPPED_NOT_RUNNING+=("${target}")
      continue
    fi
  fi
  
  GROUPS_TO_APPLY+=("${target}")
done

# Report skipped chains
if [[ ${#SKIPPED_NOT_RUNNING[@]} -gt 0 ]]; then
  echo "Skipped (not running locally): ${SKIPPED_NOT_RUNNING[*]}"
fi

if [[ ${#GROUPS_TO_APPLY[@]} -eq 0 ]]; then
  echo "No locally running chains need upgrades between ${LOCAL:0:8} and ${REMOTE_REF:0:8}."
  git pull --ff-only --quiet
  exit 0
fi

echo "Pulling ${REMOTE}/${BRANCH} (${LOCAL:0:8} → ${REMOTE_REF:0:8})..."
git pull --ff-only --quiet

echo "Applying tag-only upgrades for: ${GROUPS_TO_APPLY[*]}"
echo

FAILED=()
for target in "${GROUPS_TO_APPLY[@]}"; do
  echo "=== ${target} ==="
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[DRY_RUN] Would run: ./scripts/apply-tag-only.sh ${target}"
  else
    if ! "${SCRIPT_DIR}/apply-tag-only.sh" "${target}"; then
      echo "ERROR: apply-tag-only.sh ${target} failed" >&2
      FAILED+=("${target}")
    fi
  fi
  echo
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "FAILED: ${FAILED[*]}" >&2
  exit 1
fi

echo "Done. Applied ${#GROUPS_TO_APPLY[@]} upgrade(s)."
