#!/usr/bin/env bash
#
# Download the newest OP Mainnet op-reth archive snapshot and install it
# into HOST_DATADIR. The tarball is the datadir (db/ at the archive root).
#
# Source: https://datadirs.optimism.io/
# Object: op-mainnet-reth-archive-storage-v2-YYYY-MM-DD.tar.zst
# The latest-* directory on that index returns 403; this script picks the
# newest dated archive file. Set SNAPSHOT_URL to pin one tarball.
#
# Requires: tar, zstd (or unzstd), sha256sum, curl; aria2c optional
#
# Usage: ./restore-snapshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
SNAP_BASE="https://datadirs.optimism.io"
ARCHIVE_RE='op-mainnet-reth-archive-storage-v2-[0-9]{4}-[0-9]{2}-[0-9]{2}\.tar\.zst'

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh first" >&2
  exit 1
fi

env_get() {
  local key="$1"
  local default="$2"
  local val
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    val="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2-)"
    val="${val%\"}"
    val="${val#\"}"
    val="${val/\$HOME/$HOME}"
    if [[ -n "${val}" ]]; then
      echo "${val}"
      return
    fi
  fi
  echo "${default}"
}

DATA_DIR="$(env_get HOST_DATADIR "${HOME}/optimism-op-reth-data")"
SNAPSHOT_URL="$(env_get SNAPSHOT_URL "")"
TMP_BASE="$(env_get SNAPSHOT_TMPDIR "${HOME}/optimism-snapshot-tmp")"

command -v tar >/dev/null 2>&1 || {
  echo "ERROR: 'tar' is required." >&2
  exit 1
}
command -v sha256sum >/dev/null 2>&1 || {
  echo "ERROR: 'sha256sum' is required." >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "ERROR: 'curl' is required." >&2
  exit 1
}
if ! command -v zstd >/dev/null 2>&1 && ! command -v unzstd >/dev/null 2>&1; then
  echo "ERROR: zstd (or unzstd) is required to extract the snapshot." >&2
  exit 1
fi

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

alert_kept_snapshot() {
  echo "WARNING: snapshot files are never deleted by this script." >&2
  if [[ -n "${ARCHIVE:-}" ]]; then
    echo "         archive: ${ARCHIVE}" >&2
    if [[ -e "${ARCHIVE}" ]]; then
      echo "         size: $(du -sh "${ARCHIVE}" | awk '{print $1}')" >&2
    fi
  fi
  echo "         staging: ${TMP_BASE}" >&2
  echo "         Remove that path yourself when you no longer need the tarball." >&2
}

# Set SRC to the directory that contains db/.
find_db_root() {
  SRC=""
  if [[ -d "${EXTRACT}/db" ]]; then
    SRC="${EXTRACT}"
    return 0
  fi
  local top_count=0
  local top_dir=""
  local d
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/db" ]]; then
    SRC="${top_dir}"
    return 0
  fi
  return 1
}

install_datadir() {
  local src="$1"
  local dest_parent
  mkdir -p "${DATA_DIR}"
  if [[ -n "$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "ERROR: ${DATA_DIR} is not empty; refuse to overwrite" >&2
    exit 1
  fi
  dest_parent="$(dirname "${DATA_DIR}")"
  mkdir -p "${dest_parent}"
  if [[ "$(stat -c '%d' "${src}")" != "$(stat -c '%d' "${dest_parent}")" ]]; then
    echo "WARNING: ${src} and ${DATA_DIR} are on different filesystems; move will copy and needs extra space." >&2
  fi
  echo "moving ${src} contents -> ${DATA_DIR}"
  find "${src}" -mindepth 1 -maxdepth 1 -exec mv -t "${DATA_DIR}" {} +
  if [[ ! -d "${DATA_DIR}/db" ]]; then
    echo "ERROR: restore did not produce ${DATA_DIR}/db" >&2
    exit 1
  fi
  echo "restored archive snapshot to ${DATA_DIR}"
  echo "Next: ./create-jwt.sh && docker compose up -d"
  alert_kept_snapshot
}

if [[ -d "${DATA_DIR}/db" ]]; then
  echo "datadir already initialized at ${DATA_DIR} (db/). Skipping download and extract."
  echo "Stop the client and remove that datadir's contents to restore a snapshot instead."
  exit 0
fi

if [[ -d "${DATA_DIR}" ]] && [[ -n "$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "ERROR: ${DATA_DIR} has no db/ but is not empty." >&2
  echo "Partial chain data stays on disk. Clear that directory and rerun." >&2
  echo "This script will not download a new archive on top of it." >&2
  exit 1
fi

mkdir -p "${TMP_BASE}"
EXTRACT="${TMP_BASE}/extract"

if [[ -d "${EXTRACT}" ]] && [[ -n "$(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  if find_db_root; then
    echo "reusing extracted snapshot at ${SRC} (not downloading another archive)"
    install_datadir "${SRC}"
    exit 0
  fi
  echo "ERROR: ${EXTRACT} is a partial extract." >&2
  echo "Remove that directory and rerun. The downloaded archive is kept." >&2
  exit 1
fi

if [[ -n "${SNAPSHOT_URL}" ]]; then
  URL="${SNAPSHOT_URL}"
  OBJECT="$(basename "${URL}")"
else
  echo "listing ${SNAP_BASE}/ ..."
  mapfile -t OBJECTS < <(
    curl -fsSL "${SNAP_BASE}/" \
      | grep -oE "href=\"${ARCHIVE_RE}\"" \
      | sed -E 's/^href="(.*)"$/\1/' \
      | sort -u
  )
  if [[ "${#OBJECTS[@]}" -eq 0 ]]; then
    echo "ERROR: no op-mainnet-reth-archive-storage-v2 tarball listed at ${SNAP_BASE}/" >&2
    exit 1
  fi
  OBJECT="${OBJECTS[-1]}"
  URL="${SNAP_BASE}/${OBJECT}"
fi

if [[ "${OBJECT}" != *.tar.zst ]]; then
  echo "ERROR: snapshot object must be a .tar.zst file, got ${OBJECT}" >&2
  exit 1
fi

ARCHIVE="${TMP_BASE}/${OBJECT}"
CHECKSUM_URL="${URL}.sha256sum"

if [[ -e "${ARCHIVE}" ]]; then
  echo "WARNING: existing snapshot archive will be reused (aria2c -c resumes if incomplete)." >&2
  alert_kept_snapshot
fi
echo "using staging dir ${TMP_BASE}"
echo "downloading ${URL} ..."
download "${URL}" "${ARCHIVE}"
alert_kept_snapshot

echo "downloading checksum ${CHECKSUM_URL} ..."
if ! curl -fsSL -o "${ARCHIVE}.sha256sum" "${CHECKSUM_URL}"; then
  echo "ERROR: failed to download checksum ${CHECKSUM_URL}" >&2
  alert_kept_snapshot
  exit 1
fi
EXPECTED="$(awk '{print $1}' "${ARCHIVE}.sha256sum")"
if [[ ! "${EXPECTED}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: checksum file did not contain a sha256" >&2
  alert_kept_snapshot
  exit 1
fi
echo "verifying sha256 (${EXPECTED}) ..."
if ! (
  cd "${TMP_BASE}"
  echo "${EXPECTED}  ${OBJECT}" | sha256sum -c -
); then
  echo "ERROR: checksum mismatch for ${ARCHIVE}" >&2
  echo "The archive was kept. Remove that file and rerun to download it again." >&2
  alert_kept_snapshot
  exit 1
fi

mkdir -p "${EXTRACT}"
echo "extracting into ${EXTRACT} ..."
if command -v unzstd >/dev/null 2>&1; then
  tar --use-compress-program=unzstd -xf "${ARCHIVE}" -C "${EXTRACT}"
else
  tar --use-compress-program=zstd -xf "${ARCHIVE}" -C "${EXTRACT}"
fi

if ! find_db_root; then
  echo "ERROR: could not find db/ in snapshot archive. Contents:" >&2
  find "${EXTRACT}" -maxdepth 2 \( -type d -o -type f \) >&2
  echo "Partial extract stays in ${EXTRACT}. Clear it after you no longer need it, then rerun." >&2
  alert_kept_snapshot
  exit 1
fi

install_datadir "${SRC}"
