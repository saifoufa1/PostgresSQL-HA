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

PGDATA="${PGDATA:-/var/lib/postgresql/pgdata}"
NODE_NAME="${PGAF_NODE_NAME:-$(hostname)}"
DEFAULT_HOSTNAME="${HOSTNAME:-${NODE_NAME}}"
NODE_HOSTNAME="${PGAF_NODE_HOSTNAME:-${DEFAULT_HOSTNAME}}"
NODE_PORT="${PGAF_NODE_PORT:-5432}"
NODE_LISTEN="${PGAF_NODE_LISTEN:-0.0.0.0}"
NODE_AUTH="${PGAF_NODE_AUTH:-trust}"
FORMATION="${PGAF_NODE_FORMATION:-default}"
NODE_PRIORITY="${PGAF_NODE_CANDIDATE_PRIORITY:-50}"
REPLICATION_QUORUM="${PGAF_NODE_REPLICATION_QUORUM:-true}"
NODE_CLIENT_CIDR="${PGAF_NODE_CLIENT_CIDR:-${PG_HBA_CIDR:-172.28.0.0/24}}"
MONITOR_URI="${PG_AUTOCTL_MONITOR:-${PG_AUTOCTL_MONITOR_URI:-}}"
CONFIG_FILE="${HOME}/.config/pg_autoctl${PGDATA}/pg_autoctl.cfg"

if [[ -z "${MONITOR_URI}" ]]; then
  echo "[pgaf-keeper] PG_AUTOCTL_MONITOR not set" >&2
  exit 1
fi

mkdir -p "${PGDATA}"
if [[ "${EUID}" -eq 0 ]]; then
  chown postgres:postgres "${PGDATA}"
fi

add_hba_entry() {
  local entry="host all all ${NODE_CLIENT_CIDR} ${NODE_AUTH}"
  if [[ -f "${PGDATA}/pg_hba.conf" ]] && ! grep -Fq "${entry}" "${PGDATA}/pg_hba.conf"; then
    printf '%s\n' "${entry}" >> "${PGDATA}/pg_hba.conf"
    run_pg pg_ctl -D "${PGDATA}" reload || true
  fi
}

if [[ ! -f "${PGDATA}/PG_VERSION" || ! -f "${CONFIG_FILE}" ]]; then
  echo "[pgaf-keeper] creating pg_auto_failover node ${NODE_NAME}"
  create_args=(
    --pgdata "${PGDATA}"
    --monitor "${MONITOR_URI}"
    --hostname "${NODE_HOSTNAME}"
    --pgport "${NODE_PORT}"
    --name "${NODE_NAME}"
    --formation "${FORMATION}"
    --auth "${NODE_AUTH}"
    --ssl-self-signed
    --candidate-priority "${NODE_PRIORITY}"
    --replication-quorum "${REPLICATION_QUORUM}"
  )
  if [[ -n "${NODE_LISTEN}" ]]; then
    create_args+=(--listen "${NODE_LISTEN}")
  fi
  run_pg pg_autoctl create postgres "${create_args[@]}"
fi

add_hba_entry

if [[ "${PGAF_BOOTSTRAP:-false}" == "true" ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    gosu postgres /opt/pgaf/primary-bootstrap.sh &
  else
    /opt/pgaf/primary-bootstrap.sh &
  fi
fi

echo "[pgaf-keeper] starting keeper for ${NODE_NAME}"
if [[ "${EUID}" -eq 0 ]]; then
  exec gosu postgres pg_autoctl run --pgdata "${PGDATA}"
else
  exec pg_autoctl run --pgdata "${PGDATA}"
fi