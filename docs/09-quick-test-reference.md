# Quick Test Reference Guide

## Overview

This quick reference guide provides developers with fast access to the most common failover testing procedures and commands.

## Quick Start

### 1. Environment Setup
```bash
# Navigate to project directory
cd postgresql-ha-challenge

# Copy test environment
cp .env.test .env

# Start the cluster
docker compose --env-file .env up -d --build

# Wait for initialization (60 seconds)
sleep 60
```

### 2. Run Comprehensive Tests
```bash
# Option 1: Using bash script (Linux/Mac/Git Bash)
./scripts/test-comprehensive-failover.sh

# Option 2: Using batch script (Windows)
scripts\run-failover-tests.bat
```

### 3. Manual Testing Commands

#### Check Cluster State
```bash
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

#### Test Database Connectivity
```bash
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT version(), pg_is_in_recovery();"
```

#### Check Replication Status
```bash
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_replication;"
```

## Common Test Scenarios

### Scenario 1: Basic Health Check
```bash
# 1. Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Verify primary node
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT pg_is_in_recovery();"

# 3. Check replica status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db -c "SELECT pg_is_in_recovery();"

# 4. Verify data replication
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM medical_facilities;"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM medical_facilities;"
```

### Scenario 2: Automated Failover Test
```bash
# 1. Identify current primary
CURRENT_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
echo "Current primary: $CURRENT_PRIMARY"

# 2. Stop current primary
docker compose --env-file .env stop $CURRENT_PRIMARY

# 3. Monitor failover
for i in {1..12}; do
  echo "Attempt $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 4. Verify new primary
NEW_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
echo "New primary: $NEW_PRIMARY"

# 5. Test data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM patients;"

# 6. Restart old primary
docker compose --env-file .env start $CURRENT_PRIMARY
```

### Scenario 3: Manual Failover Test
```bash
# 1. Check current state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Perform controlled failover
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 3. Monitor the transition
for i in {1..6}; do
  echo "Attempt $i/6..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 4. Verify application connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "INSERT INTO audit_log (actor, action, context) VALUES ('test_user', 'controlled_failover_test', '{\"test\": true}');"

# 5. Verify data on new primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM audit_log WHERE actor = 'test_user';"
```

### Scenario 4: Load Testing During Failover
```bash
# 1. Create test load script
cat > load_test.sql << 'EOF'
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
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"

# 5. Clean up test data
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "DELETE FROM appointments WHERE chief_complaint = 'Load test appointment';"
```

### Scenario 5: Monitoring Verification
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
docker compose --env-file .env exec pgaf-monitor psql -U postgres -d pg_auto_failover -c 'SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;'
```

## Monitoring Commands

### Real-time Monitoring
```bash
# Monitor cluster state continuously
watch -n 2 'docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq'

# Monitor PostgreSQL logs
docker compose --env-file .env logs -f postgres-primary

# Monitor system resources
docker stats
```

### Performance Monitoring
```bash
# System resource usage
docker stats

# PostgreSQL performance metrics
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_bgwriter;"

# Replication performance
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_replication;"
```

## Troubleshooting Commands

### Common Issues
```bash
# Check node health
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Verify heartbeat settings
docker compose --env-file .env exec pgaf-monitor psql -U postgres -d pg_auto_failover -c "SELECT * FROM pgautofailover.formation;"

# Check keeper logs
docker compose --env-file .env logs postgres-primary

# Test monitor connectivity
docker compose --env-file .env exec postgres-primary psql -h pgaf-monitor -p 5431 -U autoctl_node -d pg_auto_failover -c "SELECT 1;"

# Check replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_replication;"

# Verify data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM patients;"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM patients;"
```

### Debug Commands
```bash
# Complete cluster status
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Monitor database contents
docker compose --env-file .env exec pgaf-monitor psql -U postgres -d pg_auto_failover -c "SELECT * FROM pgautofailover.node ORDER BY nodeid;"

# PostgreSQL logs
docker compose --env-file .env logs -f postgres-primary

# Network connectivity
docker compose --env-file .env exec postgres-primary pg_isready -h pgaf-monitor -p 5431 -U autoctl_node

# Metrics verification
curl -s http://localhost:9090/api/v1/query?query=up | jq
```

## Cleanup Commands

### Reset Environment
```bash
# Stop all services
docker compose --env-file .env down

# Remove all volumes (WARNING: This deletes all data)
docker compose --env-file .env down -v

# Remove specific volumes
docker volume rm postgresql-ha-challenge_postgres-primary
docker volume rm postgresql-ha-challenge_postgres-replica1
docker volume rm postgresql-ha-challenge_postgres-replica2
docker volume rm postgresql-ha-challenge_monitor_data
```

### Clean Test Data
```bash
# Remove test appointments
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "DELETE FROM appointments WHERE chief_complaint = 'Load test appointment';"

# Remove test audit logs
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "DELETE FROM audit_log WHERE actor = 'test_user';"

# Reset sequences if needed
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT setval('appointments_appointment_id_seq', 1, false);"
```

## Expected Results

### Successful Failover
- **Detection**: 10-15 seconds
- **Promotion**: 5-10 seconds
- **Total RTO**: 20-30 seconds
- **Data Consistency**: All committed transactions preserved
- **Application Impact**: Brief connection interruption

### Cluster State
```json
{
  "nodes": [
    {
      "nodeid": 1,
      "nodename": "node1",
      "reportedstate": "primary",
      "health": 1
    },
    {
      "nodeid": 2,
      "nodename": "node2",
      "reportedstate": "secondary",
      "health": 1
    },
    {
      "nodeid": 3,
      "nodename": "node3",
      "reportedstate": "secondary",
      "health": 1
    }
  ]
}
```

## Quick Validation Checklist

- [ ] Cluster shows 1 primary, 2 replicas
- [ ] All nodes report health = 1
- [ ] Primary returns `pg_is_in_recovery() = false`
- [ ] Replicas return `pg_is_in_recovery() = true`
- [ ] Data counts match across all nodes
- [ ] Prometheus metrics are available
- [ ] Grafana dashboards load correctly
- [ ] postgres-exporter collects HA metrics

## Need Help?

For detailed information, see:
- **Full Guidelines**: `docs/08-failover-testing-guidelines.md`
- **Automated Failover**: `docs/02-automated-failover.md`
- **Manual Failover**: `docs/03-manual-failover.md`
- **Main README**: `README.md`

## Version Information

- **Document Version**: 1.0
- **Last Updated**: 2025-01-22
- **Tested With**: PostgreSQL 15, pg_auto_failover 2.0+