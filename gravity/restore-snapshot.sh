#!/usr/bin/env bash
#
# Download the public Gravity mainnet PFN snapshot and move the chain
# databases into HOST_DATADIR. The archive is kept on disk.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/gravity-data}"
STORAGE="${DATA_DIR}/data"
SNAPSHOT_URL="${SNAPSHOT_URL:-https://gravity-snapshots.b-cdn.net/gravity-mainnet-data/latest.tar}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/gravity-snapshot-tmp}"
ARCHIVE="${TMP_BASE}/latest.tar"
EXTRACT="${TMP_BASE}/extract"

mkdir -p "${TMP_BASE}" "${STORAGE}"

alert_kept_snapshot() {
  echo "WARNING: snapshot archive is left on disk. Remove it yourself when you no longer need it." >&2
  echo "         archive: ${ARCHIVE}" >&2
  if [[ -e "${ARCHIVE}" ]]; then
    echo "         size: $(du -sh "${ARCHIVE}" | awk '{print $1}')" >&2
  fi
}

if [[ -d "${STORAGE}/reth" || -d "${STORAGE}/consensus_db" || -d "${STORAGE}/quorumstoreDB" ]]; then
  echo "ERROR: ${STORAGE} already has chain databases." >&2
  echo "       Stop the node and move that directory aside before restoring." >&2
  exit 1
fi

if [[ -e "${ARCHIVE}" ]]; then
  echo "WARNING: reusing existing archive."
  echo "         path: ${ARCHIVE}"
  echo "         size: $(du -sh "${ARCHIVE}" | awk '{print $1}')"
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
    echo "aria2c not found; falling back to curl (install aria2 for a large resume)" >&2
    curl -fL --retry 5 -C - --progress-bar -o "${out}" "${url}"
  fi
}

echo "==> Downloading ${SNAPSHOT_URL}"
echo "    staging: ${ARCHIVE}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"
alert_kept_snapshot

DATA_DEV="$(stat -c '%d' "${DATA_DIR}")"
TMP_DEV="$(stat -c '%d' "${TMP_BASE}")"
if [[ "${DATA_DEV}" != "${TMP_DEV}" ]]; then
  echo "WARNING: snapshot staging and HOST_DATADIR are on different filesystems." >&2
  echo "         mv will copy the extracted databases instead of renaming them." >&2
fi

rm -rf "${EXTRACT}"
mkdir -p "${EXTRACT}"
echo "==> Extracting into ${EXTRACT}"
tar -xf "${ARCHIVE}" -C "${EXTRACT}"

for dir in consensus_db quorumstoreDB reth; do
  if [[ ! -d "${EXTRACT}/${dir}" ]]; then
    echo "ERROR: snapshot is missing ${dir}/ at the archive root" >&2
    alert_kept_snapshot
    exit 1
  fi
done

echo "==> Moving databases into ${STORAGE}"
mv "${EXTRACT}/consensus_db" "${EXTRACT}/quorumstoreDB" "${EXTRACT}/reth" "${STORAGE}/"
rmdir "${EXTRACT}" 2>/dev/null || true

alert_kept_snapshot
echo ""
echo "Snapshot databases are in ${STORAGE}."
echo "The container runs as uid 10001. Before start:"
echo "  sudo chown -R 10001:10001 \"${DATA_DIR}\""
echo ""
echo "Docs do not say whether this cut is archive or --full."
echo "This repo starts archive mode (receipts/logs kept, state history pruned)."
echo "A snapshot that was already pruned cannot grow receipts back."
echo ""
echo "Next: docker compose up -d"
