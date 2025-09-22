#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/lib/postgresql/15/bin:${PATH}"

PGDATA="${PGDATA:-/var/lib/postgresql/pgdata}"
MARK_FILE="${PGDATA}/.pgaf_bootstrap_done"
SUPERUSER="${POSTGRES_SUPERUSER:-${POSTGRES_USER:-postgres}}"
PORT="${PGAF_NODE_PORT:-5432}"
TARGET_DB="${POSTGRES_DB:-postgres}"

if [[ -f "${MARK_FILE}" ]]; then
  echo "[pgaf-bootstrap] marker exists; skipping bootstrap"
  exit 0
fi

echo "[pgaf-bootstrap] waiting for local postgres on port ${PORT}"
until pg_isready -p "${PORT}" -U "${SUPERUSER}" >/dev/null 2>&1; do
  sleep 2
done

echo "[pgaf-bootstrap] waiting for node to become primary"
until [[ "$(psql -p "${PORT}" -U "${SUPERUSER}" -d postgres -Atc 'SELECT NOT pg_is_in_recovery();')" == "t" ]]; do
  sleep 2
done

echo "[pgaf-bootstrap] configuring superuser credentials"
if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
  psql -p "${PORT}" -U "${SUPERUSER}" -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER USER ${SUPERUSER} WITH PASSWORD '${POSTGRES_PASSWORD}';"
fi

echo "[pgaf-bootstrap] creating databases"
export POSTGRES_SUPERUSER="${SUPERUSER}"
/scripts/04-create-database.sh

if [[ "${TARGET_DB}" != "postgres" ]]; then
  DB_EXISTS=$(psql -p "${PORT}" -U "${SUPERUSER}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='${TARGET_DB}';")
  if [[ "${DB_EXISTS}" != "1" ]]; then
    echo "[pgaf-bootstrap] creating database ${TARGET_DB}"
    psql -p "${PORT}" -U "${SUPERUSER}" -d postgres -v ON_ERROR_STOP=1 \
      -c "CREATE DATABASE \"${TARGET_DB}\" OWNER ${SUPERUSER};"
  fi
fi

export POSTGRES_SUPERUSER="${SUPERUSER}"
export LOAD_SCHEMA="${LOAD_SCHEMA:-true}"
export LOAD_TEST_DATA="${LOAD_TEST_DATA:-true}"
export APP_USER="${APP_USER:-app_user}"
export APP_PASSWORD="${APP_PASSWORD:-app_password}"

echo "[pgaf-bootstrap] applying schema"
/scripts/05-init-schema.sh

echo "[pgaf-bootstrap] applying seed data"
/scripts/06-load-test-data.sh

touch "${MARK_FILE}"
echo "[pgaf-bootstrap] bootstrap complete"
