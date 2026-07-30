#!/usr/bin/env bash
#
# Download and restore the official XDC mainnet full-node snapshot (hash-full).
# Keeps blocks/receipts/logs; state is pruned (GC full). Skip ./init-database.sh after restore.
#
# Requires: tar; aria2c (preferred) or curl
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

DATA_DIR="${HOST_DATADIR:-${HOME}/xdc-data}"
SNAPSHOT_URL="${SNAPSHOT_URL:?SNAPSHOT_URL must be set in .env}"

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

if [[ -d "${DATA_DIR}/XDC/chaindata" ]]; then
  echo "WARNING: ${DATA_DIR} already contains an XDC database."
  read -r -p "Wipe and restore snapshot? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"
# Keep download/extract off /tmp (usually the small OS partition). Prefer home disk space.
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/xdc-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT
echo "==> Using temp dir ${TMP_DIR}"

ARCHIVE="${TMP_DIR}/snapshot.tar"
echo "==> Downloading ${SNAPSHOT_URL}"
echo "    (full snapshot is very large — hundreds of GB)"
download "${SNAPSHOT_URL}" "${ARCHIVE}"

EXTRACT="${TMP_DIR}/extract"
mkdir -p "${EXTRACT}"
echo "==> Extracting into ${EXTRACT}"
tar -xf "${ARCHIVE}" -C "${EXTRACT}"

# Normalize layout: expect XDC/ (with chaindata) under DATA_DIR
SRC=""
if [[ -d "${EXTRACT}/XDC/chaindata" ]]; then
  SRC="${EXTRACT}"
elif [[ -d "${EXTRACT}/xdcchain/XDC/chaindata" ]]; then
  SRC="${EXTRACT}/xdcchain"
else
  top_count=0
  top_dir=""
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/XDC/chaindata" ]]; then
    SRC="${top_dir}"
  elif [[ "${top_count}" -eq 1 && -d "${top_dir}/xdcchain/XDC/chaindata" ]]; then
    SRC="${top_dir}/xdcchain"
  fi
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: could not find XDC/chaindata in snapshot archive. Contents:" >&2
  find "${EXTRACT}" -maxdepth 4 -type d >&2
  exit 1
fi

echo "==> Installing chaindata into ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "${SRC}/" "${DATA_DIR}/"
else
  cp -a "${SRC}/." "${DATA_DIR}/"
fi

# Drop identity / pending tx leftovers from the snapshot (official restore steps)
rm -f "${DATA_DIR}/XDC/nodekey" "${DATA_DIR}/XDC/transactions.rlp" 2>/dev/null || true

echo ""
echo "==> Snapshot restore complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: docker compose up -d"
echo "Do not run ./init-database.sh against this datadir."
