#!/bin/sh
set -eu

LOG_FILE="/var/kend/data/logs/kend.out"
CONF_DIR="/klaytn-docker-pkg/conf"

mkdir -p "${CONF_DIR}"
cp /config/kend.conf "${CONF_DIR}/kend.conf"
if [ -n "${EXT_IP:-}" ]; then
  sed -i "s|^ADDITIONAL=.*|ADDITIONAL=\"--nat extip:${EXT_IP}\"|" "${CONF_DIR}/kend.conf"
fi

cleanup() {
  kend stop || true
  if [ -n "${TAIL_PID:-}" ]; then
    kill "${TAIL_PID}" 2>/dev/null || true
  fi
  exit 0
}

trap cleanup TERM INT

mkdir -p "$(dirname "${LOG_FILE}")"
kend start
touch "${LOG_FILE}"
tail -f "${LOG_FILE}" &
TAIL_PID=$!
wait "${TAIL_PID}"
