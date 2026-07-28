#!/usr/bin/env bash
#
# Sign the peer-discovery name record and patch node.toml.
#
# Usage (as root): ./sign-name-record.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"
env_require EXT_IP
env_require KEYSTORE_PASSWORD

NODE_TOML="${MONAD_HOME}/monad-bft/config/node.toml"
KEYSTORE="${MONAD_HOME}/monad-bft/config/id-secp"

if [[ ! -f "${KEYSTORE}" ]]; then
  echo "ERROR: missing ${KEYSTORE} — run ./generate-keystores.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${MONAD_HOME}/.env"

CURRENT_SEQ="$(sed -n 's|^self_record_seq_num[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*|\1|p' \
  "${NODE_TOML}" | head -n 1)"
CURRENT_SIG="$(sed -n 's|^self_name_record_sig[[:space:]]*=[[:space:]]*"\([^"]*\)".*|\1|p' \
  "${NODE_TOML}" | head -n 1)"

if [[ -z "${CURRENT_SEQ}" ]]; then
  echo "ERROR: no self_record_seq_num in ${NODE_TOML} — re-run ./configure.sh" >&2
  exit 1
fi

# Peers keep the highest sequence number they have seen for this key, so a record
# re-signed after an IP change must be numbered above the one already published.
if [[ -z "${CURRENT_SIG}" || "${CURRENT_SIG}" == *"<"* ]]; then
  SEQ=1
else
  SEQ=$((CURRENT_SEQ + 1))
fi

OUTPUT="$(monad-sign-name-record \
  --address "${EXT_IP}:${P2P_PORT}" \
  --authenticated-udp-port "${P2P_AUTH_PORT}" \
  --keystore-path "${KEYSTORE}" \
  --password "${KEYSTORE_PASSWORD}" \
  --self-record-seq-num "${SEQ}")"

SIG="$(echo "${OUTPUT}" | grep -oE '[0-9a-f]{128,}' | head -n 1 || true)"
if [[ -z "${SIG}" ]]; then
  echo "ERROR: could not parse name record signature — update node.toml manually:" >&2
  echo "${OUTPUT}" >&2
  exit 1
fi

sed_inplace "s|^self_address = .*|self_address = \"${EXT_IP}:${P2P_PORT}\"|" "${NODE_TOML}"
sed_inplace "s|^self_auth_port = .*|self_auth_port = ${P2P_AUTH_PORT}|" "${NODE_TOML}"
sed_inplace "s|^self_record_seq_num = .*|self_record_seq_num = ${SEQ}|" "${NODE_TOML}"
sed_inplace "s|^self_name_record_sig = .*|self_name_record_sig = \"${SIG}\"|" "${NODE_TOML}"

chown monad:monad "${NODE_TOML}"

echo "updated peer_discovery in ${NODE_TOML} (${EXT_IP}:${P2P_PORT}, seq ${SEQ})"
