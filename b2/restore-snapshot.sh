#!/usr/bin/env bash
#
# Restore a B² mainnet op-geth snapshot tarball into HOST_DATADIR.
# Skip ./init-database.sh after a successful restore.
#
# Usage:
#   ./restore-snapshot.sh           # uses GC_MODE from .env (archive → archive-data.tar.gz)
#   ./restore-snapshot.sh full      # db.tar.gz (~51 GiB compressed)
#   ./restore-snapshot.sh archive   # archive-data.tar.gz (~946 GiB compressed)
#
# Source: Tencent COS bucket b2-download-1318671312 (ap-singapore)
# Docs refresh snapshots Fridays; tarballs at bucket root may lag the recursive dir snapshots.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/b2-op-geth-data}"
DATA_DIR="${DATA_DIR/\$HOME/$HOME}"
KIND="${1:-}"
if [[ -z "${KIND}" ]]; then
  if [[ "${GC_MODE:-archive}" == "archive" ]]; then
    KIND=archive
  else
    KIND=full
  fi
fi

COS_BASE="${COS_BASE:-https://b2-download-1318671312.cos.ap-singapore.myqcloud.com}"

case "${KIND}" in
  full)
    OBJECT="db.tar.gz"
    CHECKSUM_OBJECT="db.tar.gz.sha256sum"
    ;;
  archive)
    OBJECT="archive-data.tar.gz"
    CHECKSUM_OBJECT="archive-data.tar.gz.sha256sum"
    ;;
  *)
    echo "Usage: $0 [full|archive]" >&2
    exit 1
    ;;
esac

URL="${COS_BASE}/${OBJECT}"
CHECKSUM_URL="${COS_BASE}/${CHECKSUM_OBJECT}"

if [[ -d "${DATA_DIR}/geth" ]]; then
  echo "ERROR: ${DATA_DIR}/geth already exists; refuse to overwrite" >&2
  echo "Remove it first if you intend to restore from snapshot." >&2
  exit 1
fi

mkdir -p "${DATA_DIR}"
# Keep download/extract off /tmp (usually the small OS partition). Prefer home disk
# space; override with SNAPSHOT_TMPDIR. Prefer same filesystem as HOST_DATADIR so
# the final mv is a rename when possible.
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/b2-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT
echo "using temp dir ${TMP_DIR}"

download() {
  local url="$1"
  local out="$2"
  if command -v aria2c >/dev/null 2>&1; then
    # Prefer aria2c for large COS tarballs (multi-connection, resume).
    aria2c --max-tries=0 -x 16 -s 16 -k 100M -c \
      --dir="$(dirname "${out}")" \
      --out="$(basename "${out}")" \
      "${url}"
  else
    echo "aria2c not found; falling back to curl (install aria2 for faster downloads)" >&2
    curl -fL --progress-bar -o "${out}" "${url}"
  fi
}

echo "downloading ${URL} ..."
download "${URL}" "${TMP_DIR}/${OBJECT}"
curl -fsSL -o "${TMP_DIR}/${CHECKSUM_OBJECT}" "${CHECKSUM_URL}"

EXPECTED="$(awk '{print $1}' "${TMP_DIR}/${CHECKSUM_OBJECT}")"
echo "verifying sha256 (${EXPECTED}) ..."
(
  cd "${TMP_DIR}"
  echo "${EXPECTED}  ${OBJECT}" | sha256sum -c -
)

echo "extracting into ${DATA_DIR} ..."
tar -xzf "${TMP_DIR}/${OBJECT}" -C "${TMP_DIR}"
if [[ ! -d "${TMP_DIR}/db/geth" ]]; then
  echo "ERROR: unexpected tarball layout (expected db/geth/)" >&2
  exit 1
fi
# Tarball root is db/; our --datadir expects geth/ at the top level.
shopt -s dotglob
mv "${TMP_DIR}/db/"* "${DATA_DIR}/"
shopt -u dotglob

echo "restored ${KIND} snapshot to ${DATA_DIR}"
echo "Skip ./init-database.sh. Keep GC_MODE=${GC_MODE:-${KIND}} matching this snapshot, then:"
echo "  docker compose up -d"
