#!/usr/bin/env bash
set -euo pipefail

FORMATION="${PGAF_FORMATION:-default}"
GROUP="${PGAF_GROUP:-0}"
MONITOR_URI="${PG_AUTOCTL_MONITOR:-postgresql://autoctl_node@pgaf-monitor:5431/pg_auto_failover}"

if [[ -z "${MONITOR_URI}" ]]; then
  echo "[pgaf-failover] PG_AUTOCTL_MONITOR is required" >&2
  exit 1
fi

echo "[pgaf-failover] requesting failover on formation=${FORMATION}, group=${GROUP}"
pg_autoctl perform failover --formation "${FORMATION}" --group "${GROUP}" --monitor "${MONITOR_URI}"
