#!/usr/bin/env bash
#
# Root cron / systemd timer alternative to one crontab per user. Runs
# auto-apply-if-merged.sh once per listed checkout, as the user that owns it.
# Each run fetches its own checkout; nothing runs git as root.
#
# Config (default /etc/blockchain-nodes.conf), one checkout per line:
#
#   # user:repo_path
#   <user>:/home/<user>/blockchain-rpc-nodes
#
# The per-checkout script finds the chains itself (<compose_dir>/.env present
# and containers running from that checkout), so no chain list is needed.
#
# Install a root-owned copy and run that, never the copy inside a user's
# checkout (that user could edit it and get root):
#
#   sudo install -o root -g root -m 0755 scripts/auto-apply-dispatcher.sh \
#     /usr/local/sbin/auto-apply-dispatcher
#
# Usage:
#   sudo auto-apply-dispatcher
#   sudo auto-apply-dispatcher --dry-run   # passed to each checkout
#
# Refuses (DENY, exit 1) when this script, its directory, or the config file is
# not root-owned or is group/world-writable, and skips lines whose user is
# uid 0. Refusals also go to syslog (logger -t auto-apply-dispatcher).
#
# Optional:
#   CONFIG_FILE=/etc/blockchain-nodes.conf
#
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/blockchain-nodes.conf}"
APPLY_ARGS=""
case "${1:-}" in
  "") ;;
  --dry-run) APPLY_ARGS=" --dry-run" ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

deny() {
  log "DENY $*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t auto-apply-dispatcher -p user.warning -- "DENY $*" || true
  fi
}

# Root-owned and not writable by group or others.
root_only() {
  local uid mode
  read -r uid mode < <(stat -L -c '%u %a' "$1")
  [[ "${uid}" == "0" ]] && (( (8#${mode} & 8#022) == 0 ))
}

if [[ "${EUID}" -ne 0 ]]; then
  log "ERROR: run as root (runuser switches to each checkout owner)" >&2
  exit 1
fi

self="$(readlink -f "${BASH_SOURCE[0]}")"
for path in "${self}" "$(dirname "${self}")"; do
  if ! root_only "${path}"; then
    deny "dispatcher: ${path} is not root-owned or is group/world-writable; install a root-owned copy (see header)"
    exit 1
  fi
done

if [[ ! -f "${CONFIG_FILE}" ]]; then
  log "ERROR: missing ${CONFIG_FILE}" >&2
  exit 1
fi
if ! root_only "${CONFIG_FILE}"; then
  deny "dispatcher: ${CONFIG_FILE} is not root-owned or is group/world-writable"
  exit 1
fi

failed=()
while IFS=: read -r user repo || [[ -n "${user}" ]]; do
  user="${user//[[:space:]]/}"
  repo="${repo//[[:space:]]/}"
  [[ -z "${user}" || "${user}" == \#* ]] && continue

  if ! id -u "${user}" >/dev/null 2>&1; then
    deny "${user}: no such user"
    failed+=("${user}:${repo}")
    continue
  fi
  if [[ "$(id -u "${user}")" == "0" ]]; then
    deny "${user}: uid 0; checkouts never run as root"
    failed+=("${user}:${repo}")
    continue
  fi
  script="${repo}/scripts/auto-apply-if-merged.sh"
  if [[ ! -x "${script}" ]]; then
    deny "${user}: ${script} missing or not executable"
    failed+=("${user}:${repo}")
    continue
  fi
  owner="$(stat -c '%U' "${repo}/.git")"
  if [[ "${owner}" != "${user}" ]]; then
    deny "${user}: ${repo}/.git is owned by ${owner}, not ${user}"
    failed+=("${user}:${repo}")
    continue
  fi

  log "${user}: ${repo}"
  if ! runuser -l "${user}" -c "cd $(printf '%q' "${repo}") && ./scripts/auto-apply-if-merged.sh${APPLY_ARGS}"; then
    failed+=("${user}:${repo}")
  fi
done < "${CONFIG_FILE}"

if [[ ${#failed[@]} -gt 0 ]]; then
  log "ERROR: failed: ${failed[*]}" >&2
  exit 1
fi
