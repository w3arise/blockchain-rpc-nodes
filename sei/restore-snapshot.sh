#!/usr/bin/env bash
#
# Download and restore a Sei mainnet snapshot into the datadir (data/ + wasm/).
#
# Default source (repo exception): latest Polkachu snapshot from
# https://www.polkachu.com/tendermint_snapshots/sei
# Polkachu's snapshot server uses heavy app pruning (~100 blocks); this repo
# still accepts it for Sei bootstrap. ./patch-config.sh applies min-retain-blocks=0
# after restore so the node does not prune further going forward.
#
# Requires: tar, lz4; aria2c (preferred) or curl
#
# Usage:
#   ./restore-snapshot.sh
#   SNAPSHOT_URL=https://... ./restore-snapshot.sh
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

DATA_DIR="${HOST_DATADIR:-${HOME}/sei-data}"
CONFIG_TOML="${DATA_DIR}/config/config.toml"
SNAPSHOT_URL="${SNAPSHOT_URL:-}"
POLKACHU_SNAPSHOT_PAGE="${POLKACHU_SNAPSHOT_PAGE:-https://www.polkachu.com/tendermint_snapshots/sei}"

resolve_polkachu_snapshot_url() {
  local page="$1"
  local url

  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required to resolve the latest Polkachu snapshot URL." >&2
    exit 1
  }

  url="$(curl -fsSL "${page}" \
    | grep -oE 'https://snapshots\.polkachu\.com/snapshots/sei/sei_[0-9]+\.tar\.lz4' \
    | head -1 || true)"

  if [[ -z "${url}" ]]; then
    echo "ERROR: could not find a snapshot download URL on ${page}" >&2
    echo "       Set SNAPSHOT_URL manually in .env or the environment." >&2
    exit 1
  fi

  printf '%s\n' "${url}"
}

if [[ -z "${SNAPSHOT_URL}" ]]; then
  echo "==> SNAPSHOT_URL unset — resolving latest Polkachu snapshot"
  echo "    ${POLKACHU_SNAPSHOT_PAGE}"
  SNAPSHOT_URL="$(resolve_polkachu_snapshot_url "${POLKACHU_SNAPSHOT_PAGE}")"
  echo "    ${SNAPSHOT_URL}"
fi

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
  read -r -p "Wipe data/ and wasm/ and restore snapshot? (y/N): " ans
  case "${ans}" in
    y|Y)
      rm -rf "${DATA_DIR}/data" "${DATA_DIR}/wasm"
      ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

mkdir -p "${DATA_DIR}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/sei-snapshot-tmp}"
mkdir -p "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT
echo "==> Using temp dir ${TMP_DIR}"

ARCHIVE_NAME="$(basename "${SNAPSHOT_URL}")"
ARCHIVE="${TMP_DIR}/${ARCHIVE_NAME}"
echo "==> Downloading snapshot"
echo "    ${SNAPSHOT_URL}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"

EXTRACT="${TMP_DIR}/extract"
mkdir -p "${EXTRACT}"
echo "==> Extracting"
case "${ARCHIVE_NAME}" in
  *.tar.lz4)
    lz4 -dc "${ARCHIVE}" | tar -x -C "${EXTRACT}"
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "${ARCHIVE}" -C "${EXTRACT}"
    ;;
  *)
    echo "ERROR: unsupported archive name (expected .tar.lz4 or .tar.gz): ${ARCHIVE_NAME}" >&2
    exit 1
    ;;
esac

install_tree() {
  local name="$1"
  local src=""

  if [[ -d "${EXTRACT}/${name}" ]]; then
    src="${EXTRACT}/${name}"
  else
    local top_count=0
    local top_dir=""
    while IFS= read -r -d '' d; do
      top_count=$((top_count + 1))
      top_dir="${d}"
    done < <(find "${EXTRACT}" -mindepth 1 -maxdepth 1 -type d -print0)
    if [[ "${top_count}" -eq 1 && -d "${top_dir}/${name}" ]]; then
      src="${top_dir}/${name}"
    fi
  fi

  if [[ -z "${src}" ]]; then
    return 1
  fi

  echo "==> Installing ${name}/ into ${DATA_DIR}/${name}"
  mkdir -p "${DATA_DIR}/${name}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${src}/" "${DATA_DIR}/${name}/"
  else
    cp -a "${src}/." "${DATA_DIR}/${name}/"
  fi
  return 0
}

if ! install_tree "data"; then
  echo "ERROR: could not find data/ in snapshot. Contents:" >&2
  find "${EXTRACT}" -maxdepth 3 -type d >&2
  exit 1
fi

if ! install_tree "wasm"; then
  echo "WARNING: wasm/ not found in snapshot — node may fail to start without it." >&2
  echo "         See https://docs.sei.io/node/snapshot" >&2
fi

rm -f "${DATA_DIR}/data/priv_validator_state.json" 2>/dev/null || true
printf '%s\n' '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/data/priv_validator_state.json"

echo ""
echo "==> Snapshot restore complete"
echo "    datadir: ${DATA_DIR}"
echo "Next: ./patch-config.sh"
echo "      docker compose up -d"
echo "Do not re-run ./init-database.sh against this datadir."
