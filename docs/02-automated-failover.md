# Automated Failover Procedures

This document describes the automated failover mechanisms in the PostgreSQL High Availability solution using pg_auto_failover.

## Overview

The automated failover system provides zero-downtime database operations by automatically detecting failures and promoting healthy replica nodes to primary status.

## How Automated Failover Works

### Architecture Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   pgaf-monitor  │────│ pg_auto_failover │────│ PostgreSQL Nodes│
│   (172.28.0.5)  │    │    monitor       │    │                 │
│ - Health checks │    │ - State tracking │    │ - Primary       │
│ - Failover coord│    │ - Node management│    │ - Replicas      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Key Components

1. **Monitor Node**: Central coordination and health monitoring
2. **Keeper Processes**: Run on each PostgreSQL node, report health status
3. **pg_auto_failover**: Orchestrates failover decisions and node promotion

### Health Monitoring

The monitor polls each keeper every **5 seconds**:
- **Healthy**: Keeper responds within timeout
- **Unhealthy**: Keeper misses 3 consecutive heartbeats
- **Detection Time**: ~10-15 seconds for failure detection

## Failover Process

### Automatic Failover Sequence

1. **Detection Phase** (10-15 seconds)
   - Monitor detects primary node failure
   - Confirms failure with multiple missed heartbeats
   - Marks primary node as unhealthy

2. **Election Phase** (5-10 seconds)
   - Monitor evaluates available replica nodes
   - Selects highest priority healthy replica
   - Priority order: 100 > 90 > 80

3. **Promotion Phase** (5-10 seconds)
   - Selected replica is promoted to primary
   - New primary accepts write connections
   - postgres-exporter updates to new primary

4. **Recovery Phase** (30+ seconds)
   - Failed node rejoins as replica when restored
   - Automatic resynchronization begins
   - Cluster returns to full redundancy

### Total Recovery Time Objective (RTO)

- **Typical RTO**: 20-30 seconds
- **Configurable**: Can be tuned for faster response
- **Factors**: Network latency, system resources, data volume

## Node Priorities

### Current Configuration

| Node | Container | Priority | Role | Port |
|------|-----------|----------|------|------|
| node1 | postgres-primary | 100 | Primary | 5432 |
| node2 | postgres-replica1 | 90 | Replica | 5433 |
| node3 | postgres-replica2 | 80 | Replica | 5434 |

### Priority Behavior

- **Highest Priority Wins**: Node with priority 100 is preferred for promotion
- **Automatic Selection**: Monitor chooses highest available priority
- **No Manual Override**: Priorities are enforced automatically

## Monitoring Automated Failover

### Real-time Status

```bash
# Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Monitor specific node
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;"
```

### Expected JSON Output

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

### Health Status Codes

| Code | State | Description |
|------|-------|-------------|
| 1 | Healthy | Node responding normally |
| 0 | Unhealthy | Node not responding |
| -1 | Unknown | Node state cannot be determined |

## Testing Automated Failover

### Prerequisites

Ensure cluster is healthy before testing:
```bash
# Verify initial state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

### Test Scenario 1: Primary Failure

```bash
# 1. Identify current primary
CURRENT_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
echo "Current primary: $CURRENT_PRIMARY"

# 2. Stop current primary
docker compose --env-file .env stop $CURRENT_PRIMARY

# 3. Monitor failover process
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

### Test Scenario 2: Network Partition

```bash
# 1. Isolate primary node
docker compose --env-file .env stop postgres-primary

# 2. Monitor automatic failover
for i in {1..6}; do
  echo "Check $i/6..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 3. Restore connectivity
docker compose --env-file .env start postgres-primary
```

### Test Scenario 3: Load During Failover

```bash
# 1. Start background load
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action) SELECT 'test_user', 'load_test_' || generate_series(1,1000);"

# 2. Trigger failover during load
docker compose --env-file .env stop postgres-primary

# 3. Monitor recovery
for i in {1..12}; do
  echo "Check $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done

# 4. Verify data integrity
COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM audit_log WHERE actor = 'test_user';" | tail -3 | head -1 | tr -d ' ')
echo "Records preserved: $COUNT"
```

## Expected Results

### Successful Failover

- **Detection**: 10-15 seconds
- **Promotion**: 5-10 seconds
- **Total RTO**: 20-30 seconds
- **Data Consistency**: All committed transactions preserved
- **Application Impact**: Brief connection interruption

### Failed Failover Scenarios

1. **No Healthy Replicas**
   - Monitor cannot promote any node
   - Cluster enters read-only mode
   - Manual intervention required

2. **Split Brain**
   - Network partition creates multiple primaries
   - Monitor prevents this automatically
   - Manual resolution may be needed

3. **Resource Exhaustion**
   - Insufficient memory/CPU for promotion
   - Failover may timeout
   - Requires system resource scaling

## Configuration Tuning

### Faster Failover

```bash
# Environment variables for faster response
PG_AUTOCTL_HEARTBEAT=3  # Reduce heartbeat interval (default: 5s)
PG_AUTOCTL_TIMEOUT=2    # Reduce timeout threshold (default: 3 missed heartbeats)
```

### Slower, More Stable Failover

```bash
# Environment variables for stability
PG_AUTOCTL_HEARTBEAT=10  # Increase heartbeat interval
PG_AUTOCTL_TIMEOUT=5     # Increase timeout threshold
```

## Monitoring and Alerting

### Prometheus Metrics

```bash
# Check failover metrics
curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code | jq

# Monitor replication lag
curl -s http://localhost:9090/api/v1/query?query=pg_stat_replication_replay_lag_bytes | jq
```

### Grafana Dashboard

Access the pre-configured dashboard at http://localhost:3000:
- **Node Health**: Real-time status of all nodes
- **Replication Lag**: Lag monitoring across replicas
- **Failover Events**: Historical failover tracking
- **Performance Metrics**: System resource usage

## Troubleshooting Automated Failover

### Common Issues

#### 1. Failover Not Triggering

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

#### 2. Slow Failover

```bash
# Check system resources
docker stats

# Monitor promotion process
docker compose --env-file .env logs -f pgaf-monitor

# Check replication lag
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_replication;"
```

#### 3. Data Inconsistency

```bash
# Check replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_replication;"

# Verify data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"
```

## Best Practices

### 1. Regular Testing
- Test failover monthly in staging
- Document any issues or unexpected behavior
- Verify application compatibility

### 2. Monitoring Setup
- Configure alerts for failover events
- Monitor replication lag continuously
- Track system resource usage

### 3. Performance Optimization
- Ensure adequate system resources
- Monitor for resource contention
- Regular performance benchmarking

### 4. Backup Strategy
- Implement regular backups
- Test backup restoration procedures
- Document recovery time objectives

## Recovery Procedures

If automated failover fails or behaves unexpectedly:

1. **Manual intervention** may be required
2. **Check monitor logs** for detailed error information
3. **Verify network connectivity** between all nodes
4. **Ensure adequate resources** for promotion
5. **Contact support** if issues persist

## Conclusion

The automated failover system provides robust, zero-downtime database operations with typical recovery times of 20-30 seconds. Regular testing and monitoring are essential for maintaining optimal performance and reliability.

For manual failover procedures, see the [Manual Failover Documentation](03-manual-failover.md).