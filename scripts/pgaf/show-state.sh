#!/usr/bin/env bash
set -euo pipefail

FORMATION="${PGAF_FORMATION:-default}"
MONITOR_URI="${PG_AUTOCTL_MONITOR:-postgresql://autoctl_node@pgaf-monitor:5431/pg_auto_failover}"

pg_autoctl show state --formation "${FORMATION}" --monitor "${MONITOR_URI}" --json
