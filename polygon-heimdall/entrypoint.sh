#!/bin/sh
# Refuse to start a sentry whose app.toml still has the other network's chain name.
set -eu

HOME_DIR="${HEIMDALL_HOME:-/data}"
APP_TOML="${HOME_DIR}/config/app.toml"
CONFIG_TOML="${HOME_DIR}/config/config.toml"

# init (and other one-shot commands) run before config exists.
if [ "${1:-}" != "start" ]; then
  exec heimdalld "$@"
fi

if [ ! -f "${CONFIG_TOML}" ] || [ ! -f "${APP_TOML}" ]; then
  echo "ERROR: missing ${HOME_DIR}/config — run ./init-database.sh" >&2
  exit 1
fi

if [ -z "${HEIMDALL_CHAIN:-}" ]; then
  echo "ERROR: HEIMDALL_CHAIN is empty — run ./configure.sh" >&2
  exit 1
fi

if ! grep -q "^chain = \"${HEIMDALL_CHAIN}\"" "${APP_TOML}"; then
  echo "ERROR: app.toml chain is not ${HEIMDALL_CHAIN} — run ./patch-config.sh" >&2
  exit 1
fi

exec heimdalld "$@"
