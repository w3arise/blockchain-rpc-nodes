#!/usr/bin/env bash
#
# Download and restore the official Core mainnet pruned (state) snapshot.
# This is hash-full chaindata: blocks/receipts/logs retained; state pruned.
# Skip ./init-database.sh after a successful restore.
#
# Requires: tar, lz4 (or tar with -I lz4), md5sum/md5; aria2c (preferred) or curl
#
# Usage: ./restore-snapshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/core-data}"
SNAPSHOT_URL="${SNAPSHOT_URL:?SNAPSHOT_URL must be set in .env}"
SNAPSHOT_MD5="${SNAPSHOT_MD5:-}"

command -v tar >/dev/null 2>&1 || {
  echo "ERROR: 'tar' is required." >&2
  exit 1
}

download() {
  local url="$1"
  local out="$2"
  if command -v aria2c >/dev/null 2>&1; then
    # Prefer aria2c for large snapshots (multi-connection, resume).
    aria2c --max-tries=0 -x 16 -s 16 -k 100M -c \
      --dir="$(dirname "${out}")" \
      --out="$(basename "${out}")" \
      "${url}"
  else
    echo "aria2c not found; falling back to curl (install aria2 for faster downloads)" >&2
    command -v curl >/dev/null 2>&1 || {
      echo "ERROR: neither aria2c nor curl is available." >&2
      exit 1
    }
    curl -fL --retry 3 -C - --progress-bar -o "${out}" "${url}"
  fi
}

if [[ -d "${DATA_DIR}/geth" ]]; then
  echo "WARNING: ${DATA_DIR} already contains a geth database."
  read -r -p "Wipe and restore snapshot? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"
# Keep download/extract off /tmp (usually the small OS partition). Prefer home disk space.
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/core-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
ARCHIVE="${TMP_BASE}/$(basename "${SNAPSHOT_URL}")"
EXTRACT="${TMP_BASE}/extract"

alert_kept_snapshot() {
  echo "WARNING: snapshot files are never deleted by this script." >&2
  echo "         archive: ${ARCHIVE}" >&2
  if [[ -e "${ARCHIVE}" ]]; then
    echo "         size: $(du -sh "${ARCHIVE}" | awk '{print $1}')" >&2
  fi
  echo "         staging: ${TMP_BASE}" >&2
  echo "         Remove that path yourself when you no longer need the tarball." >&2
}

if [[ -e "${ARCHIVE}" ]]; then
  echo "WARNING: existing snapshot archive will be reused (aria2c -c resumes if incomplete)." >&2
  alert_kept_snapshot
fi
echo "==> Using staging dir ${TMP_BASE}"

echo "==> Downloading ${SNAPSHOT_URL}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"
alert_kept_snapshot

if [[ -n "${SNAPSHOT_MD5}" ]]; then
  echo "==> Verifying MD5 ${SNAPSHOT_MD5}"
  if command -v md5sum >/dev/null 2>&1; then
    echo "${SNAPSHOT_MD5}  ${ARCHIVE}" | md5sum -c -
  elif command -v md5 >/dev/null 2>&1; then
    GOT="$(md5 -q "${ARCHIVE}")"
    if [[ "${GOT}" != "${SNAPSHOT_MD5}" ]]; then
      echo "ERROR: MD5 mismatch (got ${GOT})" >&2
      exit 1
    fi
  else
    echo "WARNING: no md5sum/md5 — skipping checksum"
  fi
fi

EXTRACT="${TMP_BASE}/extract"
mkdir -p "${EXTRACT}"
echo "==> Extracting into ${EXTRACT}"
if command -v lz4 >/dev/null 2>&1; then
  lz4 -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"
else
  tar -I lz4 -xf "${ARCHIVE}" -C "${EXTRACT}"
fi

# Normalize layout: expect geth/ under DATA_DIR
SRC=""
if [[ -d "${EXTRACT}/geth" ]]; then
  SRC="${EXTRACT}"
elif [[ -d "${EXTRACT}/node/geth" ]]; then
  SRC="${EXTRACT}/node"
else
  # single top-level directory?
  top_count=0
  top_dir=""
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/geth" ]]; then
    SRC="${top_dir}"
  elif [[ "${top_count}" -eq 1 && -d "${top_dir}/node/geth" ]]; then
    SRC="${top_dir}/node"
  fi
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: could not find geth/ in snapshot archive. Contents:" >&2
  find "${EXTRACT}" -maxdepth 3 -type d >&2
  exit 1
fi

move_into() {
  local src="$1"
  local dest="$2"
  local dest_parent
  dest_parent="$(dirname "${dest}")"
  mkdir -p "${dest_parent}"
  if [[ -d "${dest}" ]]; then
    if [[ -n "$(ls -A "${dest}" 2>/dev/null)" ]]; then
      echo "ERROR: ${dest} is not empty; refuse to overwrite" >&2
      exit 1
    fi
    rmdir "${dest}"
  fi
  if [[ "$(stat -c '%d' "${src}")" != "$(stat -c '%d' "${dest_parent}")" ]]; then
    echo "WARNING: ${src} and ${dest} are on different filesystems; move will copy and needs extra space." >&2
  fi
  echo "==> Moving ${src} -> ${dest}"
  mv "${src}" "${dest}"
}

echo "==> Installing chaindata into ${DATA_DIR}"
move_into "${SRC}" "${DATA_DIR}"

echo ""
echo "==> Snapshot restore complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
echo "Do not run ./init-database.sh against this datadir."
alert_kept_snapshot
