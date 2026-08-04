#!/usr/bin/env bash
#
# Download and restore the latest Liquify Zircuit mainnet l2-geth snapshot.
#
# Requires: lz4, tar; aria2c (preferred) or curl; sha256sum or shasum
#
# Usage: ./restore-snapshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

DATA_DIR="${HOST_DATADIR:-${HOME}/zircuit-l2-geth-data}"
DATA_DIR="${DATA_DIR/\$HOME/$HOME}"
SNAPSHOT_BASE="${SNAPSHOT_BASE:-https://zircuit-snapshot.liquify.com/files/mainnet}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/zircuit-snapshot-tmp}"
TMP_BASE="${TMP_BASE/\$HOME/$HOME}"

for tool in lz4 tar; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

if [[ -n "$(ls -A "${DATA_DIR}" 2>/dev/null || true)" ]]; then
  echo "ERROR: ${DATA_DIR} is not empty; refuse to overwrite" >&2
  echo "Remove existing data first if you intend to restore from snapshot." >&2
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

verify_sha256() {
  local archive="$1"
  local checksum_file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${checksum_file}"
  else
    shasum -a 256 -c "${checksum_file}"
  fi
}

echo "==> Resolving latest snapshot from ${SNAPSHOT_BASE}"
SNAPSHOT_NAME="$(curl -fsSL "${SNAPSHOT_BASE}/latest_compressed_zircuit.txt" | tr -d '[:space:]')"
if [[ -z "${SNAPSHOT_NAME}" ]]; then
  echo "ERROR: failed to read latest snapshot name" >&2
  exit 1
fi

SNAPSHOT_URL="${SNAPSHOT_BASE}/${SNAPSHOT_NAME}"
CHECKSUM_URL="${SNAPSHOT_URL}.sha256"

mkdir -p "${DATA_DIR}" "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

ARCHIVE="${TMP_DIR}/${SNAPSHOT_NAME}"
CHECKSUM_FILE="${TMP_DIR}/${SNAPSHOT_NAME}.sha256"

echo "==> Downloading ${SNAPSHOT_NAME}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"
download "${CHECKSUM_URL}" "${CHECKSUM_FILE}"

echo "==> Verifying sha256"
(
  cd "${TMP_DIR}"
  verify_sha256 "${ARCHIVE}" "$(basename "${CHECKSUM_FILE}")"
)

EXTRACT="${TMP_DIR}/extract"
mkdir -p "${EXTRACT}"
echo "==> Extracting snapshot"
lz4 -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"

SRC=""
if [[ -d "${EXTRACT}/geth" ]]; then
  SRC="${EXTRACT}"
elif [[ -d "${EXTRACT}/l2-replica-data" ]]; then
  SRC="${EXTRACT}/l2-replica-data"
else
  top_count=0
  top_dir=""
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/geth" ]]; then
    SRC="${top_dir}"
  fi
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: could not find geth datadir layout in snapshot. Top-level contents:" >&2
  ls -la "${EXTRACT}" >&2
  exit 1
fi

echo "==> Installing chain data into ${DATA_DIR}"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "${SRC}/" "${DATA_DIR}/"
else
  cp -a "${SRC}/." "${DATA_DIR}/"
fi

echo ""
echo "Snapshot restore finished. Start the node with:"
echo "  docker compose up -d"
