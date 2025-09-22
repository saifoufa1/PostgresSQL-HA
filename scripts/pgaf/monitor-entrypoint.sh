#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/lib/postgresql/15/bin:${PATH}"
export HOME="/var/lib/postgresql"
umask 077

run_pg() {
  if [[ "${EUID}" -eq 0 ]]; then
    gosu postgres "$@"
  else
    "$@"
  fi
}

PGDATA="${PGDATA:-/var/lib/postgresql/monitor}"
MONITOR_PORT="${PGAF_MONITOR_PORT:-5431}"
DEFAULT_HOSTNAME="${HOSTNAME:-pgaf-monitor}"
MONITOR_HOSTNAME="${PGAF_MONITOR_HOSTNAME:-${DEFAULT_HOSTNAME}}"
MONITOR_LISTEN="${PGAF_MONITOR_LISTEN:-0.0.0.0}"
MONITOR_AUTH="${PGAF_MONITOR_AUTH:-trust}"
MONITOR_CLIENT_CIDR="${PGAF_CLIENT_CIDR:-${PG_HBA_CIDR:-172.28.0.0/24}}"
CONFIG_FILE="${HOME}/.config/pg_autoctl${PGDATA}/pg_autoctl.cfg"

mkdir -p "${PGDATA}"
if [[ "${EUID}" -eq 0 ]]; then
  chown postgres:postgres "${PGDATA}"
fi

add_hba_entry() {
  local entry="host all all ${MONITOR_CLIENT_CIDR} ${MONITOR_AUTH}"
  if [[ -f "${PGDATA}/pg_hba.conf" ]] && ! grep -Fq "${entry}" "${PGDATA}/pg_hba.conf"; then
    printf '%s\n' "${entry}" >> "${PGDATA}/pg_hba.conf"
    run_pg pg_ctl -D "${PGDATA}" reload || true
  fi
}

if [[ ! -f "${PGDATA}/PG_VERSION" || ! -f "${CONFIG_FILE}" ]]; then
  echo "[pgaf-monitor] initializing monitor cluster at ${PGDATA}"
  create_args=(
    --pgdata "${PGDATA}"
    --hostname "${MONITOR_HOSTNAME}"
    --pgport "${MONITOR_PORT}"
    --auth "${MONITOR_AUTH}"
    --ssl-self-signed
  )
  if [[ -n "${MONITOR_LISTEN}" ]]; then
    create_args+=(--listen "${MONITOR_LISTEN}")
  fi
  run_pg pg_autoctl create monitor "${create_args[@]}"
fi

add_hba_entry

export PG_AUTOCTL_MONITOR="postgresql://autoctl_node@${MONITOR_HOSTNAME}:${MONITOR_PORT}/pg_auto_failover"

echo "[pgaf-monitor] starting monitor"
if [[ "${EUID}" -eq 0 ]]; then
  exec gosu postgres pg_autoctl run --pgdata "${PGDATA}"
else
  exec pg_autoctl run --pgdata "${PGDATA}"
fi