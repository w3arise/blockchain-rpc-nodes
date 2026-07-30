#!/usr/bin/env bash
#
# Download and restore the official Core mainnet pruned (state) snapshot.
# This is hash-full chaindata: blocks/receipts/logs retained; state pruned.
# Skip ./init-database.sh after a successful restore.
#
# Requires: curl, tar, lz4 (or tar with -I lz4), md5sum/md5
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

for tool in curl tar; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

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
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT
echo "==> Using temp dir ${TMP_DIR}"

ARCHIVE="${TMP_DIR}/snapshot.tar.lz4"
echo "==> Downloading ${SNAPSHOT_URL}"
curl -fL --retry 3 -o "${ARCHIVE}" "${SNAPSHOT_URL}"

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

EXTRACT="${TMP_DIR}/extract"
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

echo "==> Installing chaindata into ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
# Prefer rsync if available (shows progress); else cp
if command -v rsync >/dev/null 2>&1; then
  rsync -a "${SRC}/" "${DATA_DIR}/"
else
  cp -a "${SRC}/." "${DATA_DIR}/"
fi

echo ""
echo "==> Snapshot restore complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
echo "Do not run ./init-database.sh against this datadir."
