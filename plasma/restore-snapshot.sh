#!/usr/bin/env bash
#
# Download official Plasma observer snapshots (requester-pays S3) and move the
# unpacked DBs into HOST_DATADIR / HOST_CONSENSUS_DATADIR.
#
# Archives stay on disk. Staging is $HOME/plasma-snapshot-tmp (or SNAPSHOT_TMPDIR)
# on the same volume as the datadirs when possible.
#
# Requires: aws CLI v2, tar. Optional: gzip (integrity check).
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

NETWORK="${NETWORK:-mainnet}"
EXEC_DIR="${HOST_DATADIR:-${HOME}/plasma-reth-data}"
CONS_DIR="${HOST_CONSENSUS_DATADIR:-${HOME}/plasma-consensus-data}"
EXEC_DIR="${EXEC_DIR/\$HOME/$HOME}"
CONS_DIR="${CONS_DIR/\$HOME/$HOME}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/plasma-snapshot-tmp}"
TMP_BASE="${TMP_BASE/\$HOME/$HOME}"
BUCKET="${SNAPSHOT_BUCKET:-plasma-mainnet-db-backups}"
PREFIX="${SNAPSHOT_PREFIX:-mainnet/observer-0/}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}"

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: aws CLI is required for requester-pays Plasma snapshots." >&2
  exit 1
}
command -v tar >/dev/null 2>&1 || {
  echo "ERROR: tar is required." >&2
  exit 1
}

if [[ -d "${EXEC_DIR}/db" ]] || [[ -f "${CONS_DIR}/data.mdb" ]]; then
  echo "ERROR: datadir already has chain data; refuse to overwrite." >&2
  echo "  execution: ${EXEC_DIR}" >&2
  echo "  consensus: ${CONS_DIR}" >&2
  exit 1
fi

mkdir -p "${EXEC_DIR}" "${CONS_DIR}" "${TMP_BASE}"

warn_cross_fs() {
  local src="$1"
  local dst="$2"
  local src_dev dst_dev
  src_dev="$(stat -c '%d' "${src}" 2>/dev/null || true)"
  dst_dev="$(stat -c '%d' "${dst}" 2>/dev/null || true)"
  if [[ -n "${src_dev}" && -n "${dst_dev}" && "${src_dev}" != "${dst_dev}" ]]; then
    echo "WARNING: ${src} and ${dst} are on different filesystems; mv will copy." >&2
  fi
}

alert_kept_snapshot() {
  echo "WARNING: snapshot files are never deleted by this script." >&2
  echo "         staging: ${TMP_BASE}" >&2
  if [[ -d "${TMP_BASE}" ]]; then
    echo "         size: $(du -sh "${TMP_BASE}" | awk '{print $1}')" >&2
  fi
  echo "         Remove that path yourself when you no longer need the tarballs." >&2
}

list_date_folders() {
  aws s3 ls "s3://${BUCKET}/${PREFIX}" \
    --region "${REGION}" \
    --request-payer requester |
    awk '/PRE/ {print $2}' |
    sed 's:/$::' |
    grep -E '^[0-9]{2}-[0-9]{2}-[0-9]{2}$' || true
}

echo "==> Listing s3://${BUCKET}/${PREFIX} (requester-pays, ${REGION})"
mapfile -t FOLDERS < <(list_date_folders)
if [[ "${#FOLDERS[@]}" -eq 0 ]]; then
  echo "ERROR: no MM-DD-YY snapshot folders under s3://${BUCKET}/${PREFIX}" >&2
  echo "       Confirm AWS credentials and --request-payer access." >&2
  exit 1
fi

# Folders are MM-DD-YY; pick the last lexical after year-major sort.
FOLDER="$(printf '%s\n' "${FOLDERS[@]}" | awk -F- '{print $3$1$2" "$0}' | sort | awk '{print $2}' | tail -n 1)"
echo "    using ${FOLDER}"

CONS_ARCHIVE=""
EXEC_ARCHIVE=""
for name in "consensus-backup" "execution-backup"; do
  existing="$(ls -1 "${TMP_BASE}"/${name}-*.tar.gz 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "${existing}" && -s "${existing}" ]]; then
    echo "WARNING: reusing existing archive ${existing} ($(du -sh "${existing}" | awk '{print $1}'))" >&2
    if [[ "${name}" == consensus-backup ]]; then
      CONS_ARCHIVE="${existing}"
    else
      EXEC_ARCHIVE="${existing}"
    fi
  fi
done

if [[ -z "${CONS_ARCHIVE}" || -z "${EXEC_ARCHIVE}" ]]; then
  echo "==> Downloading s3://${BUCKET}/${PREFIX}${FOLDER}/"
  aws s3 cp \
    "s3://${BUCKET}/${PREFIX}${FOLDER}/" \
    "${TMP_BASE}/" \
    --recursive \
    --region "${REGION}" \
    --request-payer requester
  CONS_ARCHIVE="$(ls -1 "${TMP_BASE}"/consensus-backup-*.tar.gz | sort | tail -n 1)"
  EXEC_ARCHIVE="$(ls -1 "${TMP_BASE}"/execution-backup-*.tar.gz | sort | tail -n 1)"
fi

alert_kept_snapshot

if [[ ! -s "${CONS_ARCHIVE}" || ! -s "${EXEC_ARCHIVE}" ]]; then
  echo "ERROR: expected consensus-backup-*.tar.gz and execution-backup-*.tar.gz in ${TMP_BASE}" >&2
  exit 1
fi

if command -v gzip >/dev/null 2>&1; then
  gzip -t "${CONS_ARCHIVE}"
  gzip -t "${EXEC_ARCHIVE}"
fi

UNPACK_CONS="${TMP_BASE}/unpacked-consensus"
UNPACK_EXEC="${TMP_BASE}/unpacked-execution"
rm -rf "${UNPACK_CONS}" "${UNPACK_EXEC}"
mkdir -p "${UNPACK_CONS}" "${UNPACK_EXEC}"

echo "==> Unpacking consensus into ${UNPACK_CONS}"
tar -xzf "${CONS_ARCHIVE}" -C "${UNPACK_CONS}"
CONS_SRC="$(find "${UNPACK_CONS}" -type f \( -name 'data.mdb' -o -name 'consensus-backup*' -o -name '*.mdb' -o -name '*.db' \) | head -n 1 || true)"
if [[ -z "${CONS_SRC}" ]]; then
  echo "ERROR: no consensus DB file found inside ${CONS_ARCHIVE}" >&2
  exit 1
fi
warn_cross_fs "${UNPACK_CONS}" "${CONS_DIR}"
mv "${CONS_SRC}" "${CONS_DIR}/data.mdb"

echo "==> Unpacking execution into ${UNPACK_EXEC}"
tar -xzf "${EXEC_ARCHIVE}" -C "${UNPACK_EXEC}" --strip-components=1
if [[ ! -d "${UNPACK_EXEC}/db" ]]; then
  # Some archives nest an extra data/ directory.
  if [[ -d "${UNPACK_EXEC}/data/db" ]]; then
    UNPACK_EXEC="${UNPACK_EXEC}/data"
  else
    echo "ERROR: restore did not produce a reth db/ directory" >&2
    exit 1
  fi
fi
warn_cross_fs "${UNPACK_EXEC}" "${EXEC_DIR}"
# Move unpacked tree entries into the host datadir (same-fs rename).
shopt -s dotglob nullglob
for item in "${UNPACK_EXEC}"/*; do
  mv "${item}" "${EXEC_DIR}/"
done
shopt -u dotglob nullglob

"${SCRIPT_DIR}/create-jwt.sh"
if [[ ! -f "${CONS_DIR}/ec-secp256k1-non-validator.der" ]]; then
  echo "==> Snapshot had no consensus identity; generating one"
  "${SCRIPT_DIR}/init-database.sh"
fi

echo ""
echo "Snapshot restore finished (${NETWORK}). Start the node with:"
echo "  docker compose up -d"
alert_kept_snapshot
