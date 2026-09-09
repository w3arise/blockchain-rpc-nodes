#!/usr/bin/env bash
#
# Compare tag-only allowlisted pins (scripts/auto-upgrade.yaml) to upstream
# and optionally write same-series image bumps.
#
# Usage:
#   ./scripts/check-auto-upgrades.sh           # report only (exit 1 if bumps exist)
#   ./scripts/check-auto-upgrades.sh --write   # bump env.template (+ CHAIN_LINKS)
#
# Auto only follows the currently pinned major.minor series. Crossing a
# minor/major line is always needs-review.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
YAML_PY="${SCRIPT_DIR}/lib/auto-upgrade-yaml.py"
YAML_FILE="${SCRIPT_DIR}/auto-upgrade.yaml"
CHAIN_LINKS="${REPO_ROOT}/CHAIN_LINKS.md"

WRITE=0
if [[ "${1:-}" == "--write" ]]; then
  WRITE=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--write]" >&2
  exit 2
fi

cd "${REPO_ROOT}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

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

set_env_value() {
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

image_tag() {
  local image="$1"
  local prefix="$2"
  if [[ "${image}" != "${prefix}"* ]]; then
    echo "ERROR: image ${image} does not start with ${prefix}" >&2
    return 1
  fi
  printf '%s' "${image#"${prefix}"}"
}

fetch_tags() {
  local repo="$1"
  local prefix="$2"
  git ls-remote --tags "https://github.com/${repo}.git" "refs/tags/${prefix}*" \
    | awk '{ print $2 }' \
    | sed 's#^refs/tags/##' \
    | grep -v '\^{}$' \
    | sed 's/\^{}$//'
}

version_lt() {
  local left="$1"
  local right="$2"
  [[ "${left}" != "${right}" && "${left}" == "$(printf '%s\n' "${left}" "${right}" | sort -V | head -n1)" ]]
}

update_chain_links() {
  local old_tag="$1"
  local new_tag="$2"
  local tag_prefix="$3"
  python3 - "${CHAIN_LINKS}" "${old_tag}" "${new_tag}" "${tag_prefix}" <<'PY'
from pathlib import Path
import sys

path, old_tag, new_tag, tag_prefix = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text()
if old_tag not in text:
    sys.exit(0)
text = text.replace(old_tag, new_tag)
old_pretty = None
if tag_prefix and old_tag.startswith(tag_prefix):
    old_pretty = "v" + old_tag[len(tag_prefix):]
    new_pretty = "v" + new_tag[len(tag_prefix):]
    if old_pretty != new_pretty:
        text = text.replace(old_pretty, new_pretty)
path.write_text(text)
PY
}

restore_write() {
  local env_file="$1"
  local chain_links_enabled="$2"
  git checkout -- "${env_file}"
  if [[ "${chain_links_enabled}" == "true" ]]; then
    git checkout -- CHAIN_LINKS.md 2>/dev/null || true
  fi
}

fail_closed() {
  local env_file="$1"
  local var="$2"
  local chain_links_enabled="$3"
  local before_files="$4"

  local extra unexpected=""
  extra="$(comm -13 <(printf '%s\n' "${before_files}" | grep -v '^$' | sort -u) <(git diff --name-only | sort -u) || true)"

  local allowed="${env_file}"
  if [[ "${chain_links_enabled}" == "true" ]]; then
    allowed+=$'\n'"CHAIN_LINKS.md"
  fi

  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    if ! grep -qxF "${f}" <<< "${allowed}"; then
      unexpected+=" ${f}"
    fi
  done <<< "${extra}"

  if [[ -n "${unexpected}" ]]; then
    echo "ERROR: fail closed — unexpected files changed:${unexpected}" >&2
    restore_write "${env_file}" "${chain_links_enabled}"
    return 1
  fi

  if git diff --name-only -- "${env_file}" | grep -q .; then
    local env_diff
    env_diff="$(git diff -U0 -- "${env_file}" | grep -E '^[-+]' | grep -vE '^[-+]{3}' || true)"
    if [[ -z "${env_diff}" ]]; then
      echo "ERROR: fail closed — ${env_file} changed but the pin line is empty" >&2
      restore_write "${env_file}" "${chain_links_enabled}"
      return 1
    fi
    if grep -vE "^[-+]${var}=" <<< "${env_diff}" | grep -q .; then
      echo "ERROR: fail closed — ${env_file} changed more than ${var}" >&2
      echo "${env_diff}" >&2
      restore_write "${env_file}" "${chain_links_enabled}"
      return 1
    fi
  fi
}

require_command git
require_command python3
require_command awk
require_command sort

if [[ ! -f "${YAML_FILE}" ]]; then
  echo "ERROR: missing ${YAML_FILE}" >&2
  exit 1
fi

mapfile -t CHAIN_IDS < <(python3 "${YAML_PY}" --file "${YAML_FILE}" list)
if [[ "${#CHAIN_IDS[@]}" -eq 0 ]]; then
  echo "No tag-only chains in ${YAML_FILE}"
  exit 0
fi

BEFORE_FILES="$(git diff --name-only || true)"
BUMPS=0
SUMMARY=()

echo "Tag-only auto-upgrade check (same-series only)"
echo

for chain_id in "${CHAIN_IDS[@]}"; do
  # shellcheck disable=SC1090
  eval "$(python3 "${YAML_PY}" --file "${YAML_FILE}" export "${chain_id}")"

  env_path="${REPO_ROOT}/${AUTO_ENV_FILE}"
  current_image="$(read_env_value "${env_path}" "${AUTO_VAR}")"
  current_tag="$(image_tag "${current_image}" "${AUTO_IMAGE_PREFIX}")"
  series="$(python3 "${YAML_PY}" series "${current_tag}")"

  echo "${chain_id}:"
  echo "  pin:    ${current_image}"
  echo "  series: ${series}.*"

  if [[ "${AUTO_SOURCE_TYPE}" != "github_releases" ]]; then
    echo "ERROR: unsupported source_type ${AUTO_SOURCE_TYPE} for ${chain_id}" >&2
    exit 1
  fi

  tags_raw="$(fetch_tags "${AUTO_SOURCE_REPO}" "${AUTO_TAG_PREFIX}")" || {
    echo "ERROR: failed to list tags from ${AUTO_SOURCE_REPO}" >&2
    exit 1
  }
  mapfile -t tags < <(
    printf '%s\n' "${tags_raw}" \
      | python3 "${YAML_PY}" filter-series --current "${current_tag}" --exclude="${AUTO_EXCLUDE:-}" \
      | sort -V
  )
  if [[ "${#tags[@]}" -eq 0 ]]; then
    echo "ERROR: no same-series tags for ${chain_id} from ${AUTO_SOURCE_REPO}" >&2
    exit 1
  fi

  latest_tag="${tags[-1]}"
  latest_image="${AUTO_IMAGE_PREFIX}${latest_tag}"

  if [[ "${current_tag}" == "${latest_tag}" ]]; then
    echo "  latest: ${latest_image}  (ok)"
    echo
    continue
  fi

  if ! version_lt "${current_tag}" "${latest_tag}"; then
    echo "  latest: ${latest_image}  (pinned is not older — skipping write)"
    echo
    continue
  fi

  echo "  latest: ${latest_image}  (upgrade available)"
  echo
  BUMPS=$((BUMPS + 1))
  SUMMARY+=("${chain_id}: ${current_tag} -> ${latest_tag}")

  if [[ "${WRITE}" -eq 1 ]]; then
    set_env_value "${env_path}" "${AUTO_VAR}" "${latest_image}"
    if [[ "${AUTO_CHAIN_LINKS:-false}" == "true" ]]; then
      update_chain_links "${current_tag}" "${latest_tag}" "${AUTO_TAG_PREFIX}"
    fi
    fail_closed "${AUTO_ENV_FILE}" "${AUTO_VAR}" "${AUTO_CHAIN_LINKS:-false}" "${BEFORE_FILES}"
    BEFORE_FILES="$(git diff --name-only || true)"
  fi
done

if [[ "${BUMPS}" -eq 0 ]]; then
  echo "Pinned tag-only versions match the latest same-series upstream tags."
  exit 0
fi

echo "Upgrades:"
for line in "${SUMMARY[@]}"; do
  echo "  ${line}"
done

if [[ "${WRITE}" -eq 0 ]]; then
  echo
  echo "Re-run with --write to bump env.template (and CHAIN_LINKS.md when listed)."
  exit 1
fi

echo
echo "Wrote ${BUMPS} tag-only pin bump(s)."
exit 0
