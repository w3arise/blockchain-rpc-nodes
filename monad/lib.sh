#!/usr/bin/env bash
# Shared helpers for Monad bare-metal scripts.

set -euo pipefail

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (bare-metal install writes /home/monad and systemd units)" >&2
    exit 1
  fi
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

load_env() {
  local dir="$1"
  ENV_FILE="${dir}/.env"
  ENV_TEMPLATE="${dir}/env.template"

  if [[ ! -f "${ENV_TEMPLATE}" ]]; then
    echo "ERROR: missing ${ENV_TEMPLATE}" >&2
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_TEMPLATE}" "${ENV_FILE}"
    echo "created .env from env.template — set NODE_NAME and TRIEDB_DRIVE, then re-run"
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${ENV_FILE}"
}

env_require() {
  local key="$1"
  local val="${!key:-}"
  if [[ -z "${val}" || "${val}" == *"<"* ]]; then
    echo "ERROR: set ${key} in .env before continuing" >&2
    exit 1
  fi
}

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

fetch_public_ip() {
  curl -4 -sf ip.me | tr -d '[:space:]'
}

ensure_monad_user() {
  if ! id monad &>/dev/null; then
    useradd -m -s /bin/bash monad
    echo "created user monad"
  fi

  mkdir -p "${MONAD_HOME}/monad-bft/config/forkpoint" \
           "${MONAD_HOME}/monad-bft/config/validators" \
           "${MONAD_HOME}/monad-bft/ledger"
}

write_monad_env() {
  cat > "${MONAD_HOME}/.env" <<EOF
CHAIN=${CHAIN}
KEYSTORE_PASSWORD='${KEYSTORE_PASSWORD}'
REMOTE_VALIDATORS_URL='${REMOTE_VALIDATORS_URL}'
REMOTE_FORKPOINT_URL='${REMOTE_FORKPOINT_URL}'
RETENTION_LEDGER=${RETENTION_LEDGER}
RETENTION_WAL=${RETENTION_WAL}
RETENTION_FORKPOINT=${RETENTION_FORKPOINT}
RETENTION_VALIDATORS=${RETENTION_VALIDATORS}
EOF
  chmod 600 "${MONAD_HOME}/.env"
  chown monad:monad "${MONAD_HOME}/.env"
}

# write_monad_env builds .env from env.template instead of using the official
# .env.example verbatim, so flag any variable upstream added that we do not set.
check_env_drift() {
  local example="${MONAD_HOME}/.env.example"
  local missing
  [[ -f "${example}" ]] || return 0

  missing="$(comm -23 \
    <(grep -oE '^[A-Z_]+=' "${example}" | tr -d '=' | sort -u) \
    <(grep -oE '^[A-Z_]+=' "${MONAD_HOME}/.env" | tr -d '=' | sort -u))"

  if [[ -n "${missing}" ]]; then
    echo "WARNING: ${example} defines variables missing from ${MONAD_HOME}/.env:" >&2
    echo "${missing}" | sed 's|^|  |' >&2
    echo "  add them to env.template and write_monad_env in lib.sh" >&2
  fi
}
