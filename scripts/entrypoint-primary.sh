#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=/etc/postgresql/conf.d/postgresql.conf
HBA_FILE=/etc/postgresql/conf.d/pg_hba.conf

/usr/local/bin/docker-entrypoint.sh postgres \
  -c config_file=${CONFIG_FILE} \
  -c hba_file=${HBA_FILE} &
pg_pid=$!

gosu_cleanup() {
  kill -SIGTERM "$pg_pid" 2>/dev/null || true
  wait "$pg_pid" 2>/dev/null || true
}
trap gosu_cleanup SIGINT SIGTERM

SUPERUSER="${POSTGRES_SUPERUSER:-${POSTGRES_USER:-postgres}}"

until pg_isready -U "$SUPERUSER" -h 127.0.0.1 -p 5432; do
  if ! kill -0 "$pg_pid" 2>/dev/null; then
    echo "[entrypoint] postgres process exited while waiting for readiness"
    wait "$pg_pid"
    exit 1
  fi
  echo "[entrypoint] waiting for postgres to accept connections..."
  sleep 2
done

echo "[entrypoint] running bootstrap helpers"
gosu postgres bash /scripts/05-init-schema.sh
gosu postgres bash /scripts/06-load-test-data.sh

if [[ "${LOAD_TEST_DATA:-}" == "false" ]]; then
  gosu postgres bash /scripts/99-hardening-prod.sh || true
fi

gosu postgres bash /scripts/00-init-primary.sh &

wait "$pg_pid"
