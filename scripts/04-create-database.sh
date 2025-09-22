#!/usr/bin/env bash
set -euo pipefail

MARK=/var/lib/postgresql/data/.database_created
if [[ -f "$MARK" ]]; then
  echo "[database] skipped (mark exists)."; exit 0; fi

until pg_isready -U ${POSTGRES_SUPERUSER:-postgres} -h 127.0.0.1 -p 5432; do
  echo "[database] waiting for postgres..."; sleep 2; done

echo "[database] checking if healthcare_db exists..."

# Check if database exists
if psql -U ${POSTGRES_SUPERUSER:-postgres} -lqt | cut -d \| -f 1 | grep -qw healthcare_db; then
  echo "[database] healthcare_db already exists, skipping creation."
else
  echo "[database] healthcare_db does not exist, creating..."
  psql -v ON_ERROR_STOP=1 -U ${POSTGRES_SUPERUSER:-postgres} <<SQL
CREATE DATABASE healthcare_db;
SQL
  echo "[database] healthcare_db created successfully."
fi

touch "$MARK"
echo "[database] done."