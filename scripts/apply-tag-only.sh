#!/usr/bin/env bash
#
# Apply a merged tag-only pin on a live host: sync the allowlisted var(s) from
# env.template into the existing .env, then compose pull + up.
#
# Usage:
#   ./scripts/apply-tag-only.sh aptos
#   ./scripts/apply-tag-only.sh arbitrum
#   ./scripts/apply-tag-only.sh katana          # apply_group: both op-reth + op-node
#   ./scripts/apply-tag-only.sh katana-op-reth  # one pin only
#
# Does not rewrite other .env keys (L1 URLs, passwords). First-start still
# uses <chain>/configure.sh. Does not run configure.sh.
#
# Optional:
#   SKIP_PULL=1       do not git pull --ff-only
#   SKIP_COMPOSE=1    sync .env only
#   HEALTH_TIMEOUT=180
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
YAML_PY="${SCRIPT_DIR}/lib/auto-upgrade-yaml.py"
YAML_FILE="${SCRIPT_DIR}/auto-upgrade.yaml"

CHAIN_ID="${1:-}"
if [[ -z "${CHAIN_ID}" || -n "${2:-}" ]]; then
  echo "Usage: $0 <chain-id|apply-group>" >&2
  echo "Allowlist:" >&2
  python3 "${YAML_PY}" --file "${YAML_FILE}" list-apply >&2
  exit 2
fi

SKIP_PULL="${SKIP_PULL:-0}"
SKIP_COMPOSE="${SKIP_COMPOSE:-0}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"

cd "${REPO_ROOT}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: required command not found: python3" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: required command not found: git" >&2
  exit 1
fi

mapfile -t TARGET_IDS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" apply-ids "${CHAIN_ID}")
if [[ ${#TARGET_IDS[@]} -eq 0 ]]; then
  echo "ERROR: unknown chain id or apply_group: ${CHAIN_ID}" >&2
  exit 1
fi

# shellcheck disable=SC1090
eval "$(python3 "${YAML_PY}" --file "${YAML_FILE}" export "${TARGET_IDS[0]}")"

COMPOSE_DIR="${REPO_ROOT}/${AUTO_COMPOSE_DIR}"
ENV_TEMPLATE="${REPO_ROOT}/${AUTO_ENV_FILE}"
ENV_FILE="${COMPOSE_DIR}/.env"

if [[ ! -d "${COMPOSE_DIR}" ]]; then
  echo "ERROR: missing compose dir ${COMPOSE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${ENV_TEMPLATE}" ]]; then
  echo "ERROR: missing ${ENV_TEMPLATE}" >&2
  exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} does not exist — copy env.template to .env first" >&2
  exit 1
fi

dirty="$(git status --porcelain -- "${AUTO_COMPOSE_DIR}" | grep -vE '^\?\?' || true)"
if [[ -n "${dirty}" ]]; then
  echo "ERROR: ${AUTO_COMPOSE_DIR}/ has local tracked changes; commit or stash before apply" >&2
  echo "${dirty}" >&2
  exit 1
fi

if [[ "${SKIP_PULL}" != "1" ]]; then
  git pull --ff-only
fi

read_env_value() {
  local file="$1"
  local name="$2"
  local value
  value="$(grep -E "^${name}=" "${file}" | tail -n1 | cut -d= -f2- || true)"
  if [[ -z "${value}" ]]; then
    echo "ERROR: ${name} not set in ${file}" >&2
    return 1
  fi
  printf '%s' "${value}"
}

sync_pin() {
  local file="$1"
  local name="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v name="${name}" -v value="${value}" '
    BEGIN { done = 0 }
    $0 ~ "^" name "=" { print name "=" value; done = 1; next }
    { print }
    END { if (!done) print name "=" value }
  ' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

HEALTH_BIND_VAR=""
HEALTH_PORT_VAR=""
HEALTH_PATH=""

COMPOSE_BUILD=0
for pin_id in "${TARGET_IDS[@]}"; do
  unset AUTO_IMAGE_TAG_FROM AUTO_CHAIN_LINKS AUTO_EXCLUDE \
    AUTO_HEALTH_PATH AUTO_HEALTH_PORT_VAR AUTO_HEALTH_BIND_VAR \
    AUTO_STRIP_GIT_PREFIX AUTO_APPLY_GROUP AUTO_IMAGE_TAG_SUFFIX \
    AUTO_COMPOSE_BUILD
  # shellcheck disable=SC1090
  eval "$(python3 "${YAML_PY}" --file "${YAML_FILE}" export "${pin_id}")"
  if [[ "${AUTO_COMPOSE_BUILD:-}" == "true" ]]; then
    COMPOSE_BUILD=1
  fi

  NEW_PIN="$(read_env_value "${ENV_TEMPLATE}" "${AUTO_VAR}")"
  OLD_PIN="$(grep -E "^${AUTO_VAR}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- || true)"
  sync_pin "${ENV_FILE}" "${AUTO_VAR}" "${NEW_PIN}"

  echo "${pin_id}: ${AUTO_VAR}"
  echo "  was: ${OLD_PIN:-<unset>}"
  echo "  now: ${NEW_PIN}"

  if [[ -n "${AUTO_HEALTH_PATH:-}" && -z "${HEALTH_PATH}" ]]; then
    HEALTH_PATH="${AUTO_HEALTH_PATH}"
    HEALTH_PORT_VAR="${AUTO_HEALTH_PORT_VAR:-}"
    HEALTH_BIND_VAR="${AUTO_HEALTH_BIND_VAR:-RPC_BIND_ADDR}"
  fi
done

if [[ "${SKIP_COMPOSE}" == "1" ]]; then
  echo "SKIP_COMPOSE=1 — not running docker compose"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: required command not found: curl" >&2
  exit 1
fi

(
  cd "${COMPOSE_DIR}"
  if [[ "${COMPOSE_BUILD}" -eq 1 ]]; then
    docker compose up -d --build
  else
    docker compose pull
    docker compose up -d
  fi
)

if [[ -z "${HEALTH_PATH}" || -z "${HEALTH_PORT_VAR}" ]]; then
  echo "No health check configured for ${CHAIN_ID}."
  exit 0
fi

health_bind="$(read_env_value "${ENV_FILE}" "${HEALTH_BIND_VAR}" || true)"
health_port="$(read_env_value "${ENV_FILE}" "${HEALTH_PORT_VAR}" || true)"

if [[ -z "${health_port}" ]]; then
  echo "No health check configured for ${CHAIN_ID}."
  exit 0
fi

if [[ "${health_bind}" == "0.0.0.0" || -z "${health_bind}" ]]; then
  health_bind="127.0.0.1"
fi

url="http://${health_bind}:${health_port}${HEALTH_PATH}"
echo "Waiting for ${url} (timeout ${HEALTH_TIMEOUT}s)"

deadline=$((SECONDS + HEALTH_TIMEOUT))
while (( SECONDS < deadline )); do
  if curl -fsS --connect-timeout 2 --max-time 5 "${url}" >/dev/null 2>&1; then
    echo "Healthy: ${url}"
    exit 0
  fi
  sleep 5
done

echo "ERROR: ${CHAIN_ID} did not become healthy at ${url} within ${HEALTH_TIMEOUT}s" >&2
exit 1
