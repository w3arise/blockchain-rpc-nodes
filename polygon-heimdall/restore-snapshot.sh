#!/usr/bin/env bash
#
# Download a pruned Heimdall snapshot and move its blockstore into the datadir.
# Keeps config/ (genesis, node key, patched toml). Does not delete the archive.
#
# Usage:
#   SNAPSHOT_URL=https://.../heimdall.tar.lz4 ./restore-snapshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing .env — run ./configure.sh <mainnet|amoy> first" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

DATA_DIR="${HOST_DATADIR:-${HOME}/polygon-heimdall-data}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/polygon-heimdall-snapshot-tmp}"
CONFIG_TOML="${DATA_DIR}/config/config.toml"
SNAPSHOT_URL="${SNAPSHOT_URL:-}"

if [[ -z "${SNAPSHOT_URL}" ]]; then
  echo "ERROR: set SNAPSHOT_URL to a pruned Heimdall tarball (.tar.lz4, .tar.zst, .tar.gz, or .tar)." >&2
  echo "       Sources: https://docs.polygon.technology/pos/how-to/snapshots/" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_TOML}" ]]; then
  echo "ERROR: missing ${CONFIG_TOML} — run ./init-database.sh first" >&2
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
    curl -fL --retry 5 -C - -o "${out}" "${url}"
  fi
}

mkdir -p "${TMP_BASE}"
ARCHIVE_NAME="$(basename "${SNAPSHOT_URL%%\?*}")"
ARCHIVE="${TMP_BASE}/${ARCHIVE_NAME}"
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

if [[ -d "${DATA_DIR}/data" ]] && [[ -n "$(ls -A "${DATA_DIR}/data" 2>/dev/null || true)" ]]; then
  echo "WARNING: ${DATA_DIR}/data is not empty."
  read -r -p "Wipe data/ and restore the snapshot? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}/data" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "==> Using staging dir ${TMP_BASE}"
echo "==> Downloading snapshot"
echo "    ${SNAPSHOT_URL}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"
alert_kept_snapshot

rm -rf "${EXTRACT}"
mkdir -p "${EXTRACT}"
echo "==> Extracting into ${EXTRACT}"
case "${ARCHIVE}" in
  *.tar.lz4|*.lz4)
    command -v lz4 >/dev/null 2>&1 || { echo "ERROR: lz4 is required." >&2; exit 1; }
    lz4 -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"
    ;;
  *.tar.zst|*.zst)
    command -v zstd >/dev/null 2>&1 || { echo "ERROR: zstd is required." >&2; exit 1; }
    zstd -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "${ARCHIVE}" -C "${EXTRACT}"
    ;;
  *.tar)
    tar -xf "${ARCHIVE}" -C "${EXTRACT}"
    ;;
  *)
    echo "ERROR: unsupported archive type: ${ARCHIVE_NAME}" >&2
    exit 1
    ;;
esac

SRC=""
db_count=0
db_dir=""
while IFS= read -r -d '' db; do
  db_count=$((db_count + 1))
  db_dir="$(dirname "${db}")"
done < <(find "${EXTRACT}" -name blockstore.db -print0)

if [[ "${db_count}" -eq 1 ]]; then
  SRC="${db_dir}"
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: expected one blockstore.db in the snapshot (found ${db_count})." >&2
  find "${EXTRACT}" -maxdepth 3 \( -type d -o -name blockstore.db \) >&2
  exit 1
fi

# A snapshot that unpacked config/ next to data/ can carry another operator's
# external_address. Import the blockstore only.
if [[ "$(basename "${SRC}")" == "config" ]]; then
  echo "ERROR: blockstore.db resolved inside config/. Refusing to import it." >&2
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

echo "==> Installing chain data into ${DATA_DIR}/data"
move_into "${SRC}" "${DATA_DIR}/data"

rm -f "${DATA_DIR}/data/priv_validator_state.json"
printf '%s\n' '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/data/priv_validator_state.json"

if [[ -n "${BUILD_UID:-}" && -n "${BUILD_GID:-}" ]]; then
  if ! chown -R "${BUILD_UID}:${BUILD_GID}" "${DATA_DIR}/data"; then
    echo "ERROR: data/ is not owned by ${BUILD_UID}:${BUILD_GID}." >&2
    echo "       sudo chown -R ${BUILD_UID}:${BUILD_GID} ${DATA_DIR}/data" >&2
    exit 1
  fi
fi

echo ""
echo "==> Snapshot restore complete"
echo "    datadir: ${DATA_DIR}"
echo "    config/ was left in place (genesis and keys)."
echo "Next: ./patch-config.sh"
echo "      docker compose up -d"
echo "Do not re-run ./init-database.sh against this datadir."
alert_kept_snapshot
