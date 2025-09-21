#!/usr/bin/env bash
set -euo pipefail

echo "[hardening] applying safer defaults for prod-like runs..."

DATA_DIR=/var/lib/postgresql/data
CONF="$DATA_DIR/postgresql.conf"
HBA="$DATA_DIR/pg_hba.conf"

# Lower log verbosity
sed -ri "s/^(#?\s*log_statement\s*=\s*).*/\1'${LOG_LEVEL:-ddl}'/" "$CONF" || true

# Lock pg_hba to CIDR
CIDR="${PG_HBA_CIDR:-172.18.0.0/16}"
sed -i '/^host\s/s/0\.0\.0\.0\/0/'"$CIDR"'/' "$HBA" || true

# (Optional) force app password change at boot (if provided)
if [[ -n "${APP_PASSWORD:-}" && "${APP_PASSWORD}" != "app_password" ]]; then
  psql -U ${POSTGRES_SUPERUSER:-postgres} -d healthcare_db \
    -c "ALTER ROLE ${APP_USER:-app_user} WITH PASSWORD '${APP_PASSWORD}';" || true
fi

echo "[hardening] done."
