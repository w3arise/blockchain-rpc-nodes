#!/usr/bin/env bash
#
# Download and restore an official Ankr Tac mainnet snapshot into the datadir.
#
# Prefers SNAPSHOT_TYPE=full (block history; pruned state). Use archive for full
# state history. Skip ./init-database.sh wipe after restore — keep config/genesis.
#
# Requires: tar, lz4; aria2c (preferred) or curl
#
# Usage:
#   ./restore-snapshot.sh              # uses SNAPSHOT_TYPE from .env (default: full)
#   SNAPSHOT_TYPE=archive ./restore-snapshot.sh
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

DATA_DIR="${HOST_DATADIR:-${HOME}/tac-data}"
SNAPSHOT_TYPE="${SNAPSHOT_TYPE:-full}"
CONFIG_TOML="${DATA_DIR}/config/config.toml"

case "${SNAPSHOT_TYPE}" in
  full)
    DEFAULT_URL="http://snapshot.tac.ankr.com/tac-mainnet-full-latest.tar.lz4"
    ;;
  archive)
    DEFAULT_URL="http://snapshot.tac.ankr.com/tac-mainnet-archive-latest.tar.lz4"
    ;;
  *)
    echo "ERROR: SNAPSHOT_TYPE must be 'full' or 'archive' (got: ${SNAPSHOT_TYPE})" >&2
    exit 1
    ;;
esac

SNAPSHOT_URL="${SNAPSHOT_URL:-${DEFAULT_URL}}"

for tool in tar lz4; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

if [[ ! -f "${CONFIG_TOML}" ]]; then
  echo "ERROR: missing ${CONFIG_TOML} — run ./init-database.sh before restoring a snapshot" >&2
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

if [[ -d "${DATA_DIR}/data" ]] && [[ -n "$(ls -A "${DATA_DIR}/data" 2>/dev/null || true)" ]]; then
  echo "WARNING: ${DATA_DIR}/data is not empty."
  read -r -p "Wipe data/ and restore ${SNAPSHOT_TYPE} snapshot? (y/N): " ans
  case "${ans}" in
    y|Y) rm -rf "${DATA_DIR}/data" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"
# Keep download/extract off /tmp (usually the small OS partition).
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/tac-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT
echo "==> Using temp dir ${TMP_DIR}"

ARCHIVE_NAME="$(basename "${SNAPSHOT_URL}")"
ARCHIVE="${TMP_DIR}/${ARCHIVE_NAME}"
echo "==> Downloading ${SNAPSHOT_TYPE} snapshot"
echo "    ${SNAPSHOT_URL}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"

# Optional checksum when Ankr publishes a sibling .shasum
SHA_URL="${SNAPSHOT_URL%.tar.lz4}.shasum"
SHA_FILE="${TMP_DIR}/$(basename "${SHA_URL}")"
if curl -fsSL -o "${SHA_FILE}" "${SHA_URL}" 2>/dev/null; then
  echo "==> Verifying checksum (${SHA_URL})"
  (
    cd "${TMP_DIR}"
    if command -v sha256sum >/dev/null 2>&1 && grep -qE '^[a-fA-F0-9]{64}[[:space:]]' "${SHA_FILE}"; then
      sha256sum -c "$(basename "${SHA_FILE}")"
    else
      shasum -a 256 -c "$(basename "${SHA_FILE}")"
    fi
  )
  echo "checksum OK"
else
  echo "==> No .shasum at ${SHA_URL} (continuing without verify)"
fi

EXTRACT="${TMP_DIR}/extract"
mkdir -p "${EXTRACT}"
echo "==> Extracting into ${EXTRACT}"
lz4 -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"

# Normalize: Ankr layouts usually unpack a data/ directory (or its contents)
SRC=""
if [[ -d "${EXTRACT}/data" ]]; then
  SRC="${EXTRACT}/data"
elif [[ -d "${EXTRACT}/application.db" ]] || [[ -d "${EXTRACT}/blockstore.db" ]]; then
  SRC="${EXTRACT}"
else
  top_count=0
  top_dir=""
  while IFS= read -r -d '' d; do
    top_count=$((top_count + 1))
    top_dir="${d}"
  done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ "${top_count}" -eq 1 && -d "${top_dir}/data" ]]; then
    SRC="${top_dir}/data"
  elif [[ "${top_count}" -eq 1 ]] && { [[ -d "${top_dir}/application.db" ]] || [[ -d "${top_dir}/blockstore.db" ]]; }; then
    SRC="${top_dir}"
  fi
fi

if [[ -z "${SRC}" ]]; then
  echo "ERROR: could not find Tendermint data/ in snapshot. Contents:" >&2
  find "${EXTRACT}" -maxdepth 3 -type d >&2
  exit 1
fi

echo "==> Installing chain data into ${DATA_DIR}/data"
mkdir -p "${DATA_DIR}/data"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "${SRC}/" "${DATA_DIR}/data/"
else
  cp -a "${SRC}/." "${DATA_DIR}/data/"
fi

# Drop validator identity leftovers if present in the snapshot
rm -f "${DATA_DIR}/data/priv_validator_state.json" 2>/dev/null || true
# Recreate empty validator state so non-validator RPC nodes start cleanly
printf '%s\n' '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/data/priv_validator_state.json"

echo ""
echo "==> Snapshot restore complete (${SNAPSHOT_TYPE})"
echo "    datadir: ${DATA_DIR}"
if [[ "${SNAPSHOT_TYPE}" == "full" ]]; then
  echo "    Keep PRUNING=default in .env (matches full snapshot)."
else
  echo "    Set PRUNING=nothing in .env before ./patch-config.sh for archive."
fi
echo "Next: ./patch-config.sh"
echo "      docker compose up -d"
echo "Do not re-run ./init-database.sh against this datadir."
