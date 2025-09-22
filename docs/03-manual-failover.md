# Manual Failover Procedures

This document describes manual failover procedures for planned maintenance, testing, and emergency situations in the PostgreSQL High Availability solution.

## Overview

Manual failover allows administrators to:
- **Perform planned maintenance** on primary nodes
- **Test failover procedures** in controlled environments
- **Handle complex failure scenarios** not covered by automation
- **Migrate workloads** between nodes for load balancing

## When to Use Manual Failover

### Planned Maintenance
- **Operating system updates** requiring node reboots
- **Hardware maintenance** or upgrades
- **PostgreSQL version upgrades**
- **Configuration changes** requiring restarts

### Testing Scenarios
- **Failover testing** in staging environments
- **Application compatibility** verification
- **Performance benchmarking** during transitions
- **Disaster recovery drills**

### Emergency Situations
- **Automated failover failures** requiring intervention
- **Complex network issues** affecting multiple nodes
- **Data corruption** requiring selective recovery
- **Performance issues** requiring workload redistribution

## Manual Failover Process

### Prerequisites

1. **Verify cluster health** before starting
2. **Ensure all nodes are reachable** and responding
3. **Check replication status** and lag
4. **Notify application teams** of planned maintenance
5. **Prepare rollback plan** if needed

### Pre-Failover Health Check

```bash
# 1. Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Verify replication health
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"

# 3. Check node priorities
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, nodename, reportedstate, goalstate, health FROM pgautofailover.node;"

# 4. Verify monitoring stack
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9187/metrics | head -5
```

### Method 1: Controlled Failover (Recommended)

#### Step 1: Check Current State

```bash
# Get current cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

Expected output:
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
    }
  ]
}
```

#### Step 2: Perform Controlled Failover

```bash
# Execute controlled failover
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# Monitor the transition
echo "Monitoring controlled failover..."
for i in {1..6}; do
  echo "Attempt $i/6..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done
```

#### Step 3: Verify New State

```bash
# Check final state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Test new primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), now();"

# Verify application connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action, context) VALUES ('admin', 'manual_failover_test', '{\"test\": true}');"

# Verify data persistence
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM audit_log WHERE actor = 'admin' ORDER BY created_at DESC LIMIT 1;"
```

### Method 2: Node-by-Node Migration

#### Step 1: Identify Target Node

```bash
# Check available nodes and priorities
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, nodename, reportedstate, goalstate, health FROM pgautofailover.node ORDER BY nodeid;"

# Select target node (should be healthy secondary)
TARGET_NODE="postgres-replica1"
echo "Target node: $TARGET_NODE"
```

#### Step 2: Stop Current Primary

```bash
# Gracefully stop current primary
CURRENT_PRIMARY="postgres-primary"
docker compose --env-file .env stop $CURRENT_PRIMARY

# Wait for failover detection
sleep 15
```

#### Step 3: Verify Promotion

```bash
# Check if target node was promoted
for i in {1..6}; do
  echo "Check $i/6..."
  STATE=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r ".nodes[] | select(.nodename == \"node2\") | .reportedstate")
  echo "Node2 state: $STATE"
  if [ "$STATE" = "primary" ]; then
    echo "✓ Target node promoted successfully"
    break
  fi
  sleep 5
done
```

#### Step 4: Restart Old Primary as Replica

```bash
# Restart old primary (should rejoin as replica)
docker compose --env-file .env start $CURRENT_PRIMARY

# Verify it rejoins as secondary
sleep 30
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

### Method 3: Emergency Manual Promotion

#### When to Use
- **Automated failover failed**
- **Monitor node unavailable**
- **Network partition scenarios**
- **Critical application requirements**

#### Step 1: Identify Healthiest Replica

```bash
# Check all nodes status
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Check replication lag on each replica
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), pg_last_wal_receive_time(), pg_last_wal_replay_time(), now() - pg_last_wal_replay_time() as replay_lag;"

PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5434 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), pg_last_wal_receive_time(), pg_last_wal_replay_time(), now() - pg_last_wal_replay_time() as replay_lag;"
```

#### Step 2: Promote Replica Manually

```bash
# Connect to target replica
TARGET_REPLICA="postgres-replica1"

# Promote using pg_promote() (if monitor is unavailable)
docker compose --env-file .env exec $TARGET_REPLICA \
  psql -U postgres -d healthcare_db \
  -c "SELECT pg_promote();"

# Verify promotion
docker compose --env-file .env exec $TARGET_REPLICA \
  psql -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery();"
```

#### Step 3: Update Monitor Configuration

```bash
# Update monitor to recognize new primary
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "UPDATE pgautofailover.node SET reportedstate = 'primary' WHERE nodename = 'node2';"

# Verify cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

## Rollback Procedures

### Scenario 1: Failover Issues

```bash
# 1. Check current state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Perform controlled failover back to original primary
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 3. Verify rollback
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

### Scenario 2: Application Issues

```bash
# 1. Check application connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT version(), pg_is_in_recovery();"

# 2. If issues persist, perform controlled failover
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 3. Test application with new primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action) VALUES ('admin', 'rollback_test');"
```

## Testing Manual Failover

### Test Script Example

```bash
#!/bin/bash
set -euo pipefail

echo "Starting manual failover test..."

# 1. Pre-failover health check
echo "✓ Pre-failover health check"
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Perform controlled failover
echo "✓ Performing controlled failover"
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 3. Monitor transition
echo "✓ Monitoring transition..."
for i in {1..6}; do
  echo "Check $i/6..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | {name: .nodename, state: .reportedstate}'
  sleep 5
done

# 4. Verify new primary
echo "✓ Verifying new primary"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), version();"

# 5. Test data consistency
echo "✓ Testing data consistency"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action) VALUES ('test_user', 'manual_failover_test');"

# 6. Verify audit log
COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM audit_log WHERE actor = 'test_user';" | tail -3 | head -1 | tr -d ' ')

echo "✓ Manual failover test completed successfully!"
echo "✓ Records preserved: $COUNT"
```

### Performance Measurement

```bash
# Measure manual failover time
START=$(date +%s.%3N)

# Perform failover
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# Monitor completion
while true; do
  STATE=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.nodename == "node2") | .reportedstate')
  if [ "$STATE" = "primary" ]; then
    END=$(date +%s.%3N)
    DURATION=$(echo "$END - $START" | bc)
    echo "Manual failover completed in $DURATION seconds"
    break
  fi
  sleep 0.1
done
```

## Monitoring During Manual Failover

### Real-time Monitoring

```bash
# Monitor cluster state continuously
watch -n 2 'docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq'

# Monitor PostgreSQL logs
docker compose --env-file .env logs -f postgres-primary

# Monitor system resources
docker stats
```

### Prometheus Metrics

```bash
# Check failover metrics
curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code | jq

# Monitor replication lag
curl -s http://localhost:9090/api/v1/query?query=pg_stat_replication_replay_lag_bytes | jq
```

## Troubleshooting Manual Failover

### Common Issues

#### 1. Failover Command Fails

```bash
# Check monitor connectivity
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT 1;"

# Check node states
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Verify no nodes are in unknown state
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;"
```

#### 2. New Primary Not Accepting Connections

```bash
# Check if promoted node is ready
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), pg_roles.role_name FROM pg_roles WHERE role_name = 'postgres';"

# Check for configuration issues
docker compose --env-file .env logs postgres-replica1

# Verify network connectivity
docker compose --env-file .env exec postgres-replica1 \
  netstat -tlnp | grep 5432
```

#### 3. Old Primary Not Rejoining

```bash
# Check old primary logs
docker compose --env-file .env logs postgres-primary

# Verify monitor connectivity from old primary
docker compose --env-file .env exec postgres-primary \
  pg_isready -h pgaf-monitor -p 5431 -U autoctl_node

# Check replication slots
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_replication_slots;"
```

## Best Practices

### 1. Planning
- **Schedule during low-traffic periods**
- **Notify all stakeholders** in advance
- **Have rollback plan** ready
- **Test procedures** in staging first

### 2. Execution
- **Monitor throughout** the process
- **Verify each step** before proceeding
- **Document any issues** encountered
- **Test application connectivity** after completion

### 3. Post-Failover
- **Verify data consistency** across all nodes
- **Update connection strings** if needed
- **Monitor performance** for 24-48 hours
- **Document lessons learned**

### 4. Emergency Procedures
- **Have emergency contacts** ready
- **Know when to abort** and rollback
- **Document all manual changes** made
- **Test restoration** from backups if needed

## Conclusion

Manual failover provides administrators with control over the failover process for planned maintenance and complex scenarios. While automated failover handles most failure cases, manual procedures are essential for:

- **Planned maintenance** requiring controlled transitions
- **Testing failover procedures** in safe environments
- **Emergency situations** requiring human intervention
- **Complex scenarios** not covered by automation

Always test manual procedures in staging environments before executing in production, and maintain detailed documentation of all steps taken during the process.

For automated failover procedures, see the [Automated Failover Documentation](02-automated-failover.md).