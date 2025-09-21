#!/usr/bin/env bash
set -euo pipefail

# Use inside the target replica container:
# docker exec -it postgres-replica1 bash -lc "/scripts/90-failover-promote.sh"

DATA_DIR=/var/lib/postgresql/data

echo "[failover] promoting standby to primary..."
pg_ctl -D "$DATA_DIR" promote

echo "[failover] promoted. New primary is $(hostname)."
# Optionally, you might want to reconfigure other replicas to follow the new primary.
