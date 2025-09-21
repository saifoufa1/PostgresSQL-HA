#!/usr/bin/env bash
set -euo pipefail

# Run this inside the *old* primary after the new primary is up.
# Example:
# docker exec -it postgres-primary bash -lc "/scripts/91-rejoin-as-standby.sh new-primary-host"

NEW_PRIMARY_HOST="${1:-postgres-replica1}"
NEW_PRIMARY_PORT="${2:-5432}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator_password}"
DATA_DIR=/var/lib/postgresql/data

echo "[rejoin] stopping postgres..."
pg_ctl -D "$DATA_DIR" -m fast stop || true

echo "[rejoin] wiping old data and re-cloning..."
rm -rf "$DATA_DIR"/*
export PGPASSWORD="$REPL_PASSWORD"
pg_basebackup -h "$NEW_PRIMARY_HOST" -p "$NEW_PRIMARY_PORT" \
  -D "$DATA_DIR" -U "$REPL_USER" -v -P -X stream --write-recovery-conf

# become standby again
echo "[rejoin] starting postgres as standby..."
postgres -D "$DATA_DIR" -c config_file="$DATA_DIR/postgresql.conf"
