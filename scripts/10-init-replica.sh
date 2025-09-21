#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/var/lib/postgresql/data
PRIMARY_HOST="${PRIMARY_HOST:-postgres-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator_password}"

if [[ -s "$DATA_DIR/PG_VERSION" ]]; then
  echo "[replica] data dir already initialized; skipping basebackup."
else
  echo "[replica] waiting for primary readiness..."
  until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U postgres; do
    echo "[replica] primary not ready yet..."
    sleep 2
  done

  echo "[replica] performing pg_basebackup..."
  export PGPASSWORD="$REPL_PASSWORD"
  rm -rf "$DATA_DIR"/*

  attempt=0
  until pg_basebackup \
    -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" \
    -D "$DATA_DIR" -U "$REPL_USER" \
    -v -P -X stream --write-recovery-conf; do
    attempt=$((attempt+1))
    if [[ $attempt -ge 5 ]]; then
      echo "[replica] pg_basebackup failed after $attempt attempts; giving up." >&2
      exit 1
    fi
    echo "[replica] basebackup failed; retrying in 5s..."
    sleep 5
    rm -rf "$DATA_DIR"/*
  done

  SLOT="slot_replica1"
  if hostname | grep -q "replica2"; then SLOT="slot_replica2"; fi

  cat >> "$DATA_DIR/postgresql.auto.conf" <<EOF
primary_slot_name = '${SLOT}'
EOF

  cp /etc/postgresql/conf.d/postgresql.conf "$DATA_DIR/postgresql.conf" || true
fi
