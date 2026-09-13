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
CHECKSUM_URL="${URL}.sha256sum"

mkdir -p "${DATA_DIR}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/mantle-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT
echo "using temp dir ${TMP_DIR}"

echo "downloading ${URL} ..."
download "${URL}" "${TMP_DIR}/${OBJECT}"
curl -fsSL -o "${TMP_DIR}/${OBJECT}.sha256sum" "${CHECKSUM_URL}"

EXPECTED="$(awk '{print $1}' "${TMP_DIR}/${OBJECT}.sha256sum")"
echo "verifying sha256 (${EXPECTED}) ..."
(
  cd "${TMP_DIR}"
  echo "${EXPECTED}  ${OBJECT}" | sha256sum -c -
)

EXTRACT="${TMP_DIR}/extract"
mkdir -p "${EXTRACT}"
echo "extracting into ${EXTRACT} ..."
if command -v unzstd >/dev/null 2>&1; then
  tar --use-compress-program=unzstd -xf "${TMP_DIR}/${OBJECT}" -C "${EXTRACT}"
else
  tar --use-compress-program=zstd -xf "${TMP_DIR}/${OBJECT}" -C "${EXTRACT}"
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

echo "installing chaindata into ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
if [[ -d "${SRC}/geth/chaindata" ]]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${SRC}/" "${DATA_DIR}/"
  else
    cp -a "${SRC}/." "${DATA_DIR}/"
  fi
else
  mkdir -p "${DATA_DIR}/geth"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${SRC}/" "${DATA_DIR}/geth/"
  else
    cp -a "${SRC}/." "${DATA_DIR}/geth/"
  fi
fi

if [[ ! -d "${DATA_DIR}/geth/chaindata" ]]; then
  echo "ERROR: restore did not produce ${DATA_DIR}/geth/chaindata" >&2
  exit 1
fi

echo "restored full snapshot to ${DATA_DIR}"
echo "Keep GC_MODE=full, then: docker compose up -d"
