#!/bin/bash

set -euo pipefail

# Simple helper to run sonic genesis inside the container version from .env
# Usage: ./sonic-init.sh [path/to/sonic.g]
# - If no argument is provided, defaults to '$HOME/sonic.g'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load SONIC_VERSION and other vars from .env if present (recommended: cp env.template .env)
if [ -f "${ENV_FILE}" ]; then
    # Export variables defined in .env
    set -a
    # shellcheck disable=SC1090
    . "${ENV_FILE}"
    set +a
fi

# Defaults (mirror env.template where useful)
SONIC_VERSION="${SONIC_VERSION:-2.1.2}"
DATADIR="${DATADIR:-/app/.sonic}"
GOMEMLIMIT_RUN="${GOMEMLIMIT:-28GiB}"   # default to 28GiB for this init as requested
CACHE_MB_RUN="${CACHE_MB:-16000}"       # default to 16000 for this init

# Resolve genesis file (configurable; default is '$HOME/sonic.g')
GENESIS_FILE_INPUT="${1:-${HOME}/sonic.g}"

# Check if parent directory exists before resolving absolute path
GENESIS_DIR_INPUT="$(dirname "${GENESIS_FILE_INPUT}")"
if [ ! -d "${GENESIS_DIR_INPUT}" ]; then
    echo "ERROR: Genesis file directory does not exist: ${GENESIS_DIR_INPUT}"
    echo "Usage: $0 [path/to/sonic.g]"
    exit 1
fi

# Resolve to absolute path
GENESIS_FILE_ABS_DIR="$(cd "${GENESIS_DIR_INPUT}" && pwd)"
GENESIS_FILE_ABS="${GENESIS_FILE_ABS_DIR}/$(basename "${GENESIS_FILE_INPUT}")"

if [ ! -f "${GENESIS_FILE_ABS}" ]; then
    echo "ERROR: Genesis file not found at: ${GENESIS_FILE_ABS}"
    echo "Usage: $0 [path/to/sonic.g]"
    exit 1
fi

echo "Running sonic genesis with:"
echo "  Image:        sonic-node:${SONIC_VERSION}"
echo "  Datadir:      ${DATADIR}  (mounted from ${HOME}/.sonic)"
echo "  GOMEMLIMIT:   ${GOMEMLIMIT_RUN}"
echo "  Cache (MB):   ${CACHE_MB_RUN}"
echo "  Genesis file: ${GENESIS_FILE_ABS}"
echo

# Note: We mount:
# - Host ${HOME}/.sonic -> ${DATADIR} inside the container
# - Genesis file directory -> /config (read-only)
# We intentionally do not use host networking; not required for genesis.
docker run --rm -d \
    --entrypoint ./sonictool \
    --name sonic-init \
    -e "GOMEMLIMIT=${GOMEMLIMIT_RUN}" \
    -v "${HOME}/.sonic:${DATADIR}" \
    -v "${GENESIS_FILE_ABS_DIR}:/config:ro" \
    "sonic-node:${SONIC_VERSION}" \
    --datadir "${DATADIR}" --cache "${CACHE_MB_RUN}" genesis "/config/$(basename "${GENESIS_FILE_ABS}")"

echo "Genesis initialization started in background. Check logs with: docker logs sonic-init"

docker logs -f --tail 100 sonic-init
