#!/usr/bin/env bash
set -euo pipefail

echo "Initializing replication users and settings…"

REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator_password}"
MONITOR_USER="${MONITOR_USER:-monitor}"
MONITOR_PASSWORD="${MONITOR_PASSWORD:-monitor_password}"

# Create roles if missing + set cluster-level replication settings
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$REPL_USER') THEN
      EXECUTE format('CREATE ROLE %I WITH REPLICATION LOGIN ENCRYPTED PASSWORD %L', '$REPL_USER', '$REPL_PASSWORD');
   END IF;

   IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$MONITOR_USER') THEN
      EXECUTE format('CREATE ROLE %I WITH LOGIN ENCRYPTED PASSWORD %L', '$MONITOR_USER', '$MONITOR_PASSWORD');
   END IF;
END
\$\$;

-- Grant minimal access to monitor
GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO "$MONITOR_USER";
GRANT USAGE ON SCHEMA public TO "$MONITOR_USER";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "$MONITOR_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "$MONITOR_USER";

-- Ensure replication GUCs are set (persisted in postgresql.auto.conf)
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = '10';
ALTER SYSTEM SET max_replication_slots = '10';
ALTER SYSTEM SET hot_standby = 'on';
ALTER SYSTEM SET wal_keep_size = '1024MB';
SQL

# Safely append pg_hba rules (once)
HBA_FILE="$PGDATA/pg_hba.conf"
add_hba() {
  local line="$1"
  grep -Fqx "$line" "$HBA_FILE" 2>/dev/null || echo "$line" >> "$HBA_FILE"
}

echo "# Replication access" >> "$HBA_FILE"
add_hba "host    replication     ${REPL_USER}      0.0.0.0/0          md5"
add_hba "host    replication     ${REPL_USER}      ::/0               md5"
add_hba "host    all             all               0.0.0.0/0          md5"
add_hba "host    all             all               ::/0               md5"

echo "Replication init done."
