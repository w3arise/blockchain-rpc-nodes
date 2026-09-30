#!/usr/bin/env bash
#
# Restore the official Mantle mainnet full (hash-full) op-geth snapshot.
# Skip genesis init after a successful restore — start with docker compose up -d.
#
# Source: https://s3.ap-southeast-1.amazonaws.com/snapshot.mantle.xyz/
# Object: ${DATE}-mainnet-full-chaindata.tar.zst (DATE from current.info)
#
# Requires: tar, zstd (or unzstd); sha256sum; aria2c (preferred) or curl
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

env_get() {
  local key="$1"
  local default="$2"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    local val
    val="$(grep -E "^${key}=" "${ENV_FILE}" | cut -d= -f2-)"
    val="${val/\$HOME/$HOME}"
    echo "${val}"
    return
  fi
  echo "${default}"
}

DATA_DIR="$(env_get HOST_DATADIR "${HOME}/mantle-op-geth-data")"
SNAP_BASE="${SNAPSHOT_BASE:-https://s3.ap-southeast-1.amazonaws.com/snapshot.mantle.xyz}"

command -v tar >/dev/null 2>&1 || {
  echo "ERROR: 'tar' is required." >&2
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

if [[ -d "${DATA_DIR}/geth/chaindata" || -d "${DATA_DIR}/chaindata" ]]; then
  echo "ERROR: ${DATA_DIR} already contains chaindata; refuse to overwrite" >&2
  echo "Remove it first if you intend to restore from snapshot." >&2
  exit 1
fi

DATE="$(curl -fsSL "${SNAP_BASE}/current.info" | tr -d '[:space:]')"
if [[ -z "${DATE}" ]]; then
  echo "ERROR: failed to read ${SNAP_BASE}/current.info" >&2
  exit 1
fi

OBJECT="${DATE}-mainnet-full-chaindata.tar.zst"
URL="${SNAP_BASE}/${OBJECT}"
# Official docs publish .sha256sum for archive (*-mainnet-chaindata.tar.zst) only.
# The full snapshot sidecar is missing; S3 then returns 403 AccessDenied (not 404).
CHECKSUM_URL="${URL}.sha256sum"

mkdir -p "${DATA_DIR}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/mantle-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
ARCHIVE="${TMP_BASE}/${OBJECT}"
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
echo "using staging dir ${TMP_BASE}"

echo "downloading ${URL} ..."
download "${URL}" "${ARCHIVE}"
alert_kept_snapshot

if curl -fsSL -o "${TMP_BASE}/${OBJECT}.sha256sum" "${CHECKSUM_URL}"; then
  EXPECTED="$(awk '{print $1}' "${TMP_BASE}/${OBJECT}.sha256sum")"
  echo "verifying sha256 (${EXPECTED}) ..."
  (
    cd "${TMP_BASE}"
    echo "${EXPECTED}  ${OBJECT}" | sha256sum -c -
  )
else
  echo "WARNING: no checksum at ${CHECKSUM_URL} (HTTP 403/404); continuing without verify" >&2
fi
mkdir -p "${EXTRACT}"
echo "extracting into ${EXTRACT} ..."
if command -v unzstd >/dev/null 2>&1; then
  tar --use-compress-program=unzstd -xf "${ARCHIVE}" -C "${EXTRACT}"
else
  tar --use-compress-program=zstd -xf "${ARCHIVE}" -C "${EXTRACT}"
fi

# Official layout is chaindata at the tarball root (mounted as datadir/geth/).
SRC=""
if [[ -d "${EXTRACT}/geth/chaindata" ]]; then
  SRC="${EXTRACT}"
elif [[ -d "${EXTRACT}/chaindata" ]]; then
  SRC="${EXTRACT}"
else
  top_count=0
  top_dir=""
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/geth/chaindata" ]]; then
    SRC="${top_dir}"
  elif [[ "${top_count}" -eq 1 && -d "${top_dir}/chaindata" ]]; then
    SRC="${top_dir}"
  fi
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: could not find chaindata in snapshot archive. Contents:" >&2
  find "${EXTRACT}" -maxdepth 3 -type d >&2
  exit 1
fi

# Rename the unpacked tree into the datadir (same filesystem = no extra copy).
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
  echo "moving ${src} -> ${dest}"
  mv "${src}" "${dest}"
}

echo "installing chaindata into ${DATA_DIR}"
if [[ -d "${SRC}/geth/chaindata" ]]; then
  move_into "${SRC}" "${DATA_DIR}"
else
  move_into "${SRC}" "${DATA_DIR}/geth"
fi

if [[ ! -d "${DATA_DIR}/geth/chaindata" ]]; then
  echo "ERROR: restore did not produce ${DATA_DIR}/geth/chaindata" >&2
  exit 1
fi

echo "restored full snapshot to ${DATA_DIR}"
echo "Keep GC_MODE=full, then: docker compose up -d"
alert_kept_snapshot
