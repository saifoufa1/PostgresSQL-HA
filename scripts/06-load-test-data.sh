#!/usr/bin/env bash
set -euo pipefail

MARK=/var/lib/postgresql/data/.test_data_loaded
if [[ -f "$MARK" || "${LOAD_TEST_DATA:-false}" != "true" ]]; then
  echo "[seed] skipped (mark exists or LOAD_TEST_DATA!=true)."; exit 0; fi

until pg_isready -U ${POSTGRES_SUPERUSER:-postgres} -h 127.0.0.1 -p 5432; do
  echo "[seed] waiting for postgres..."; sleep 2; done

echo "[seed] loading sql/02-test-data.sql ..."
psql -v ON_ERROR_STOP=1 -U ${POSTGRES_SUPERUSER:-postgres} -f /sql/02-test-data.sql

touch "$MARK"
echo "[seed] done."
