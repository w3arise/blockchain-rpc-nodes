#!/usr/bin/env bash
#
# Create Hedera runtime/bootstrap configuration and generate database secrets.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_TEMPLATE="${SCRIPT_DIR}/env.template"
APP_TEMPLATE="${SCRIPT_DIR}/config/application.yml.template"
APP_CONFIG="${SCRIPT_DIR}/config/application.yml"
BOOTSTRAP_ENV="${SCRIPT_DIR}/bootstrap.env"

sed_inplace() {
  local expression="$1"
  local file="$2"
  local temporary
  temporary="$(mktemp)"
  sed -e "${expression}" "${file}" > "${temporary}"
  mv "${temporary}" "${file}"
}

set_env_value() {
  local name="$1"
  local value="$2"
  sed_inplace "s|^${name}=.*|${name}=${value}|" "${ENV_FILE}"
}

if [[ ! -f "${ENV_TEMPLATE}" || ! -f "${APP_TEMPLATE}" ]]; then
  echo "ERROR: missing env.template or config/application.yml.template" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  echo "created .env from env.template"
fi

generated_any=false
for name in \
  POSTGRES_PASSWORD GRAPHQL_PASSWORD GRPC_PASSWORD IMPORTER_PASSWORD \
  OWNER_PASSWORD REST_PASSWORD REST_JAVA_PASSWORD ROSETTA_PASSWORD WEB3_PASSWORD
do
  current="$(grep -E "^${name}=" "${ENV_FILE}" | cut -d= -f2- || true)"
  if [[ -z "${current}" || "${current}" == "GENERATE" ]]; then
    set_env_value "${name}" "$(openssl rand -hex 24)"
    echo "generated ${name}"
    generated_any=true
  fi
done

# shellcheck disable=SC1091
source "${ENV_FILE}"

mkdir -p \
  "${HOST_DB_DATADIR}" \
  "${HOST_MIRROR_REDIS_DATADIR}" \
  "${HOST_RELAY_REDIS_DATADIR}" \
  "${HOST_BOOTSTRAP_DATADIR}/export" \
  "${HOST_BOOTSTRAP_DATADIR}/bootstrap-logs"

cp "${APP_TEMPLATE}" "${APP_CONFIG}"
chmod 644 "${APP_CONFIG}"

{
  printf 'export PGUSER="%s"\n' "postgres"
  printf 'export PGPASSWORD="%s"\n' "${POSTGRES_PASSWORD}"
  printf 'export PGDATABASE="%s"\n' "postgres"
  printf 'export PGHOST="%s"\n' "db"
  printf 'export PGPORT="%s"\n' "5432"
  printf 'export PGSSLMODE="%s"\n' "disable"
  printf 'export IS_GCP_CLOUD_SQL="%s"\n' "false"
  printf 'export CREATE_MIRROR_API_USER="%s"\n' "true"
  printf 'export GRAPHQL_PASSWORD="%s"\n' "${GRAPHQL_PASSWORD}"
  printf 'export GRPC_PASSWORD="%s"\n' "${GRPC_PASSWORD}"
  printf 'export IMPORTER_PASSWORD="%s"\n' "${IMPORTER_PASSWORD}"
  printf 'export OWNER_PASSWORD="%s"\n' "${OWNER_PASSWORD}"
  printf 'export REST_PASSWORD="%s"\n' "${REST_PASSWORD}"
  printf 'export REST_JAVA_PASSWORD="%s"\n' "${REST_JAVA_PASSWORD}"
  printf 'export ROSETTA_PASSWORD="%s"\n' "${ROSETTA_PASSWORD}"
  printf 'export WEB3_PASSWORD="%s"\n' "${WEB3_PASSWORD}"
  printf 'export DECOMPRESSOR_THREADS="%s"\n' "${DECOMPRESSOR_THREADS}"
} > "${BOOTSTRAP_ENV}"
chmod 600 "${BOOTSTRAP_ENV}"

echo "rendered config/application.yml and bootstrap.env"

if [[ "${generated_any}" == "true" ]]; then
  BACKUP_DIR="${SCRIPT_DIR}/secrets-backups"
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  BACKUP_FILE="${BACKUP_DIR}/env-$(date -u +%Y%m%dT%H%M%SZ).bak"
  cp "${ENV_FILE}" "${BACKUP_FILE}"
  chmod 600 "${BACKUP_FILE}"

  echo ""
  echo "=============================================================="
  echo "  NEW DATABASE SECRETS WERE JUST GENERATED"
  echo "=============================================================="
  echo "  A local copy was saved to:"
  echo "    ${BACKUP_FILE}"
  echo ""
  echo "  These passwords are set on PostgreSQL roles INSIDE the mirror"
  echo "  node database once you run ./bootstrap.sh init. If this .env"
  echo "  is later lost and configure.sh regenerates new passwords, the"
  echo "  new values will NOT match what's stored in the database, and"
  echo "  the importer/rest/relay services will fail to authenticate."
  echo "  Recovering from that means restoring a backup, manually"
  echo "  resetting the PostgreSQL role passwords, or wiping and"
  echo "  reimporting the entire multi-TB database from scratch."
  echo ""
  echo "  This file also contains your GCP credentials and, if set,"
  echo "  your relay operator private key. Copy it to a password"
  echo "  manager or other secure, offline storage now, then remove it"
  echo "  from this host if you don't want it here long-term."
  echo "=============================================================="
  if [[ -t 0 && -t 1 ]]; then
    read -r -p "  Press Enter once you have backed up this file securely: " _
  fi
fi

echo ""
echo "Next:"
if [[ -z "${GCP_PROJECT_ID}" || -z "${GCP_ACCESS_KEY}" || -z "${GCP_SECRET_KEY}" ]]; then
  echo "  edit .env and set GCP_PROJECT_ID, GCP_ACCESS_KEY, GCP_SECRET_KEY"
fi
if [[ "${READ_ONLY}" != "true" && ( -z "${OPERATOR_ID_MAIN}" || -z "${OPERATOR_KEY_MAIN}" ) ]]; then
  echo "  set OPERATOR_ID_MAIN and OPERATOR_KEY_MAIN, or set READ_ONLY=true"
fi
echo "  rerun ./configure.sh after editing .env"
echo "  ./bootstrap.sh download"
