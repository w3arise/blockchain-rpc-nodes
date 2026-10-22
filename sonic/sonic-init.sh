#!/usr/bin/env bash
#
# Download the genesis file (when needed) and prime the Sonic state DB.
# Usage: ./sonic-init.sh [path/to/sonic.g]
#
# With no argument, downloads GENESIS_URL from .env (default: pruned mainnet).
# An existing chaindata + carmen datadir is left unchanged: no download, no import.
# A path argument uses that local file and does not contact the genesis host.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_GENESIS_URL="https://genesis.soniclabs.com/latest-sonic-pruned.g"

sed_inplace() {
  local expr="$1"
  local file="$2"
  local tmp
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "${tmp}"
  mv "${tmp}" "${file}"
}

set_env_value() {
  local name="$1"
  local value="$2"
  if [[ ! -f "${ENV_FILE}" ]]; then
    return 0
  fi
  if grep -qE "^${name}=" "${ENV_FILE}"; then
    sed_inplace "s|^${name}=.*|${name}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${name}" "${value}" >> "${ENV_FILE}"
  fi
}

alert_kept_genesis() {
  if [[ -z "${ARCHIVE:-}" ]]; then
    return 0
  fi
  echo "WARNING: genesis archive is never deleted by this script." >&2
  echo "         path: ${ARCHIVE}" >&2
  if [[ -e "${ARCHIVE}" ]]; then
    echo "         size: $(du -sh "${ARCHIVE}" | awk '{print $1}')" >&2
  fi
  echo "         staging: ${TMP_BASE:-}" >&2
  echo "         Remove that path yourself when you no longer need the file." >&2
  return 0
}

download() {
  local url="$1"
  local out="$2"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c --max-tries=0 -x 16 -s 16 -k 100M -c \
      --auto-file-renaming=false \
      --dir="$(dirname "${out}")" \
      --out="$(basename "${out}")" \
      "${url}"
  else
    echo "aria2c not found; falling back to curl (install aria2 for faster downloads)" >&2
    curl -fL --retry 3 -C - --progress-bar -o "${out}" "${url}"
  fi
}

file_size() {
  stat -c '%s' "$1"
}

# Size matches the resolved object, and the official MD5 matches (cached after
# the first successful check). A short file is incomplete, not a match.
genesis_ready() {
  local file="$1"
  local stamp size
  [[ -f "${file}" ]] || return 1
  [[ -n "${REMOTE_SIZE}" ]] || return 1
  size="$(file_size "${file}")"
  [[ "${size}" == "${REMOTE_SIZE}" ]] || return 1
  if [[ -z "${EXPECTED_MD5}" ]]; then
    return 0
  fi
  stamp="${file}.md5ok"
  if [[ -f "${stamp}" ]] && [[ "$(tr -d '[:space:]' < "${stamp}")" == "${EXPECTED_MD5}" ]]; then
    return 0
  fi
  if ! command -v md5sum >/dev/null 2>&1; then
    echo "WARNING: no md5sum — skipping checksum for ${file}" >&2
    return 0
  fi
  echo "==> Verifying MD5 ${EXPECTED_MD5}"
  if echo "${EXPECTED_MD5}  ${file}" | md5sum -c -; then
    printf '%s\n' "${EXPECTED_MD5}" > "${stamp}"
    return 0
  fi
  return 1
}

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

SONIC_VERSION="${SONIC_VERSION:-2.2.0}"
HOST_DATADIR="${HOST_DATADIR:-$HOME/sonic-data}"
GOMEMLIMIT_RUN="${GOMEMLIMIT:-28GiB}"
CACHE_MB_RUN="${CACHE_MB:-16000}"

mkdir -p "${HOST_DATADIR}"

# sonictool treats chaindata and carmen together as an initialized database
# and refuses to import over them. Match that so a repeat init does not fetch.
if [[ -d "${HOST_DATADIR}/chaindata" && -d "${HOST_DATADIR}/carmen" ]]; then
  if [[ -e "${HOST_DATADIR}/chaindata/unfinished" ]]; then
    echo "ERROR: genesis import is unfinished in ${HOST_DATADIR}" >&2
    echo "       chaindata and carmen were left in place. No genesis file was downloaded." >&2
    echo "       Remove those two directories, then rerun ./sonic-init.sh" >&2
    exit 1
  fi
  echo "datadir already initialized at ${HOST_DATADIR} (skipping genesis download and import)"
  exit 0
fi

if [[ $# -ge 1 ]]; then
  GENESIS_FILE_INPUT="$1"
  if [[ ! -f "${GENESIS_FILE_INPUT}" ]]; then
    echo "ERROR: Genesis file not found at: ${GENESIS_FILE_INPUT}" >&2
    echo "Usage: $0 [path/to/sonic.g]" >&2
    exit 1
  fi
  GENESIS_FILE_ABS_DIR="$(cd "$(dirname "${GENESIS_FILE_INPUT}")" && pwd)"
  GENESIS_FILE_ABS="${GENESIS_FILE_ABS_DIR}/$(basename "${GENESIS_FILE_INPUT}")"
else
  GENESIS_URL="${GENESIS_URL:-${DEFAULT_GENESIS_URL}}"
  TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/sonic-snapshot-tmp}"
  mkdir -p "${TMP_BASE}"

  if [[ "$(stat -c '%d' "${TMP_BASE}")" != "$(stat -c '%d' "${HOST_DATADIR}")" ]]; then
    echo "WARNING: staging ${TMP_BASE} and datadir ${HOST_DATADIR} are on different filesystems." >&2
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required." >&2
    exit 1
  }

  echo "==> Resolving ${GENESIS_URL}"
  HEADERS="$(curl -fsSI -L --retry 3 --max-redirs 10 "${GENESIS_URL}")"
  FINAL_URL="$(printf '%s\n' "${HEADERS}" | awk 'tolower($1)=="location:" {url=$2} END {gsub(/\r/,"",url); print url}')"
  REMOTE_SIZE="$(printf '%s\n' "${HEADERS}" | awk 'tolower($1)=="content-length:" {size=$2} END {gsub(/\r/,"",size); print size}')"
  if [[ -z "${FINAL_URL}" ]]; then
    FINAL_URL="${GENESIS_URL}"
  fi
  OBJECT="$(basename "${FINAL_URL%%\?*}")"
  if [[ -z "${OBJECT}" || "${OBJECT}" == "/" ]]; then
    echo "ERROR: could not determine genesis filename from ${FINAL_URL}" >&2
    exit 1
  fi

  ARCHIVE="${TMP_BASE}/${OBJECT}"
  trap 'alert_kept_genesis' EXIT

  if [[ -e "${ARCHIVE}" ]]; then
    echo "WARNING: existing genesis archive will be reused (aria2c -c resumes if incomplete)." >&2
    alert_kept_genesis
  fi

  MD5_TEXT="$(curl -fsSL --retry 3 "${GENESIS_URL}.md5")"
  EXPECTED_MD5="$(printf '%s\n' "${MD5_TEXT}" | awk -v obj="${OBJECT}" '
    NR==1 { first=$1 }
    $2==obj { print $1; found=1; exit }
    END { if (!found) print first }
  ')"
  if [[ -z "${EXPECTED_MD5}" ]]; then
    echo "ERROR: empty checksum from ${GENESIS_URL}.md5" >&2
    exit 1
  fi

  CHOSEN=""
  if genesis_ready "${ARCHIVE}"; then
    CHOSEN="${ARCHIVE}"
    echo "genesis already downloaded: ${CHOSEN}"
  elif [[ -f "${ARCHIVE}" ]]; then
    HAVE="$(file_size "${ARCHIVE}")"
    if [[ -n "${REMOTE_SIZE}" && "${HAVE}" -gt "${REMOTE_SIZE}" ]]; then
      echo "ERROR: ${ARCHIVE} is ${HAVE} bytes; latest object is ${REMOTE_SIZE} bytes." >&2
      echo "       The file was left in place. Remove it yourself, then rerun ./sonic-init.sh." >&2
      exit 1
    fi
    if [[ -n "${REMOTE_SIZE}" && "${HAVE}" == "${REMOTE_SIZE}" ]]; then
      echo "ERROR: MD5 mismatch for ${ARCHIVE} (expected ${EXPECTED_MD5})." >&2
      echo "       The file was left in place. Remove it yourself, then rerun ./sonic-init.sh." >&2
      exit 1
    fi
  elif [[ -f "${HOME}/sonic.g" ]] && genesis_ready "${HOME}/sonic.g"; then
    CHOSEN="${HOME}/sonic.g"
    ARCHIVE="${CHOSEN}"
    echo "reusing existing genesis ${CHOSEN}"
  elif [[ -s "${HOME}/sonic.g" ]]; then
    echo "WARNING: ${HOME}/sonic.g exists ($(du -sh "${HOME}/sonic.g" | awk '{print $1}')) and does not match the latest genesis; leaving it in place." >&2
  fi

  if [[ -z "${CHOSEN}" ]]; then
    echo "==> Downloading ${FINAL_URL}"
    echo "    destination: ${ARCHIVE}"
    download "${FINAL_URL}" "${ARCHIVE}"
    if ! genesis_ready "${ARCHIVE}"; then
      HAVE="0"
      if [[ -f "${ARCHIVE}" ]]; then
        HAVE="$(file_size "${ARCHIVE}")"
      fi
      if [[ -n "${REMOTE_SIZE}" && "${HAVE}" != "${REMOTE_SIZE}" ]]; then
        echo "ERROR: download incomplete for ${ARCHIVE} (${HAVE} of ${REMOTE_SIZE} bytes)." >&2
      else
        echo "ERROR: MD5 mismatch for ${ARCHIVE} (expected ${EXPECTED_MD5})." >&2
      fi
      echo "       The file was left in place. Remove it yourself, then rerun ./sonic-init.sh." >&2
      exit 1
    fi
    CHOSEN="${ARCHIVE}"
  fi

  set_env_value GENESIS_FILE "${CHOSEN}"
  GENESIS_FILE_ABS="${CHOSEN}"
  GENESIS_FILE_ABS_DIR="$(cd "$(dirname "${GENESIS_FILE_ABS}")" && pwd)"
  GENESIS_FILE_ABS="${GENESIS_FILE_ABS_DIR}/$(basename "${GENESIS_FILE_ABS}")"
fi

echo "Running sonic genesis with:"
echo "  Image:        sonic-node:${SONIC_VERSION}"
echo "  Host datadir: ${HOST_DATADIR}  (container: /data)"
echo "  GOMEMLIMIT:   ${GOMEMLIMIT_RUN}"
echo "  Cache (MB):   ${CACHE_MB_RUN}"
echo "  Genesis file: ${GENESIS_FILE_ABS}"
echo

docker run --rm -d \
  --entrypoint ./sonictool \
  --name sonic-init \
  -e "GOMEMLIMIT=${GOMEMLIMIT_RUN}" \
  -v "${HOST_DATADIR}:/data" \
  -v "${GENESIS_FILE_ABS_DIR}:/config:ro" \
  "sonic-node:${SONIC_VERSION}" \
  --datadir /data --cache "${CACHE_MB_RUN}" genesis "/config/$(basename "${GENESIS_FILE_ABS}")"

echo
echo "Genesis import is running in container sonic-init."
echo "Ctrl+C or closing this session only stops these logs. The import keeps running."
echo "Attach again with: docker logs -f sonic-init"
echo
docker logs -f --tail 100 sonic-init
