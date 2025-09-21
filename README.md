# Operations Runbook for PostgreSQL HA Lab

This runbook documents how to stand up, operate, and evaluate the PostgreSQL high-availability lab shipped in this repository. It centralises the compose topology, helper scripts, and testing guidance into a single operational reference.

---

## 1. Environment and Setup

### 1.1 Prerequisites
- Docker Engine 20.10+
- Docker Compose plugin 2.0+
- At least 8 GB RAM and 50 GB free disk space on the host
- Host ports 5432-5434, 9090, and 9187 available (or adjust port mappings)

### 1.2 Topology Overview
Component | Role | Container | Static IP | Host Port
--------- | ---- | --------- | --------- | ---------
Primary database | Accepts reads and writes | postgres-primary | 172.28.0.10 | 5432
Replica #1 | Hot standby, preferred promotion target | postgres-replica1 | 172.28.0.11 | 5433
Replica #2 | Hot standby, optional for drills | postgres-replica2 | 172.28.0.12 | 5434
Postgres exporter | Metrics translator | postgres-exporter | 172.28.0.20 | 9187
Prometheus | Metrics collection | prometheus | 172.28.0.21 | 9090

Default credentials are defined in `.env.test` (`postgres/postgres_password`, `replicator/replicator_password`, `admin/admin`). Adjust as needed before bringing the stack online.

### 1.3 First-Time Startup
```bash
# from repo root
cp .env.test .env  # optional: tweak before copying
docker compose up -d

# observe container state
watch "docker compose ps"
```
On first boot `postgres-primary` initialises `$PGDATA`, copies the custom configuration, applies the schema (`sql/01-schema.sql`), loads sample data (`sql/02-test-data.sql`), and creates replication roles. Each replica performs `pg_basebackup` and enters recovery mode.

### 1.4 Verifying the Cluster
```bash
# check replication sessions
PGPASSWORD=postgres_password psql -h 127.0.0.1 -U postgres -c "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"

# confirm metrics endpoints
curl http://localhost:9187/metrics | head
open http://localhost:9090
```
A healthy state shows two rows in `pg_stat_replication` with `state = 'streaming'` and `pg_stat_replication_replay_lag_bytes` near zero for both standbys.

---

## 2. Failover Procedures

### 2.1 Automated Failover
Automated failover tooling is **not** bundled with this lab. To achieve unattended failover, integrate an orchestrator such as Patroni, pg_auto_failover, or Stolon and adjust the compose stack accordingly. Until then, alerting should escalate to an operator who can follow the manual procedure below.

### 2.2 Manual Planned Failover
1. Drain or pause write traffic to the cluster.
2. Stop the current primary to simulate an outage:
   ```bash
   docker compose stop postgres-primary
   ```
3. Promote Replica #1 (recommended target):
   ```bash
   docker exec postgres-replica1 bash -lc "/scripts/90-failover-promote.sh"
   docker compose exec postgres-replica1 psql -U postgres -c "SELECT pg_is_in_recovery();"  # expect 'f'
   ```
4. Redirect clients to Replica #1 (`172.28.0.11:5432` inside the network or host port `5433`).
5. Keep Replica #2 online to preserve redundancy.

### 2.3 Emergency Failover (Primary crash)
1. Detect failure via exporter metrics, Prometheus alerts, or container health checks.
2. Ensure the failed container is stopped: `docker compose stop postgres-primary`.
3. Promote Replica #1 using the same script as above.
4. Confirm Replica #2 is still connected; if not, rejoin it using the recovery steps below.

---

## 3. Recovery Procedures

### 3.1 Rejoining the Former Primary as a Standby
After promoting Replica #1:
```bash
docker compose start postgres-primary
docker exec postgres-primary bash -lc "/scripts/91-rejoin-as-standby.sh postgres-replica1 5432"
```
The rejoin script issues a fast stop, wipes `$PGDATA`, performs `pg_basebackup` from the supplied primary, writes recovery settings, and starts PostgreSQL in standby mode. Verify with `pg_is_in_recovery()` (should return `'t'`).

### 3.2 Re-adding Replica #2
- If it was stopped intentionally: `docker compose start postgres-replica2`.
- If it remained running during the failover, re-clone it to avoid divergence:
  ```bash
  docker exec postgres-replica2 bash -lc "/scripts/91-rejoin-as-standby.sh postgres-replica1 5432"
  ```

### 3.3 Failing Back to the Original Primary
1. Once the former primary has caught up, plan a second brief maintenance window.
2. Promote the standby you want to lead (for example, the rejoined original primary).
3. Rejoin the other nodes using the rejoin script so they follow the new leader.
4. Update connection strings or load balancer targets accordingly.

---

## 4. Monitoring and Observability

### 4.1 Prometheus
- UI: `http://localhost:9090`
- Useful queries:
  - `up{job="postgres"}` — exporter scrape health
  - `pg_stat_replication_replay_lag_bytes` — replication delay
  - `pg_stat_database_xact_commit{datname="healthcare_db"}` — write throughput
- To extend visualisation, add Grafana and point it at Prometheus (`172.28.0.21:9090`).

### 4.2 Postgres Exporter
- Endpoint: `http://localhost:9187/metrics`
- Authenticates with the `postgres` superuser against whichever node is primary.
- After a failover, confirm the exporter sees the new primary; if metrics disappear, restart `postgres-exporter`.

### 4.3 Routine Operational Checks
- `docker compose ps` — container health and port bindings
- `docker compose logs -f postgres-primary` — init scripts, replication slot creation, errors
- `psql -c "SELECT * FROM pg_stat_activity"` — active sessions during investigations

---

## 5. Limitations and Future Improvements

Limitation | Impact | Suggested Improvement
---------- | ------ | ---------------------
No automated failover | Manual intervention required, longer RTO | Integrate Patroni/pg_auto_failover and add distributed consensus
Static credentials and permissive CIDR | Not production-safe | Externalise secrets, tighten `pg_hba.conf`, enable TLS
Single Prometheus instance, no alerting | Limited visibility when unattended | Add Alertmanager, Grafana dashboards, alert rules for lag and node death
Local Docker volumes only | Loss of host means data loss | Mount replicated storage or remote volumes, add scheduled backups
Manual schema/data loading on boot | Risk of drift as scripts evolve | Adopt a migration tool (Flyway/Liquibase) and move seeding to versioned migrations

Additional enhancements: introduce connection pooling (PgBouncer), front replicas with HAProxy or Pgpool-II for read routing, implement WAL archiving and point-in-time recovery drills, and add automated smoke tests post-failover.

---

## 6. Time Budget Reference (Challenge Guidance)
- Setup and verification: ~20 minutes
- Manual failover drill: ~10 minutes
- Failback drill: ~10 minutes
- Monitoring review and notes: ~10 minutes

This aligns with the suggested 30–45 minute documentation window while leaving room to expand on automation or monitoring.
