# shellcheck shell=bash
# Shared helpers for configure.sh and init-database.sh (sourced, not run).
# One place for: execution-client <-> COMPOSE_FILE mapping and in-place .env edits.

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

# set_env_var FILE KEY VALUE: replace the KEY= line, or append it. Safe to rerun.
set_env_var() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}=" "${file}"; then
    sed_inplace "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

# compose_file_for_client CLIENT: top compose file name; fails on an unknown client.
compose_file_for_client() {
  case "$1" in
    geth) echo "docker-compose.yml" ;;
    reth) echo "docker-compose.reth.yml" ;;
    *) return 1 ;;
  esac
}

# client_from_env FILE: geth|reth from the first COMPOSE_FILE entry in FILE (geth when unset).
client_from_env() {
  local file="$1" value="" first
  if [[ -f "${file}" ]]; then
    value="$(grep -E '^COMPOSE_FILE=' "${file}" | tail -n1 | cut -d= -f2- || true)"
  fi
  first="${value%%:*}"
  case "${first}" in
    ""|docker-compose.yml) echo geth ;;
    docker-compose.reth.yml) echo reth ;;
    *) echo "ERROR: unsupported COMPOSE_FILE=${value} (run ./configure.sh <network> geth|reth)" >&2; return 1 ;;
  esac
}

# client_stack_present CLIENT: success when a morph-<client> container exists (running or stopped).
client_stack_present() {
  command -v docker >/dev/null 2>&1 || return 1
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "morph-$1"
}

# valid_ipv4 VALUE: success for a dotted-quad IPv4 address (each octet 0-255).
valid_ipv4() {
  local ip="$1" octet
  [[ "${ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  local IFS=.
  for octet in ${ip}; do
    (( 10#${octet} <= 255 )) || return 1
  done
}
