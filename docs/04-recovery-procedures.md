# Recovery Procedures

This document provides comprehensive recovery procedures for various failure scenarios in the PostgreSQL High Availability solution.

## Overview

Recovery procedures cover:
- **Node recovery** after failures
- **Data recovery** from corruption or loss
- **Cluster recovery** from multi-node failures
- **Monitor recovery** when coordination fails
- **Backup and restore** operations

## Recovery Scenarios

### Scenario Classification

| Severity | Description | Recovery Time | Data Loss Risk |
|----------|-------------|---------------|----------------|
| **Minor** | Single replica failure | 5-15 minutes | None |
| **Moderate** | Primary failure with healthy replicas | 20-30 seconds | None |
| **Major** | Monitor failure | 1-5 minutes | None |
| **Critical** | Multiple node failures | 30+ minutes | Possible |
| **Catastrophic** | Complete cluster failure | Hours | Likely |

## Node Recovery Procedures

### Automatic Node Recovery

#### Replica Node Recovery

1. **Detection**: Monitor detects unhealthy replica
2. **Automatic Recovery**: Node attempts self-healing
3. **Rejoin Process**: Node reconnects to cluster automatically

```bash
# Monitor replica recovery
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Check replica logs during recovery
docker compose --env-file .env logs -f postgres-replica1
```

#### Primary Node Recovery

1. **Failover**: Automatic promotion of healthy replica
2. **Recovery**: Failed primary rejoins as replica
3. **Resync**: Automatic data synchronization

```bash
# Monitor primary recovery process
for i in {1..12}; do
  echo "Check $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 5
done
```

### Manual Node Recovery

#### Step 1: Assess Damage

```bash
# Check all nodes status
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Check individual node health
docker compose --env-file .env ps

# Verify data integrity on remaining nodes
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"
```

#### Step 2: Isolate Failed Node

```bash
# Stop the failed node
FAILED_NODE="postgres-replica1"
docker compose --env-file .env stop $FAILED_NODE

# Verify cluster stability
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

#### Step 3: Data Recovery Options

**Option A: Volume Preservation**
```bash
# Restart with existing data
docker compose --env-file .env start $FAILED_NODE

# Monitor rejoin process
sleep 30
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

**Option B: Full Reseed**
```bash
# Remove existing volume
docker volume rm postgresql-ha-challenge_$FAILED_NODE

# Restart node (will reclone from primary)
docker compose --env-file .env start $FAILED_NODE

# Monitor resync progress
for i in {1..20}; do
  echo "Check $i/20..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 10
done
```

## Data Recovery Procedures

### Point-in-Time Recovery (PITR)

#### Prerequisites
- **WAL Archiving**: Must be configured
- **Base Backups**: Regular backup schedule
- **Archive Location**: Accessible storage for WAL files

#### Recovery Steps

1. **Stop Failed Node**
```bash
docker compose --env-file .env stop postgres-replica1
```

2. **Prepare Recovery**
```bash
# Create recovery configuration
cat > recovery.conf << 'EOF'
restore_command = 'cp /var/lib/postgresql/archive/%f %p'
recovery_target_time = '2024-01-15 10:00:00'
EOF
```

3. **Start Recovery**
```bash
# Mount recovery config and start node
docker compose --env-file .env start postgres-replica1
```

### Schema and Data Recovery

#### From Backup Files

```bash
# 1. Stop target node
docker compose --env-file .env stop postgres-replica1

# 2. Remove existing volume
docker volume rm postgresql-ha-challenge_postgres-replica1

# 3. Start node (will reclone from primary)
docker compose --env-file .env start postgres-replica1

# 4. Monitor recovery
for i in {1..10}; do
  echo "Recovery check $i/10..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 10
done
```

#### Manual Schema Restoration

```bash
# Connect to recovered node
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d postgres << 'EOF'
-- Recreate schema if needed
\i /sql/01-schema.sql

-- Restore application user
CREATE USER admin WITH PASSWORD 'admin';
GRANT ALL PRIVILEGES ON DATABASE healthcare_db TO admin;
EOF
```

## Cluster Recovery Procedures

### Partial Cluster Recovery

#### Scenario: One Node Failed

```bash
# 1. Identify failed node
FAILED_NODE=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.health == 0) | .nodename')
echo "Failed node: $FAILED_NODE"

# 2. Stop failed node
docker compose --env-file .env stop $FAILED_NODE

# 3. Remove volume for clean recovery
docker volume rm postgresql-ha-challenge_$FAILED_NODE

# 4. Restart node
docker compose --env-file .env start $FAILED_NODE

# 5. Monitor recovery
for i in {1..15}; do
  echo "Recovery check $i/15..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 10
done
```

#### Scenario: Multiple Nodes Failed

```bash
# 1. Assess cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Identify healthy nodes
HEALTHY_NODES=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.health == 1) | .nodename')
echo "Healthy nodes: $HEALTHY_NODES"

# 3. Stop all failed nodes
docker compose --env-file .env stop postgres-replica1 postgres-replica2

# 4. Clean volumes for failed nodes
docker volume rm postgresql-ha-challenge_postgres-replica1
docker volume rm postgresql-ha-challenge_postgres-replica2

# 5. Restart failed nodes
docker compose --env-file .env start postgres-replica1 postgres-replica2

# 6. Monitor full recovery
for i in {1..20}; do
  echo "Full recovery check $i/20..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
  sleep 15
done
```

### Complete Cluster Recovery

#### From Backup

```bash
# 1. Stop entire cluster
docker compose --env-file .env down

# 2. Remove all volumes
docker volume rm postgresql-ha-challenge_monitor_data
docker volume rm postgresql-ha-challenge_postgres-primary
docker volume rm postgresql-ha-challenge_postgres-replica1
docker volume rm postgresql-ha-challenge_postgres-replica2

# 3. Restore from backup (if available)
# ... backup restoration commands ...

# 4. Restart cluster
docker compose --env-file .env up -d --build

# 5. Monitor bootstrap process
for i in {1..10}; do
  echo "Bootstrap check $i/10..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq 2>/dev/null || echo "Monitor not ready"
  sleep 10
done
```

#### Fresh Cluster Setup

```bash
# 1. Complete cluster teardown
docker compose --env-file .env down -v

# 2. Clean up any remaining resources
docker system prune -f

# 3. Fresh start
docker compose --env-file .env up -d --build

# 4. Monitor initial bootstrap
for i in {1..15}; do
  echo "Initial bootstrap check $i/15..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq 2>/dev/null || echo "Still bootstrapping..."
  sleep 10
done

# 5. Verify cluster health
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

## Monitor Recovery Procedures

### Monitor Node Failure

#### Automatic Recovery

```bash
# 1. Check if monitor is down
docker compose --env-file .env ps | grep pgaf-monitor

# 2. Restart monitor
docker compose --env-file .env restart pgaf-monitor

# 3. Monitor recovery
sleep 30
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

#### Manual Monitor Recovery

```bash
# 1. Stop monitor
docker compose --env-file .env stop pgaf-monitor

# 2. Check monitor data integrity
docker volume ls | grep monitor_data

# 3. Restart monitor
docker compose --env-file .env start pgaf-monitor

# 4. Verify monitor functionality
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c "SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;"
```

### Monitor Data Recovery

#### From Backup

```bash
# 1. Stop monitor
docker compose --env-file .env stop pgaf-monitor

# 2. Backup current monitor data
docker run --rm -v postgresql-ha-challenge_monitor_data:/data -v $(pwd):/backup alpine cp -r /data /backup/monitor_backup

# 3. Restore monitor data
# ... restore from backup ...

# 4. Restart monitor
docker compose --env-file .env start pgaf-monitor
```

#### Fresh Monitor Setup

```bash
# 1. Stop all nodes
docker compose --env-file .env stop

# 2. Remove monitor volume
docker volume rm postgresql-ha-challenge_monitor_data

# 3. Restart monitor (will recreate database)
docker compose --env-file .env start pgaf-monitor

# 4. Wait for monitor to be ready
sleep 30

# 5. Restart PostgreSQL nodes
docker compose --env-file .env start postgres-primary postgres-replica1 postgres-replica2

# 6. Monitor cluster reformation
for i in {1..10}; do
  echo "Cluster reformation check $i/10..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq 2>/dev/null || echo "Reforming..."
  sleep 10
done
```

## Backup and Restore Procedures

### Database Backup

#### Automated Backups

```bash
# Create backup script
cat > backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups"

# Backup primary database
docker compose --env-file .env exec postgres-primary \
  pg_dump -U postgres -h localhost healthcare_db > $BACKUP_DIR/healthcare_$DATE.sql

# Compress backup
gzip $BACKUP_DIR/healthcare_$DATE.sql

# Cleanup old backups (keep 7 days)
find $BACKUP_DIR -name "healthcare_*.sql.gz" -mtime +7 -delete
EOF

chmod +x backup.sh
```

#### Manual Backup

```bash
# Backup from current primary
docker compose --env-file .env exec postgres-primary \
  pg_dump -U postgres -h localhost healthcare_db > healthcare_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore Procedures

#### Full Database Restore

```bash
# 1. Identify target node
TARGET_NODE="postgres-replica1"
BACKUP_FILE="healthcare_backup_20240115_100000.sql"

# 2. Stop target node
docker compose --env-file .env stop $TARGET_NODE

# 3. Remove existing volume
docker volume rm postgresql-ha-challenge_$TARGET_NODE

# 4. Start node (will reclone from primary)
docker compose --env-file .env start $TARGET_NODE

# 5. Wait for resync
sleep 60

# 6. Verify recovery
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
```

#### Selective Table Restore

```bash
# Restore specific table to primary
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db << EOF
-- Backup table first
CREATE TABLE patients_backup AS SELECT * FROM patients;

-- Restore from backup file
\i /path/to/backup/containing/patients/restore.sql

-- Verify restore
SELECT COUNT(*) FROM patients;
EOF
```

## Verification Procedures

### Post-Recovery Verification

```bash
# 1. Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Verify data consistency
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM patients;"

# 3. Check replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"

# 4. Verify monitoring
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9187/metrics | head -5
```

### Performance Verification

```bash
# Test read performance
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "EXPLAIN ANALYZE SELECT * FROM patients WHERE last_name LIKE 'S%';"

# Test write performance
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "EXPLAIN ANALYZE INSERT INTO audit_log (actor, action) VALUES ('test', 'recovery_test');"
```

## Emergency Procedures

### Critical System Failure

```bash
# 1. Assess situation
docker compose --env-file .env ps

# 2. Emergency stop
docker compose --env-file .env down

# 3. Check system resources
docker system df
docker stats --no-stream

# 4. Clean restart
docker compose --env-file .env up -d --build

# 5. Monitor recovery
for i in {1..10}; do
  echo "Emergency recovery check $i/10..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq 2>/dev/null || echo "Recovering..."
  sleep 15
done
```

### Data Corruption Recovery

```bash
# 1. Identify corruption
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_database WHERE datname = 'healthcare_db';"

# 2. Isolate corrupted node
docker compose --env-file .env stop postgres-primary

# 3. Promote healthy replica
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

# 4. Investigate corruption on old primary
docker compose --env-file .env exec postgres-primary \
  psql -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_database;"
```

## Documentation and Reporting

### Recovery Report Template

```bash
# Create recovery report
cat > recovery_report_$(date +%Y%m%d_%H%M%S).md << EOF
# Recovery Report - $(date)

## Incident Summary
- **Date/Time**: $(date)
- **Severity**: [Minor/Moderate/Major/Critical/Catastrophic]
- **Affected Components**: [List components]
- **Root Cause**: [Description]

## Recovery Actions Taken
1. [Action 1]
2. [Action 2]
3. [Action 3]

## Verification Results
- [ ] Cluster state verified
- [ ] Data consistency confirmed
- [ ] Performance validated
- [ ] Monitoring functional

## Lessons Learned
- [Lesson 1]
- [Lesson 2]

## Recommendations
- [Recommendation 1]
- [Recommendation 2]
EOF
```

## Support and Escalation

### When to Escalate

- **Data loss detected** - Escalate immediately
- **Recovery time exceeds 1 hour** - Escalate to senior DBA
- **Multiple nodes affected** - Escalate to infrastructure team
- **Application impact** - Escalate to application team

### Emergency Contacts

```bash
# Emergency notification script
cat > emergency_notify.sh << 'EOF'
#!/bin/bash
# Send emergency notifications
echo "EMERGENCY: PostgreSQL HA cluster recovery required" | mail -s "URGENT: Database Recovery" dba-team@company.com
echo "EMERGENCY: PostgreSQL HA cluster recovery required" | curl -X POST -H 'Content-type: application/json' --data '{"text":"EMERGENCY: PostgreSQL HA cluster recovery required"}' $SLACK_WEBHOOK
EOF
```

## Conclusion

Recovery procedures ensure the PostgreSQL HA cluster can be restored to operational status following various failure scenarios. Regular testing of these procedures is essential for maintaining system reliability and minimizing downtime.

Key principles:
- **Test regularly** - Practice recovery procedures monthly
- **Document thoroughly** - Maintain detailed recovery logs
- **Monitor continuously** - Use monitoring to detect issues early
- **Backup consistently** - Ensure reliable backup procedures
- **Train team** - Ensure all team members understand procedures

For failover procedures, see the [Automated Failover Documentation](02-automated-failover.md) and [Manual Failover Documentation](03-manual-failover.md).