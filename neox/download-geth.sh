#!/usr/bin/env bash
#
# Download the Neo X geth binary from bane-labs/go-ethereum releases.
# Writes ./geth (gitignored). Required before init-database.sh or compose up.
#
# Usage: ./download-geth.sh
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

GETH_VERSION="${GETH_VERSION:-v0.6.1}"
ARCH="${GETH_ARCH:-}"

if [[ -z "${ARCH}" ]]; then
  case "$(uname -m)" in
    x86_64|amd64) ARCH="linux-amd64" ;;
    aarch64|arm64) ARCH="linux-arm64" ;;
    *)
      echo "ERROR: unsupported architecture $(uname -m); set GETH_ARCH in .env" >&2
      exit 1
      ;;
  esac
fi

ASSET="geth-${ARCH}"
URL="https://github.com/bane-labs/go-ethereum/releases/download/${GETH_VERSION}/${ASSET}"
TARGET="${SCRIPT_DIR}/geth"

for tool in curl; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: '${tool}' is required." >&2
    exit 1
  }
done

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

echo "==> Downloading Neo X geth ${GETH_VERSION} (${ASSET})"
curl -fL "${URL}" -o "${TMP}"

install -m 755 "${TMP}" "${TARGET}"
echo "==> Installed ${TARGET}"
echo "    Run ./init-database.sh then docker compose up -d"
