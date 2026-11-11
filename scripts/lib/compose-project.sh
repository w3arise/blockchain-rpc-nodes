# shellcheck shell=bash
# Shared compose helpers for apply-tag-only.sh and auto-apply-if-merged.sh.
# Sourced — do not run directly. Callers run with set -euo pipefail.
# Every helper takes the dir and the YAML compose_file explicitly; no global
# state, so they work the same inside $(...) subshells.

# compose_cmd DIR FILE ARGS...: runs "docker compose [-f FILE] ARGS..." in DIR.
# The default docker-compose.yml gets no -f, so compose still loads a
# docker-compose.override.yml next to it, as it did before compose_file.
compose_cmd() {
  local dir="$1" file="$2"
  shift 2
  local -a file_args=()
  if [[ "${file}" != "docker-compose.yml" ]]; then
    file_args=(-f "${file}")
  fi
  (cd "${dir}" && docker compose "${file_args[@]}" "$@")
}

# Prints the compose project name for compose file $2 in directory $1 (the
# com.docker.compose.project label of its containers). Falls back to the
# lowercased directory name for the default file; returns 1 when another
# file's name cannot be resolved (guessing would pick the wrong project).
compose_project_name() {
  local dir="$1" file="$2" name=""
  name="$(compose_cmd "${dir}" "${file}" config 2>/dev/null \
    | sed -n 's/^name: //p')" || name=""
  # First line only; no head(1), whose early exit could fail the pipe (pipefail).
  name="${name%%$'\n'*}"
  if [[ -z "${name}" ]]; then
    if [[ "${file}" != "docker-compose.yml" ]]; then
      echo "ERROR: cannot resolve the compose project of ${dir}/${file}" >&2
      return 1
    fi
    name="$(basename "$(cd "${dir}" && pwd -P)" | tr '[:upper:]' '[:lower:]')"
  fi
  printf '%s\n' "${name}"
}

# Prints the service names defined in compose file $2 in directory $1, one per
# line. Returns 1 when compose cannot read the file or it defines none.
compose_services() {
  local services
  services="$(compose_cmd "$1" "$2" config --services 2>/dev/null)" || return 1
  [[ -n "${services}" ]] || return 1
  printf '%s\n' "${services}"
}
