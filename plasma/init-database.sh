#!/usr/bin/env bash
#
# Initialize Plasma execution + consensus datadirs from committed genesis (no snapshot).
#
# Snapshot flow — skip this script after ./restore-snapshot.sh (still run
# ./create-jwt.sh; identity keys are created here if missing).
#
# Usage: ./init-database.sh
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
GENESIS="${SCRIPT_DIR}/config/${NETWORK}/genesis.json"
TOML="${SCRIPT_DIR}/config/${NETWORK}/non-validator.toml"
IDENTITY="${CONS_DIR}/ec-secp256k1-non-validator.der"

for var in RETH_IMAGE CONSENSUS_IMAGE; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: ${var} is not set in .env" >&2
    exit 1
  fi
done

for required in "${GENESIS}" "${TOML}"; do
  if [[ ! -f "${required}" ]]; then
    echo "ERROR: missing ${required}" >&2
    exit 1
  fi
done

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required." >&2
  exit 1
}

mkdir -p "${EXEC_DIR}" "${CONS_DIR}"
"${SCRIPT_DIR}/create-jwt.sh"

if [[ ! -f "${IDENTITY}" ]]; then
  echo "==> Generating consensus identity (secp256k1)"
  if command -v openssl >/dev/null 2>&1; then
    openssl ecparam -name secp256k1 -genkey -noout -out "${CONS_DIR}/ec-secp256k1-non-validator.pem"
    openssl ec -in "${CONS_DIR}/ec-secp256k1-non-validator.pem" -outform DER -no_public -out "${IDENTITY}"
  else
    docker run --rm --user 0:0 --entrypoint /bin/sh \
      -v "${CONS_DIR}:/consensus" \
      docker.io/alpine/openssl:3.5.8 \
      -c 'openssl ecparam -name secp256k1 -genkey -noout -out /consensus/ec-secp256k1-non-validator.pem && openssl ec -in /consensus/ec-secp256k1-non-validator.pem -outform DER -no_public -out /consensus/ec-secp256k1-non-validator.der'
  fi
else
  echo "Consensus identity already exists (skipping)"
fi

if [[ -f "${CONS_DIR}/data.mdb" ]]; then
  echo "Consensus database already exists at ${CONS_DIR}/data.mdb (skipping plasma-cli init)"
else
  echo "==> Initializing consensus database (${NETWORK})"
  docker run --rm --user 0:0 \
    --entrypoint plasma-cli \
    -v "${CONS_DIR}:/consensus" \
    -v "${GENESIS}:/node/genesis.json:ro" \
    -v "${TOML}:/tmp/non-validator.toml:ro" \
    "${CONSENSUS_IMAGE}" \
    init \
    --data-dir /consensus \
    --chain /node/genesis.json \
    observer \
    --config-path /tmp/non-validator.toml
fi

if [[ -f "${EXEC_DIR}/db/mdbx.dat" || -d "${EXEC_DIR}/db" ]]; then
  echo "Execution database already exists at ${EXEC_DIR} (skipping reth init)"
else
  echo "==> Initializing execution database (${NETWORK})"
  docker run --rm --user 0:0 \
    --entrypoint reth \
    -v "${EXEC_DIR}:/data" \
    -v "${GENESIS}:/node/genesis.json:ro" \
    "${RETH_IMAGE}" \
    init \
    --chain /node/genesis.json \
    --datadir /data
fi

echo ""
echo "Initialization complete."
echo "  execution: ${EXEC_DIR}"
echo "  consensus: ${CONS_DIR}"
echo "Next: docker compose up -d"
