### Target Topology (pg_auto_failover Based)

| Component            | Container name       | Role / Notes                                                                 | Ports (container) | Host map | Persistent volume                |
|----------------------|----------------------|-------------------------------------------------------------------------------|-------------------|----------|----------------------------------|
| Monitor              | `pgaf-monitor`       | Runs pg_auto_failover monitor (single instance for lab).                      | 5431               | n/a or 5431 | `monitor_data`                  |
| Data node #1         | `pgaf-node1`         | Postgres instance managed by `pg_autoctl run` (initial primary).             | 5432, 6010         | 5432      | `node1_data`                     |
| Data node #2         | `pgaf-node2`         | Postgres instance managed by `pg_autoctl run` (standby).                     | 5432, 6011         | 5433      | `node2_data`                     |
| Postgres exporter    | `postgres-exporter`  | Scrapes whichever node is primary (update DSN after auto-failover).          | 9187               | 9187      | —                                |
| Prometheus           | `prometheus`         | Monitors exporter; can add alert rules for pg_auto_failover state/lag.       | 9090               | 9090      | `prometheus_data` (optional)     |

**Networking**
- Single custom Docker network `postgres-cluster` with subnet `172.28.0.0/24` (reuse current scheme).
- Static assignments recommended for stability:
  - `pgaf-monitor` → `172.28.0.5`
  - `pgaf-node1` → `172.28.0.10`
  - `pgaf-node2` → `172.28.0.11`
  - `postgres-exporter` → `172.28.0.20`
  - `prometheus` → `172.28.0.21`
- Monitor listens on 5431 (default for pg_auto_failover).
- Keepers need both Postgres port (5432) and the node-to-monitor port (default 6010/6011) exposed inside the network.

**Process Layout**
- Monitor container runs `pg_autoctl monitor` with persistent state (Postgres + metadata).
- Each data node runs `pg_autoctl run` (keeper) as PID 1; the keeper launches/stops the actual postgresql instance.
- Keeper registration command: `pg_autoctl create postgres --name <node> --hostname <ip> --pgport 5432 --monitor postgresql://autoctl_node@pgaf-monitor:5431/pg_auto_failover ...`
- Use a dedicated user (`autoctl_node`) for monitor authentication (password via env or file).

**Volumes**
- `monitor_data` → `/var/lib/postgresql/data` (monitor’s Postgres state)
- `node1_data`, `node2_data` → `/var/lib/postgresql/15/main` (or pg_autoctl default) to persist database data.
- Prometheus optional volume if we want to persist configuration/state beyond the config file.

**Environment & Credentials**
- Monitor DB superuser: reuse `postgres/postgres_password` or set dedicated `autoctl`. Need to expose credentials to keepers via URI.
- Application superuser: continue using `postgres/postgres_password` inside data nodes; initial schema/data load will run once (see later steps).
- `pg_autoctl` CLI requires locale + gnupg; ensure image has them.

Let me know if this table matches your expectations before I start rewriting `docker-compose.yml`.
