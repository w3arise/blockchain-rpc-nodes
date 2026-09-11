#!/usr/bin/env bash
#
# Pull-based automatic upgrade: fetch origin/main, detect merged tag-only pin
# bumps, and apply them with apply-tag-only.sh.
#
# Run via cron on each node host. Idempotent — safe to run frequently.
#
# Usage:
#   ./scripts/auto-apply-if-merged.sh              # apply all changed chains
#   ./scripts/auto-apply-if-merged.sh aptos katana # apply only these chains
#
# Environment:
#   REPO_DIR        path to the repo checkout (default: script's parent dir)
#   REMOTE          git remote to fetch (default: origin)
#   BRANCH          branch to track (default: main)
#   DRY_RUN=1       print what would be applied without running
#   SKIP_FETCH=1    use local HEAD vs origin without fetching
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_FETCH="${SKIP_FETCH:-0}"

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

declare -A CHAIN_TO_GROUP
declare -A GROUP_ENV_FILE
for chain_id in "${ALL_IDS[@]}"; do
  env_file="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${chain_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["env_file"])')"
  group="$(python3 "${YAML_PY}" --file "${YAML_FILE}" json "${chain_id}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("apply_group") or "")')"
  if [[ -n "${group}" ]]; then
    CHAIN_TO_GROUP["${chain_id}"]="${group}"
    GROUP_ENV_FILE["${group}"]="${env_file}"
  else
    CHAIN_TO_GROUP["${chain_id}"]="${chain_id}"
    GROUP_ENV_FILE["${chain_id}"]="${env_file}"
  fi
done

GROUPS_TO_APPLY=()
for target in "${APPLY_TARGETS[@]}"; do
  env_file="${GROUP_ENV_FILE[${target}]:-}"
  if [[ -z "${env_file}" ]]; then
    continue
  fi
  if echo "${CHANGED_TEMPLATES}" | grep -qxF "${env_file}"; then
    if [[ ${#FILTER_CHAINS[@]} -gt 0 ]]; then
      for filter in "${FILTER_CHAINS[@]}"; do
        if [[ "${target}" == "${filter}" ]]; then
          GROUPS_TO_APPLY+=("${target}")
          break
        fi
      done
    else
      GROUPS_TO_APPLY+=("${target}")
    fi
  fi
done

if [[ ${#GROUPS_TO_APPLY[@]} -eq 0 ]]; then
  echo "No allowlisted chains changed between ${LOCAL:0:8} and ${REMOTE_REF:0:8}."
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
