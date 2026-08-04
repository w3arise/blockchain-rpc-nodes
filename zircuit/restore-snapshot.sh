#!/usr/bin/env bash
#
# Restore a Conduit Zircuit mainnet op-reth snapshot into HOST_DATADIR.
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

DATA_DIR="${HOST_DATADIR:-${HOME}/zircuit-op-reth-data}"
DATA_DIR="${DATA_DIR/\$HOME/$HOME}"
NETWORK_SLUG="${SNAPSHOT_NETWORK:-zircuit-mainnet}"
GCS_URI="gs://conduit-networks-snapshots/${NETWORK_SLUG}/latest.tar"
TMP_BASE="${SNAPSHOT_TMPDIR:-${HOME}/zircuit-snapshot-tmp}"
TMP_BASE="${TMP_BASE/\$HOME/$HOME}"

if [[ -n "$(ls -A "${DATA_DIR}" 2>/dev/null || true)" ]]; then
  echo "ERROR: ${DATA_DIR} is not empty; refuse to overwrite" >&2
  echo "Remove existing data first if you intend to restore from snapshot." >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud is required for requester-pays Conduit snapshot downloads" >&2
  exit 1
fi

if [[ -z "${GCP_PROJECT:-}" ]]; then
  GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [[ -z "${GCP_PROJECT}" || "${GCP_PROJECT}" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT in .env or configure an active gcloud project" >&2
  exit 1
fi

mkdir -p "${DATA_DIR}" "${TMP_BASE}"
TMP_DIR="$(mktemp -d "${TMP_BASE}/XXXXXX")"
ARCHIVE="${TMP_DIR}/latest.tar"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "==> Downloading ${GCS_URI} (billing project: ${GCP_PROJECT})"
gcloud storage cp --billing-project="${GCP_PROJECT}" "${GCS_URI}" "${ARCHIVE}"

echo "==> Extracting into ${DATA_DIR}"
tar -xf "${ARCHIVE}" -C "${DATA_DIR}"

echo ""
echo "Snapshot restore finished. Start the node with:"
echo "  docker compose up -d"
