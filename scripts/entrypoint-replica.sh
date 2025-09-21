#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=/etc/postgresql/conf.d/postgresql.conf

bash /scripts/10-init-replica.sh

exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c config_file=${CONFIG_FILE}
