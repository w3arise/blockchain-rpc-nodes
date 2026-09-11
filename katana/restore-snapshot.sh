#!/usr/bin/env bash
#
# Restore a Katana mainnet op-reth snapshot into HOST_DATADIR.
#
# Usage: ./restore-snapshot.sh [mainnet|bokuto]
#
# Source: https://github.com/katana-network/network-configs
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

NETWORK="${1:-mainnet}"
case "${NETWORK}" in
  mainnet)
    SNAPSHOT_URL="https://pub-1d729d824bda40459735d97aca47bc6f.r2.dev/katana/latest.tar"
    ;;
  bokuto)
    SNAPSHOT_URL="https://pub-1d729d824bda40459735d97aca47bc6f.r2.dev/katana-bokuto/latest.tar"
    ;;
  *)
    echo "Usage: $0 [mainnet|bokuto]" >&2
    exit 1
    ;;
esac

DATA_DIR="${HOST_DATADIR:-${HOME}/katana-op-reth-data}"
DATA_DIR="${DATA_DIR/\$HOME/$HOME}"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/katana-snapshot-tmp}"
TMP_BASE="${TMP_BASE/\$HOME/$HOME}"

if [[ -n "$(ls -A "${DATA_DIR}" 2>/dev/null || true)" ]]; then
  echo "ERROR: ${DATA_DIR} is not empty; refuse to overwrite" >&2
  echo "Remove existing data first if you intend to restore from snapshot." >&2
  exit 1
fi

mkdir -p "${DATA_DIR}" "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
ARCHIVE="${TMP_DIR}/katana-latest.tar"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

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
    curl -fL --progress-bar -o "${out}" "${url}"
  fi
}

echo "==> Downloading ${SNAPSHOT_URL}"
download "${SNAPSHOT_URL}" "${ARCHIVE}"

echo "==> Extracting into ${DATA_DIR}"
tar -xf "${ARCHIVE}" -C "${DATA_DIR}"

echo ""
echo "Snapshot restore finished (${NETWORK}). Start the node with:"
echo "  docker compose up -d"
