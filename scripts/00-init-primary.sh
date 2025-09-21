#!/usr/bin/env bash
set -euo pipefail

MARK=/var/lib/postgresql/data/.primary_bootstrap_done
if [[ -f "$MARK" ]]; then
  echo "[primary] already bootstrapped."
  exit 0
fi

# wait for server up
until pg_isready -U postgres -h 127.0.0.1 -p 5432; do
  echo "[primary] waiting for postgres..."
  sleep 2
done

echo "[primary] creating users/roles."

psql -U postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user WITH LOGIN PASSWORD 'app_password';
    GRANT CONNECT ON DATABASE healthcare_db TO app_user;
  END IF;
END$$;
SQL

# ensure replication slot for each replica (optional but good)
psql -U postgres -d postgres -c "SELECT pg_create_physical_replication_slot('slot_replica1') WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'slot_replica1');" || true
psql -U postgres -d postgres -c "SELECT pg_create_physical_replication_slot('slot_replica2') WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'slot_replica2');" || true

touch "$MARK"
echo "[primary] bootstrap done."
