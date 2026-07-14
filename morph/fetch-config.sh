#!/usr/bin/env bash
#
# Refresh Morph config from morph-l2/run-morph-node and verify geth genesis checksums.
#
# Usage: ./fetch-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REF="${RUN_MORPH_NODE_REF:-main}"
BASE="https://raw.githubusercontent.com/morph-l2/run-morph-node/${REF}"

fetch() {
  local src="$1"
  local dst="$2"
  echo "fetching ${src}..."
  curl -fsSL "${BASE}/${src}" -o "${dst}.tmp"
  mv "${dst}.tmp" "${dst}"
}

verify_checksum() {
  local file="$1"
  local checksum_file="$2"
  local actual expected
  actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  if [[ -f "${checksum_file}" ]]; then
    expected="$(tr -d '[:space:]' < "${checksum_file}")"
    if [[ "${actual}" != "${expected}" ]]; then
      echo "ERROR: checksum mismatch for ${file}" >&2
      echo "  expected: ${expected}" >&2
      echo "  actual:   ${actual}" >&2
      exit 1
    fi
    echo "checksum OK for $(basename "${file}")"
  else
    echo "${actual}" > "${checksum_file}"
    echo "wrote checksum to ${checksum_file}"
  fi
}

mkdir -p "${SCRIPT_DIR}/config/hoodi"

fetch "mainnet/node-data/config/genesis.json" "${SCRIPT_DIR}/config/genesis.json"
fetch "mainnet/node-data/config/config.toml" "${SCRIPT_DIR}/config/config.toml"
fetch "mainnet/geth-data/static-nodes.json" "${SCRIPT_DIR}/config/static-nodes.json"
fetch "mainnet/geth-data/genesis.json" "${SCRIPT_DIR}/config/geth-genesis.json"
verify_checksum "${SCRIPT_DIR}/config/geth-genesis.json" "${SCRIPT_DIR}/config/.geth-genesis.sha256"

fetch "hoodi/node-data/config/genesis.json" "${SCRIPT_DIR}/config/hoodi/genesis.json"
fetch "hoodi/node-data/config/config.toml" "${SCRIPT_DIR}/config/hoodi/config.toml"
fetch "hoodi/geth-data/static-nodes.json" "${SCRIPT_DIR}/config/hoodi/static-nodes.json"
fetch "hoodi/geth-data/genesis.json" "${SCRIPT_DIR}/config/hoodi/geth-genesis.json"
verify_checksum "${SCRIPT_DIR}/config/hoodi/geth-genesis.json" "${SCRIPT_DIR}/config/hoodi/.geth-genesis.sha256"

REF_SHA="$(curl -fsSL "https://api.github.com/repos/morph-l2/run-morph-node/commits/${REF}" 2>/dev/null \
  | grep -m1 '"sha"' | sed 's/.*"sha": "\([^"]*\)".*/\1/' || true)"
if [[ -n "${REF_SHA}" ]]; then
  echo "${REF_SHA}" > "${SCRIPT_DIR}/config/.run-morph-node-ref"
  echo "pinned run-morph-node ref: ${REF_SHA}"
fi

echo "config refresh complete"
