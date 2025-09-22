#!/usr/bin/env bash
set -euo pipefail

MARK=/var/lib/postgresql/data/.schema_applied
if [[ -f "$MARK" || "${LOAD_SCHEMA:-false}" != "true" ]]; then
  echo "[schema] skipped (mark exists or LOAD_SCHEMA!=true)."; exit 0; fi

until pg_isready -U ${POSTGRES_SUPERUSER:-postgres} -h 127.0.0.1 -p 5432; do
  echo "[schema] waiting for postgres..."; sleep 2; done

# Ensure healthcare_db exists
echo "[schema] ensuring healthcare_db exists..."
DB_EXISTS=$(psql -U ${POSTGRES_SUPERUSER:-postgres} -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='healthcare_db';" 2>/dev/null || echo "0")
if [[ "${DB_EXISTS}" != "1" ]]; then
  echo "[schema] creating healthcare_db database..."
  psql -v ON_ERROR_STOP=1 -U ${POSTGRES_SUPERUSER:-postgres} -d postgres <<SQL
CREATE DATABASE healthcare_db;
SQL
else
  echo "[schema] healthcare_db already exists."
fi

echo "[schema] applying sql/01-schema.sql ..."
psql -v ON_ERROR_STOP=1 -U ${POSTGRES_SUPERUSER:-postgres} -d healthcare_db -f /sql/01-schema.sql

# create app user and basic grants (schema already grants to postgres per file)
psql -v ON_ERROR_STOP=1 -U ${POSTGRES_SUPERUSER:-postgres} -d healthcare_db <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_USER:-app_user}') THEN
    CREATE ROLE ${APP_USER:-app_user} WITH LOGIN PASSWORD '${APP_PASSWORD:-app_password}';
  END IF;
  GRANT CONNECT ON DATABASE healthcare_db TO ${APP_USER:-app_user};
  GRANT USAGE ON SCHEMA public TO ${APP_USER:-app_user};
  GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO ${APP_USER:-app_user};
  GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${APP_USER:-app_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO ${APP_USER:-app_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${APP_USER:-app_user};
END\$\$;
SQL

touch "$MARK"
echo "[schema] done."
