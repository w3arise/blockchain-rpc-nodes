#!/usr/bin/env bash
#
# Prime Sonic state DB from a genesis file (sonictool genesis).
# Usage: ./sonic-init.sh [path/to/sonic.g]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

SONIC_VERSION="${SONIC_VERSION:-2.1.3}"
HOST_DATADIR="${HOST_DATADIR:-$HOME/sonic-data}"
GOMEMLIMIT_RUN="${GOMEMLIMIT:-28GiB}"
CACHE_MB_RUN="${CACHE_MB:-16000}"
GENESIS_FILE_INPUT="${1:-${HOME}/sonic.g}"

GENESIS_DIR_INPUT="$(dirname "${GENESIS_FILE_INPUT}")"
if [[ ! -d "${GENESIS_DIR_INPUT}" ]]; then
  echo "ERROR: Genesis file directory does not exist: ${GENESIS_DIR_INPUT}" >&2
  echo "Usage: $0 [path/to/sonic.g]" >&2
  exit 1
fi

GENESIS_FILE_ABS_DIR="$(cd "${GENESIS_DIR_INPUT}" && pwd)"
GENESIS_FILE_ABS="${GENESIS_FILE_ABS_DIR}/$(basename "${GENESIS_FILE_INPUT}")"

if [[ ! -f "${GENESIS_FILE_ABS}" ]]; then
  echo "ERROR: Genesis file not found at: ${GENESIS_FILE_ABS}" >&2
  echo "Usage: $0 [path/to/sonic.g]" >&2
  exit 1
fi

mkdir -p "${HOST_DATADIR}"

echo "Running sonic genesis with:"
echo "  Image:        sonic-node:${SONIC_VERSION}"
echo "  Host datadir: ${HOST_DATADIR}  (container: /data)"
echo "  GOMEMLIMIT:   ${GOMEMLIMIT_RUN}"
echo "  Cache (MB):   ${CACHE_MB_RUN}"
echo "  Genesis file: ${GENESIS_FILE_ABS}"
echo

docker run --rm -d \
  --entrypoint ./sonictool \
  --name sonic-init \
  -e "GOMEMLIMIT=${GOMEMLIMIT_RUN}" \
  -v "${HOST_DATADIR}:/data" \
  -v "${GENESIS_FILE_ABS_DIR}:/config:ro" \
  "sonic-node:${SONIC_VERSION}" \
  --datadir /data --cache "${CACHE_MB_RUN}" genesis "/config/$(basename "${GENESIS_FILE_ABS}")"

echo "Genesis initialization started in background. Check logs with: docker logs sonic-init"
docker logs -f --tail 100 sonic-init
