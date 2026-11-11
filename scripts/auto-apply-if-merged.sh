#!/usr/bin/env bash
#
# Pull-based host apply for merged tag-only pins. Meant for cron (e.g. every
# 5 minutes) as the user that owns this checkout and runs its chains.
#
# Each run:
#   1. git fetch. Fast-forward only when every new commit touches nothing but
#      *.md, the root .gitignore, <dir>/env.template, files in chain dirs not
#      set up here, or auto-upgrade.yaml keys that do not change how a chain
#      set up here is applied. Anything else (the rest of scripts/, other root
#      files, other files in a chain dir with a .env) blocks the merge until a
#      human pulls.
#   2. For every allowlisted apply target set up in this checkout
#      (<compose_dir>/.env exists), compare each pin var (the YAML `var`) in
#      env.template with .env. A difference is a pending upgrade.
#   3. Validate each new pin against the YAML: image_prefix, same series as
#      the pin applied in .env (unless allow_series_jump), exclude list,
#      plain tag characters.
#   4. Apply with apply-tag-only.sh (SKIP_PULL=1), only when that target's
#      containers run from this checkout.
#
# .env is the record of what is applied, so a pin skipped while a node was
# stopped is picked up on a later run. No state file tracks commits.
#
# Every refusal is logged as "DENY <subject>: <reason>" on stderr and sent to
# syslog (logger -t auto-apply). Security denies (blocked merge, invalid pin,
# held failures, project collision) make the run exit 1, every run, until
# fixed. Operator choices (manual override, AUTO_APPLY_HOLD=1) exit 0.
#
# Other safety:
#   - A stopped chain is never started; it stays pending until it runs again.
#   - A failed apply writes .git/auto-apply/failed/<target> and holds the
#     target until an operator removes the marker. No restart loop.
#   - flock prevents overlapping runs.
#
# Usage:
#   ./scripts/auto-apply-if-merged.sh                # all local targets
#   ./scripts/auto-apply-if-merged.sh aptos katana   # only these targets
#   ./scripts/auto-apply-if-merged.sh --dry-run      # report every target, change nothing
#
# --dry-run fetches but does not merge or apply. It compares against
# REMOTE/BRANCH (unless the merge is blocked) and also prints targets that are
# up to date.
#
# Optional:
#   REMOTE=origin  BRANCH=main
#
set -euo pipefail

main() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
  YAML_PY="${SCRIPT_DIR}/lib/auto-upgrade-yaml.py"
  # Changes under scripts/ block the merge, except auto-upgrade.yaml edits that
# leave every set-up chain's apply keys unchanged (yaml_blocking).
  YAML_FILE="${SCRIPT_DIR}/config/auto-upgrade.yaml"
  # shellcheck source=SCRIPTDIR/lib/compose-project.sh
  source "${SCRIPT_DIR}/lib/compose-project.sh"

  REMOTE="${REMOTE:-origin}"
  BRANCH="${BRANCH:-main}"

  DRY_RUN=0
  FILTER=()
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run) DRY_RUN=1 ;;
      -*) die "unknown option: ${arg}" ;;
      *) FILTER+=("${arg}") ;;
    esac
  done

  for cmd in git python3 docker flock; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      die "required command not found: ${cmd}"
    fi
  done

  cd "${REPO_ROOT}"
  GIT_DIR="$(git rev-parse --absolute-git-dir)"
  STATE_DIR="${GIT_DIR}/auto-apply"
  mkdir -p "${STATE_DIR}/failed"

  exec 9>"${STATE_DIR}/lock"
  if ! flock -n 9; then
    log "another run holds ${STATE_DIR}/lock; exiting"
    exit 0
  fi

  if ! docker info >/dev/null 2>&1; then
    die "cannot reach the Docker daemon as $(id -un)"
  fi

  update_checkout
  local ref="${COMPARE_REF}"

  local target result
  local applied=0 failed=0 denied=0
  while read -r target; do
    [[ -n "${target}" ]] || continue
    if [[ ${#FILTER[@]} -gt 0 ]] && ! in_list "${target}" "${FILTER[@]}"; then
      continue
    fi
    result="$(check_target "${target}" "${ref}")"
    case "${result}" in
      apply)
        if [[ "${DRY_RUN}" == "1" ]]; then
          log "${target}: would apply (--dry-run)"
        elif apply_target "${target}"; then
          applied=$((applied + 1))
        else
          failed=$((failed + 1))
        fi
        ;;
      deny)
        denied=$((denied + 1))
        ;;
    esac
  done < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list-apply | awk '{print $1}')

  if (( applied > 0 )); then
    log "applied ${applied} target(s)"
  fi

  # apply-tag-only.sh syncs .env before compose up, so a target that failed
  # there no longer looks pending. Report every marker on every run.
  local marker held=0
  for marker in "${STATE_DIR}/failed/"*; do
    [[ -f "${marker}" ]] || continue
    deny "$(basename "${marker}")" "held after a failed or refused apply; fix it, then rm ${marker}"
    held=$((held + 1))
  done

  if (( failed > 0 || held > 0 || denied > 0 || BLOCKED > 0 )); then
    exit 1
  fi
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Refusal: stderr with timestamp, plus syslog so it survives a discarded cron log.
deny() {
  local subject="$1"
  shift
  log "DENY ${subject}: $*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t auto-apply -p user.warning -- "DENY ${subject}: $* (${REPO_ROOT})" || true
  fi
}

die() {
  log "ERROR: $*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t auto-apply -p user.err -- "ERROR: $* (${REPO_ROOT:-})" || true
  fi
  exit 1
}

in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

# Fast-forward to REMOTE/BRANCH. Refuses any other branch, diverged history,
# or commits that change more than the allowed paths (see blocking_files).
# Sets COMPARE_REF (where env.template pins are read) and BLOCKED.
update_checkout() {
  COMPARE_REF="HEAD"
  BLOCKED=0

  local current
  current="$(git symbolic-ref --quiet --short HEAD || true)"
  if [[ "${current}" != "${BRANCH}" ]]; then
    deny merge "checkout is on '${current:-detached HEAD}', expected '${BRANCH}'"
    exit 1
  fi

  git fetch --quiet "${REMOTE}" "${BRANCH}"

  local local_rev remote_rev
  local_rev="$(git rev-parse HEAD)"
  remote_rev="$(git rev-parse "${REMOTE}/${BRANCH}")"
  if [[ "${local_rev}" == "${remote_rev}" ]]; then
    return 0
  fi
  if ! git merge-base --is-ancestor "${local_rev}" "${remote_rev}"; then
    deny merge "HEAD ${local_rev:0:8} is not an ancestor of ${REMOTE}/${BRANCH} ${remote_rev:0:8}; fix the checkout by hand"
    exit 1
  fi

  # Collect first and check the exit status: a failed check must block, not
  # look like an empty (all-clear) list.
  local line blocking
  if ! blocking="$(blocking_files "${local_rev}" "${remote_rev}" </dev/null)"; then
    deny merge "could not check the files changed in ${local_rev:0:8} → ${remote_rev:0:8}; fix by hand"
    exit 1
  fi
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    BLOCKED=1
    deny merge "${REMOTE}/${BRANCH} ${remote_rev:0:8} changes ${line}"
  done <<<"${blocking}"
  if [[ "${BLOCKED}" == "1" ]]; then
    deny merge "not fast-forwarding ${local_rev:0:8} → ${remote_rev:0:8}; review, then git pull --ff-only by hand. Pending pins from ${local_rev:0:8} still apply."
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "${REMOTE}/${BRANCH} is ahead (${local_rev:0:8} → ${remote_rev:0:8}); not merging (--dry-run)"
    COMPARE_REF="${REMOTE}/${BRANCH}"
    return 0
  fi
  log "fast-forward ${local_rev:0:8} → ${remote_rev:0:8}"
  git merge --ff-only --quiet "${remote_rev}"
}

# Prints "<path> (<reason>)" for each file changed between $1 (HEAD) and $2
# that may not be merged without review. Allowed:
#   - *.md anywhere
#   - the repo-root .gitignore, as a regular file (only affects git status)
#   - <dir>/env.template, as a regular file
#   - files in a chain dir (has docker-compose.yml at HEAD) with no .env here
#   - scripts/config/auto-upgrade.yaml, when only check-side keys change for
#     chains set up here (see yaml_blocking)
# Chain dirs come from HEAD only, so a new commit cannot turn scripts/ (or any
# other dir) into a "chain dir" by adding a compose file.
# Returns non-zero when a check cannot run; the caller then blocks.
blocking_files() {
  local old="$1" new="$2"
  local f dir mode changed
  changed="$(git diff --name-only --no-renames "${old}" "${new}")" || return 1
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    [[ "${f}" == *.md ]] && continue
    if [[ "${f}" == ".gitignore" ]]; then
      mode="$(git ls-tree "${new}" -- "${f}" | awk '{print $1}')" || return 1
      if [[ -n "${mode}" && "${mode}" != "100644" ]]; then
        echo "${f} (.gitignore is not a regular file: mode ${mode})"
      fi
      continue
    fi
    if [[ "${f}" == "scripts/config/auto-upgrade.yaml" ]]; then
      yaml_blocking "${old}" "${new}" "${f}" || return 1
      continue
    fi
    if [[ "${f}" != */* ]]; then
      echo "${f} (repo root file)"
      continue
    fi
    dir="${f%%/*}"
    if [[ "${f}" == "${dir}/env.template" ]]; then
      mode="$(git ls-tree "${new}" -- "${f}" | awk '{print $1}')" || return 1
      if [[ -n "${mode}" && "${mode}" != "100644" ]]; then
        echo "${f} (env.template is not a regular file: mode ${mode})"
      fi
      continue
    fi
    if [[ -f "${REPO_ROOT}/${dir}/.env" ]]; then
      echo "${f} (in ${dir}/, which is set up here)"
      continue
    fi
    if ! git cat-file -e "${old}:${dir}/docker-compose.yml" 2>/dev/null; then
      echo "${f} (outside chain dirs)"
      continue
    fi
  done <<<"${changed}"
}

# auto-upgrade.yaml is the rulebook new pins are validated against, so a change
# to it may only merge unreviewed when no chain set up here (compose_dir with a
# .env) changes an apply-relevant key. Uses the parser at HEAD, never the new one.
yaml_blocking() {
  local old="$1" new="$2" f="$3" mode out rc
  mode="$(git ls-tree "${new}" -- "${f}" | awk '{print $1}')" || return 1
  if [[ "${mode}" != "100644" ]]; then
    echo "${f} (not a regular file at ${new:0:8}: mode ${mode:-deleted})"
    return 0
  fi
  rc=0
  out="$(python3 "${YAML_PY}" apply-view-diff \
    --old <(git show "${old}:${f}") --new <(git show "${new}:${f}") \
    --root "${REPO_ROOT}" 2>&1 </dev/null)" || rc=$?
  if [[ "${rc}" == "1" && -n "${out}" ]] && ! grep -qv '^[A-Za-z0-9_.-]*$' <<<"${out}"; then
    echo "${f} (apply settings change for: $(paste -sd, <<<"${out}"))"
  elif [[ "${rc}" != "0" ]]; then
    echo "${f} (cannot compare: $(tail -n1 <<<"${out:-exit ${rc}}"))"
  fi
}

env_value() {
  grep -E "^$2=" "$1" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

template_value() {
  local ref="$1" file="$2" var="$3"
  git show "${ref}:${file}" 2>/dev/null | grep -E "^${var}=" | tail -n1 | cut -d= -f2- || true
}

# True when VALUE was ever the pin for VAR in FILE on this branch.
seen_in_history() {
  local file="$1" var="$2" value="$3"
  git log --format= -p "${REMOTE}/${BRANCH}" -- "${file}" \
    | grep -E "^[-+]${var}=" \
    | cut -c2- \
    | cut -d= -f2- \
    | grep -qxF -- "${value}"
}

# IDs of containers of compose file $2 in compose dir $1: working_dir label,
# the project that file resolves to, and a service defined in that file. Two
# compose files in one dir (robinhood node + feed relay) never count for each
# other, even when COMPOSE_PROJECT_NAME in the shared .env merges their
# projects. Extra docker ps args (e.g. --all) follow. Prints nothing when the
# project or services cannot be resolved or docker ps fails (never applies).
containers_here() {
  local dir="$1" file="$2" project services
  shift 2
  project="$(compose_project_name "${dir}" "${file}" 2>/dev/null)" || return 0
  services="$(compose_services "${dir}" "${file}")" || return 0
  docker ps "$@" \
    --filter "label=com.docker.compose.project.working_dir=${dir}" \
    --filter "label=com.docker.compose.project=${project}" \
    --format '{{.ID}} {{.Label "com.docker.compose.service"}}' \
    | awk 'NR == FNR { svc[$0] = 1; next } ($2 in svc) { print $1 }' \
      <(printf '%s\n' "${services}") - || true
}

# Prints "apply" when the target should be applied now, "deny" for a security
# refusal (run exits 1), nothing otherwise. Logs go to stderr.
check_target() {
  local target="$1" ref="$2"
  local -a ids
  mapfile -t ids < <(python3 "${YAML_PY}" --file "${YAML_FILE}" apply-ids "${target}")
  [[ ${#ids[@]} -gt 0 ]] || return 0

  local AUTO_COMPOSE_DIR="" AUTO_COMPOSE_FILE="" AUTO_ENV_FILE="" AUTO_VAR=""
  # shellcheck disable=SC1090
  eval "$(python3 "${YAML_PY}" --file "${YAML_FILE}" export "${ids[0]}")"
  local compose_path="${REPO_ROOT}/${AUTO_COMPOSE_DIR}"
  local compose_file="${AUTO_COMPOSE_FILE}"
  local env_file="${compose_path}/.env"

  # Not set up from this checkout.
  [[ -f "${env_file}" ]] || return 0

  local -a changes=()
  local id want have problem
  for id in "${ids[@]}"; do
    # shellcheck disable=SC1090
    eval "$(python3 "${YAML_PY}" --file "${YAML_FILE}" export "${id}")"
    want="$(template_value "${ref}" "${AUTO_ENV_FILE}" "${AUTO_VAR}")"
    have="$(env_value "${env_file}" "${AUTO_VAR}")"
    if [[ -z "${want}" || "${want}" == "${have}" ]]; then
      continue
    fi
    if [[ -z "${have}" ]]; then
      # An optional service in a shared compose dir (e.g. the robinhood feed
      # relay) that was never set up: no var and no containers. Not a deny.
      if [[ -z "$(containers_here "${compose_path}" "${compose_file}" --all)" ]]; then
        if [[ "${DRY_RUN}" == "1" ]]; then
          log "${target}: ${AUTO_VAR} not in .env and no containers; not set up here" >&2
        fi
        return 0
      fi
      deny "${target}" "${AUTO_VAR} is not set in .env; set it up by hand first"
      echo deny
      return 0
    fi
    if ! seen_in_history "${AUTO_ENV_FILE}" "${AUTO_VAR}" "${have}"; then
      deny "${target}" "${AUTO_VAR}=${have} in .env is not a repo pin; leaving it (manual override)"
      return 0
    fi
    if ! problem="$(python3 "${YAML_PY}" --file "${YAML_FILE}" validate-pin "${id}" --current "${have}" --new "${want}")"; then
      deny "${target}" "${AUTO_VAR} ${have} → ${want} rejected: ${problem:-validate-pin failed}"
      echo deny
      return 0
    fi
    changes+=("${AUTO_VAR}: ${have} → ${want}")
  done

  if [[ ${#changes[@]} -eq 0 ]]; then
    if [[ "${DRY_RUN}" == "1" ]]; then
      log "${target}: up to date" >&2
    fi
    return 0
  fi

  local change
  for change in "${changes[@]}"; do
    log "${target}: pending ${change}" >&2
  done

  if [[ "$(env_value "${env_file}" AUTO_APPLY_HOLD)" == "1" ]]; then
    deny "${target}" "AUTO_APPLY_HOLD=1 in .env"
    return 0
  fi

  # Reported once per run by main.
  [[ -f "${STATE_DIR}/failed/${target}" ]] && return 0

  if [[ -z "$(containers_here "${compose_path}" "${compose_file}")" ]]; then
    log "${target}: not running from ${compose_path}/${compose_file}; will apply once it runs" >&2
    return 0
  fi

  echo apply
}

apply_target() {
  local target="$1"
  local marker="${STATE_DIR}/failed/${target}"
  local rc=0
  log "${target}: applying"
  SKIP_PULL=1 "${SCRIPT_DIR}/apply-tag-only.sh" "${target}" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    log "${target}: done"
    return 0
  fi
  {
    echo "time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "commit: $(git rev-parse HEAD)"
    echo "exit: ${rc}"
  } > "${marker}"
  if [[ "${rc}" -eq 3 ]]; then
    deny "${target}" "compose project also has containers from another directory (apply-tag-only.sh exit 3)"
  else
    deny "${target}" "apply-tag-only.sh failed (exit ${rc})"
  fi
  return 1
}

main "$@"
exit
