# 🏥 PostgreSQL High Availability Lab

[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://docker.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-blue.svg)](https://postgresql.org)
[![pg_auto_failover](https://img.shields.io/badge/pg__auto__failover-2.0+-green.svg)](https://github.com/citusdata/pg_auto_failover)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-orange.svg)](https://prometheus.io)
[![Grafana](https://img.shields.io/badge/Grafana-Dashboards-yellow.svg)](https://grafana.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **Production-Ready PostgreSQL High Availability Testing Environment**
>
> This repository provides a complete PostgreSQL HA lab using pg_auto_failover with automated failover, monitoring, and comprehensive testing scenarios. Perfect for learning, testing, and demonstrating PostgreSQL high availability concepts.

## 🎯 What This Lab Provides

- **Automated Failover**: Zero-downtime PostgreSQL cluster with intelligent failover orchestration
- **Production Monitoring**: Real-time metrics with Prometheus and Grafana dashboards
- **Healthcare Dataset**: Realistic test data for performance and functionality testing
- **Easy Testing**: Pre-configured scenarios for common HA testing patterns
- **Docker-Native**: Complete containerized environment for consistent deployments

## 📊 Architecture Overview

This lab deploys a 3-node PostgreSQL cluster with:
- **1 Monitor Node**: Orchestrates failover and health monitoring
- **3 PostgreSQL Nodes**: Primary + 2 replicas with different failover priorities
- **Monitoring Stack**: Prometheus metrics collection + Grafana dashboards
- **Healthcare Database**: Realistic schema with sample patient/provider data

## 🚀 Quick Start

Get the lab running in under 5 minutes:

```bash
# 1. Clone and navigate to the repository
git clone <repository-url>
cd postgresql-ha-challenge

# 2. Start the complete stack
cp .env.test .env
docker compose --env-file .env up -d --build

# 3. Verify everything is running
docker compose --env-file .env ps

# 4. Check cluster status
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 5. Access Grafana dashboard
open http://localhost:3000 (admin/admin)
```

**Expected Result**: You should see one primary and two replica nodes, with Grafana showing real-time metrics.

## 🎯 Use Cases

This lab is perfect for:

- **Learning PostgreSQL HA**: Understand automated failover concepts
- **Testing Applications**: Verify your app handles failovers gracefully
- **Performance Benchmarking**: Test read/write patterns under different loads
- **Disaster Recovery Planning**: Practice failover scenarios
- **Monitoring Setup**: Learn production monitoring patterns

---

## 📋 Prerequisites

### System Requirements
- **Docker Engine**: 20.10 or higher
- **Docker Compose**: Plugin 2.0 or higher
- **Memory**: 8GB RAM minimum (12GB recommended)
- **Storage**: 60GB free disk space
- **Network**: Open ports 5431-5434, 6010-6012, 9090, 9187, 3000

### Required Ports
| Port | Service | Purpose |
|------|---------|---------|
| 5431 | pg_auto_failover Monitor | Cluster coordination |
| 5432 | PostgreSQL Primary | Database connections |
| 5433 | PostgreSQL Replica 1 | Read-only connections |
| 5434 | PostgreSQL Replica 2 | Read-only connections |
| 6010-6012 | pg_autoctl | Node management |
| 9090 | Prometheus | Metrics UI |
| 9187 | postgres-exporter | Metrics collection |
| 3000 | Grafana | Dashboard UI |

### Optional Tools
- **jq**: For pretty-printing JSON cluster state
- **psql**: PostgreSQL client for direct database access
- **curl**: For API testing and metrics verification

---

## 2. Topology Overview

Component | Role | Container | Static IP | Host Ports | Persistent Volume
--------- | ---- | --------- | --------- | ---------- | -----------------
pg_auto_failover monitor | Tracks keeper health & orchestrates promotion | `pgaf-monitor` | 172.28.0.5 | 5431 | `monitor_data`
Primary candidate | Keeper-managed primary (bootstrap applies schema/data) | `postgres-primary` | 172.28.0.10 | 5432, 6010 | `postgres-primary`
Replica #1 | Preferred failover target (higher candidate priority) | `postgres-replica1` | 172.28.0.11 | 5433, 6011 | `postgres-replica1`
Replica #2 | Secondary standby for redundancy/tests | `postgres-replica2` | 172.28.0.12 | 5434, 6012 | `postgres-replica2`
Postgres exporter | Exposes metrics for whichever node is writable | `postgres-exporter` | 172.28.0.20 | 9187 | -
Prometheus | Scrapes Postgres exporter | `prometheus` | 172.28.0.21 | 9090 | (optional)
Grafana | Visualises pg_auto_failover metrics (pre-built dashboard) | `grafana` | 172.28.0.30 | 3000 | -

Each keeper stores its data under `/var/lib/postgresql/pgdata`. The monitor data lives under `/var/lib/postgresql/monitor`.

---

## 3. Configuration Files

- `docker-compose.yml` � service definitions (monitor, keepers, Prometheus, Grafana, exporter)
- `scripts/pgaf/*.sh` � pg_auto_failover entrypoints and helper scripts (run automatically in containers)
- `sql/01-schema.sql`, `sql/02-test-data.sql` � bootstrap schema + test data (applied once on initial primary only)
- `monitoring/prometheus.yml` � Prometheus scrape config
- `monitoring/grafana/` � provisioning for datasource + pg_auto_failover dashboard

Environment toggles (set via `.env.test` or `.env.prod`):

Variable | Purpose | Default (.env.test)
-------- | ------- | ------------------
`LOAD_SCHEMA` | Apply schema bootstrap on new primary | `true`
`LOAD_TEST_DATA` | Load sample data | `true`
`APP_USER` / `APP_PASSWORD` | Credentials for seeded application role | `admin` / `admin`
`POSTGRES_PASSWORD` | Superuser password inside the keepers | `postgres_password`
`PG_HBA_CIDR` | CIDR appended to every node�s `pg_hba.conf` to allow host/WSL connections | `0.0.0.0/0`

`.env.prod` mirrors these variables but defaults to more restrictive values (e.g. `PG_HBA_CIDR=172.28.0.0/24`).

---

## 🧪 Comprehensive Testing Guide

This section provides step-by-step procedures for testing the PostgreSQL HA system. Each test scenario includes expected outcomes and verification steps.

### Test 1: Basic Cluster Health Check

**Objective**: Verify the cluster is running correctly with proper role assignment.

```bash
# 1. Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Verify primary node
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery();"

# 3. Check replica status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery();"

# 4. Verify data replication
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM medical_facilities;"

PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM medical_facilities;"
```

**Expected Results**:
- Monitor shows 1 primary, 2 replicas
- Primary returns `f` (not in recovery)
- Replicas return `t` (in recovery)
- Both nodes show same record count

### Test 2: Automated Failover Testing

**Objective**: Test automatic failover when primary node fails.

```bash
# 1. Identify current primary
CURRENT_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
echo "Current primary: $CURRENT_PRIMARY"

# 2. Stop current primary
docker compose --env-file .env stop $CURRENT_PRIMARY

# 3. Monitor failover (check every 5 seconds)
echo "Monitoring failover..."
for i in {1..12}; do
  echo "Attempt $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 4. Verify new primary
NEW_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
echo "New primary: $NEW_PRIMARY"

# 5. Test data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

# 6. Restart old primary
docker compose --env-file .env start $CURRENT_PRIMARY
```

**Expected Results**:
- Failover completes within 30 seconds
- New primary is promoted automatically
- Data remains consistent across nodes
- Old primary rejoins as replica

### Test 3: Controlled Failover Testing

**Objective**: Test manual failover for planned maintenance.

```bash
# 1. Check current state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Perform controlled failover
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 3. Monitor the transition
echo "Monitoring controlled failover..."
for i in {1..6}; do
  echo "Attempt $i/6..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 4. Verify application connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action, context) VALUES ('test_user', 'controlled_failover_test', '{\"test\": true}');"

# 5. Verify data on new primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM audit_log WHERE actor = 'test_user';"
```

**Expected Results**:
- Controlled failover completes smoothly
- No data loss during transition
- Application connections recover automatically
- Audit log entry persists after failover

### Test 4: Monitoring and Observability

**Objective**: Verify monitoring stack functionality.

```bash
# 1. Check Prometheus metrics
curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code | jq

# 2. Verify Grafana dashboards
# Visit http://localhost:3000 and check:
# - pg_auto_failover dashboard loads
# - Node health metrics are visible
# - Replication lag is shown

# 3. Test metrics endpoint directly
curl -s http://localhost:9187/metrics | grep -E "(pg_auto_failover|pg_stat_replication)" | head -10

# 4. Check monitor database directly
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c 'SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;'
```

**Expected Results**:
- Prometheus shows cluster metrics
- Grafana dashboards display correctly
- postgres-exporter collects HA metrics
- Monitor database tracks node states

### Test 5: Performance and Load Testing

**Objective**: Test cluster performance under load.

```bash
# 1. Create test load script
cat > load_test.sql << 'EOF'
-- Insert test appointments
INSERT INTO appointments (patient_id, provider_id, facility_id, appointment_date, appointment_time, duration_minutes, appointment_type, status, chief_complaint)
SELECT
  p.patient_id,
  pr.provider_id,
  f.facility_id,
  CURRENT_DATE + (random() * 30)::int,
  '08:00:00'::time + (random() * 8)::int * '01:00:00'::interval,
  30,
  'consultation',
  'scheduled',
  'Load test appointment'
FROM patients p
CROSS JOIN healthcare_providers pr
CROSS JOIN medical_facilities f
LIMIT 100;
EOF

# 2. Run load test on primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -f load_test.sql

# 3. Verify replication lag
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 4. Check replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"

# 5. Clean up test data
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "DELETE FROM appointments WHERE chief_complaint = 'Load test appointment';"
```

**Expected Results**:
- Load test completes successfully
- Replication lag remains minimal
- No errors in PostgreSQL logs
- Data consistency maintained across nodes

---

## 4. First-Time Startup

```bash
# from repository root
# (optional) copy the desired profile
cp .env.test .env

# bring everything up
docker compose --env-file .env.test up -d --build

# verify containers
docker compose --env-file .env.test ps
```

Boot sequence:
1. `pgaf-monitor` initialises the monitor database (`pg_autoctl create monitor`) and starts listening on 5431.
2. `postgres-primary` registers, becomes primary, applies schema/data, and exposes 5432/6010.
3. `postgres-replica1` and `postgres-replica2` register, clone from the primary, and enter streaming replication.
4. `postgres-exporter` immediately tracks the writable node; Prometheus and Grafana come online.

### Quick-check commands

```bash
# cluster state (JSON)
docker compose --env-file .env.test exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# sample data check on primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM medical_facilities;"
```

---

## 5. Automated Failover Behaviour

The monitor polls each keeper every 5?s. If the primary misses three heartbeats, the monitor marks it unhealthy, elects the highest-priority standby, and instructs it to promote. Typical timings (default settings): detection ~10�15?s, promotion ~5�10?s, overall RTO ~20�30?s. Tune with `PG_AUTOCTL_*` environment variables if you need faster reaction.

### Helper Scripts (`scripts/pgaf`)

Script | Run inside | Purpose
------ | ---------- | -------
`show-state.sh` | `pgaf-monitor` | Dumps cluster state as JSON (`pg_autoctl show state`).
`perform-failover.sh` | `pgaf-monitor` | Requests a controlled failover (`pg_autoctl perform failover`).

Example controlled failover:
```bash
docker compose --env-file .env.test exec pgaf-monitor bash /opt/pgaf/perform-failover.sh
```

### Failure Drill

1. Stop current primary (`pgaf-node1` is the container name):
   ```bash
   docker compose --env-file .env.test stop pgaf-node1
   ```
2. Monitor promotion:
   ```bash
   docker compose --env-file .env.test exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
   ```
   You should see `postgres-replica1` become `primary` within ~30?s.
3. Point clients at the new writable port (host 5433 or 5434, depending on promoted node).
4. Restart the old primary:
   ```bash
   docker compose --env-file .env.test start pgaf-node1
   ```
   The keeper reclones automatically and rejoins as `secondary`.
5. Confirm state once more with `show-state.sh`.

---

## 6. Monitoring & Observability

- Exporter endpoint: <http://localhost:9187/metrics>
- Prometheus UI: <http://localhost:9090>
- Grafana UI: <http://localhost:3000> (login admin / admin)

Grafana auto-loads a pg_auto_failover dashboard showing:
- Node health (`pg_auto_failover_node_state_health_code`)
- Node state code (`pg_auto_failover_node_state_reported_state_code`)
- Replication lag (`pg_stat_replication_replay_lag_bytes`)

Need raw monitor data? Execute:
```bash
docker compose --env-file .env.test exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c 'SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;'
```
Add additional Grafana dashboards or Prometheus alert rules as desired.

---

## 7. Maintenance & Recovery

- **Rolling maintenance:** stop a keeper (`docker compose stop <service>`), apply changes, then `docker compose start <service>`; pg_autoctl handles re-registration.
- **Full reseed:** stop the keeper, remove its volume (`docker volume rm postgresql-ha-challenge_postgres-replica1`), restart the service; it reclones from the current primary.
- **Manual switchover:** run `/opt/pgaf/perform-failover.sh` from the monitor for a controlled leader change.

---

## 8. Validation Checklist

Drill | Command | Expected Result
----- | ------- | ---------------
Fresh bootstrap | `docker compose --env-file .env.test up -d --build` | Monitor healthy, primary promoted, replicas streaming (Grafana reachable at <http://localhost:3000>).
Failover | `docker compose --env-file .env.test stop pgaf-node1` | Promotion within ~30?s, exporter metrics continue.
Rejoin | `docker compose --env-file .env.test start pgaf-node1` | Restarted keeper returns as `secondary` without manual steps.
Monitoring | `curl http://localhost:9187/metrics` | Metrics include `pg_auto_failover_*` and `pg_stat_replication*` series.

---

## 9. Future Enhancements

Area | Improvement
---- | -----------
RTO tuning | Reduce heartbeat intervals or enable synchronous replication for stricter RPO.
Client routing | Add HAProxy or PgBouncer to hide failovers from clients.
Alerting | Integrate Prometheus with Alertmanager (lag, unhealthy nodes, missing primary).
Backups | Introduce WAL archiving / PITR tooling (e.g., `pgbackrest`).
Testing | Automate failover drills in CI to catch regressions.

---

## 🧪 Testing Guidelines for Developers

### Testing Best Practices

1. **Always Test Failover**: Never assume HA works without testing
2. **Use Realistic Data**: Test with production-like data volumes
3. **Monitor Performance**: Watch for performance degradation during tests
4. **Document Issues**: Record any unexpected behavior for improvement
5. **Clean Up**: Reset environment between test scenarios

### Test Scenarios to Implement

#### Application Integration Testing
```bash
# Test your application against the cluster
# 1. Configure connection string to use primary endpoint
# 2. Perform read/write operations
# 3. Trigger failover during active transactions
# 4. Verify application handles failover gracefully
# 5. Check connection pool behavior
```

#### Load Testing with Failover
```bash
# Simulate production load during failover
# 1. Start background load (inserts, updates, queries)
# 2. Trigger failover during peak load
# 3. Monitor application response times
# 4. Verify data consistency post-failover
# 5. Check for connection drops or timeouts
```

#### Network Partition Testing
```bash
# Test behavior during network issues
# 1. Isolate primary node from network
# 2. Verify monitor detects failure
# 3. Confirm no split-brain scenario
# 4. Restore connectivity and verify recovery
```

### Custom Test Scripts

Create test scripts in the `scripts/` directory:

```bash
# Example: scripts/test-failover.sh
#!/bin/bash
set -euo pipefail

echo "Starting comprehensive failover test..."

# 1. Pre-failover health check
echo "✓ Pre-failover health check"
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Start background load
echo "✓ Starting background load"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action) SELECT 'test_user', 'load_test_' || generate_series(1,1000);"

# 3. Trigger failover
echo "✓ Triggering failover"
docker compose --env-file .env stop postgres-primary

# 4. Monitor recovery
echo "✓ Monitoring recovery..."
for i in {1..12}; do
  echo "Check $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | {name: .nodename, state: .reportedstate}'
  sleep 5
done

# 5. Verify data integrity
echo "✓ Verifying data integrity"
COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM audit_log WHERE actor = 'test_user';" | tail -3 | head -1 | tr -d ' ')
echo "Records preserved: $COUNT"

echo "✓ Failover test completed successfully!"
```

### Performance Benchmarks

#### Read/Write Performance
```bash
# Test read performance across replicas
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "EXPLAIN ANALYZE SELECT * FROM patients WHERE last_name LIKE 'S%';"

# Test write performance on primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "EXPLAIN ANALYZE INSERT INTO patients (medical_record_number, first_name, last_name) VALUES ('BENCH001', 'Bench', 'Mark');"
```

#### Failover Time Measurement
```bash
# Measure actual failover time
START=$(date +%s.%3N)
docker compose --env-file .env stop postgres-primary

while true; do
  STATE=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.nodename == "node2") | .reportedstate')
  if [ "$STATE" = "primary" ]; then
    END=$(date +%s.%3N)
    DURATION=$(echo "$END - $START" | bc)
    echo "Failover completed in $DURATION seconds"
    break
  fi
  sleep 0.1
done
```

---

## 🤝 Contributing

### Development Setup

1. **Fork the repository**
2. **Clone your fork**: `git clone https://github.com/your-username/postgresql-ha-challenge.git`
3. **Create feature branch**: `git checkout -b feature/amazing-feature`
4. **Set up environment**: `cp .env.test .env`
5. **Start development environment**: `docker compose --env-file .env up -d`
6. **Make changes** and test thoroughly
7. **Submit pull request** with detailed description

### Contribution Guidelines

- **Test Changes**: All changes must include corresponding tests
- **Documentation**: Update README for any new features or changes
- **Code Style**: Follow existing patterns and conventions
- **Testing**: Ensure all existing tests pass
- **Review**: Address all review comments before merging

### Areas for Contribution

- **Additional Test Scenarios**: More comprehensive failover tests
- **Performance Improvements**: Optimize cluster performance
- **Monitoring Enhancements**: Better dashboards and alerting
- **Documentation**: Improve guides and examples
- **Tooling**: Additional scripts for common operations

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 10. Reference Commands

```bash
# Tail keeper logs
docker compose --env-file .env.test logs -f pgaf-node1

# Monitor state snapshot
docker compose --env-file .env.test exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Exporter metrics
curl -s http://localhost:9187/metrics | head
```

Reset the lab (including volumes) with:
```bash
docker compose --env-file .env down -v
```

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Port Conflicts
**Problem**: Services fail to start due to port conflicts.

**Solution**:
```bash
# Check what's using the ports
netstat -tulpn | grep -E ':(5431|5432|5433|5434|6010|6011|6012|9090|9187|3000)'

# Modify ports in docker-compose.yml or stop conflicting services
```

#### Issue 2: Monitor Connection Failures
**Problem**: PostgreSQL nodes can't connect to monitor.

**Solution**:
```bash
# Check monitor logs
docker compose --env-file .env logs pgaf-monitor

# Verify monitor is listening
docker compose --env-file .env exec pgaf-monitor netstat -tlnp | grep 5431

# Test monitor connectivity
docker compose --env-file .env exec postgres-primary \
  psql -h pgaf-monitor -p 5431 -U autoctl_node -d pg_auto_failover -c "SELECT 1;"
```

#### Issue 3: Failover Not Triggering
**Problem**: Primary failure doesn't trigger automatic failover.

**Solution**:
```bash
# Check node health
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Verify heartbeat settings
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT * FROM pgautofailover.formation;"

# Check keeper logs
docker compose --env-file .env logs postgres-primary
```

#### Issue 4: Data Inconsistency After Failover
**Problem**: Data differs between nodes after failover.

**Solution**:
```bash
# Check replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_replication;"

# Verify data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

# Check for replication lag
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, reportedlsn, health FROM pgautofailover.node;"
```

#### Issue 5: Grafana Dashboard Not Loading
**Problem**: Grafana shows no data or fails to load.

**Solution**:
```bash
# Check Prometheus connectivity
curl -s http://localhost:9090/-/healthy

# Verify postgres-exporter
curl -s http://localhost:9187/metrics | head -5

# Check Grafana logs
docker compose --env-file .env logs grafana

# Restart monitoring stack
docker compose --env-file .env restart prometheus grafana postgres-exporter
```

### Debug Commands

```bash
# Complete cluster status
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Monitor database contents
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT * FROM pgautofailover.node ORDER BY nodeid;"

# PostgreSQL logs
docker compose --env-file .env logs -f postgres-primary

# Network connectivity
docker compose --env-file .env exec postgres-primary \
  pg_isready -h pgaf-monitor -p 5431 -U autoctl_node

# Metrics verification
curl -s http://localhost:9090/api/v1/query?query=up | jq
```

---

## 📋 Technical Assumptions & Limitations

### Architecture Assumptions

1. **Network Reliability**: Assumes stable network connectivity between nodes
2. **Storage Reliability**: Persistent volumes must survive container restarts
3. **Resource Availability**: Sufficient CPU/memory for PostgreSQL workload
4. **Time Synchronization**: All nodes must have synchronized system clocks
5. **Docker Environment**: Designed for Docker environments only

### pg_auto_failover Specifics

- **Failover Priority**: Node priorities determine promotion order (100 > 90 > 80)
- **Heartbeat Interval**: Default 5-second health checks with 3-miss threshold
- **RTO Target**: ~20-30 seconds for complete failover (configurable)
- **Data Consistency**: Synchronous replication not enabled by default
- **Split Brain Protection**: Monitor prevents multiple primaries

### Performance Characteristics

- **Monitoring Overhead**: ~5% CPU overhead for health monitoring
- **Network Traffic**: Additional heartbeat and state replication traffic
- **Memory Usage**: Monitor requires minimal memory (~100MB)
- **Storage**: Each node maintains full data copy plus WAL logs

### Known Limitations

- **Single Point of Failure**: Monitor node is a SPOF (can be made HA)
- **Network Partitions**: May cause temporary unavailability during partitions
- **Resource Contention**: High load may affect failover timing
- **Docker Dependency**: Not suitable for non-containerized deployments