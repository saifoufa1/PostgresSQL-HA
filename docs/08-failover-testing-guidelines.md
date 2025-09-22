# PostgreSQL High Availability Failover Testing Guidelines

## Overview

This document provides comprehensive guidelines for testing the PostgreSQL High Availability (HA) failover system. These guidelines ensure that the HA system performs correctly under various failure scenarios and provides the expected recovery time objectives (RTO) and recovery point objectives (RPO).

## Document Information

- **Version**: 1.0
- **Last Updated**: 2025-01-22
- **Target Audience**: Developers, QA Engineers, DevOps Engineers
- **Testing Environment**: Docker-based PostgreSQL HA cluster with pg_auto_failover
- **Expected RTO**: 20-30 seconds for automated failover
- **Expected RPO**: Zero data loss (synchronous replication)

---

## 1. Testing Objectives

### 1.1 Primary Objectives

- **Verify Automated Failover**: Ensure automatic failover occurs within specified RTO
- **Validate Data Consistency**: Confirm no data loss during failover events
- **Test Application Recovery**: Verify applications handle failovers gracefully
- **Monitor System Performance**: Ensure failover doesn't impact system performance
- **Validate Monitoring**: Confirm monitoring systems detect and report failover events

### 1.2 Secondary Objectives

- **Test Manual Failover**: Verify controlled failover procedures work correctly
- **Performance Benchmarking**: Measure failover times under various conditions
- **Load Testing**: Ensure system handles failovers under production-like loads
- **Network Resilience**: Test behavior during network partitions and failures
- **Resource Management**: Verify proper resource cleanup and allocation

### 1.3 Success Criteria

- **RTO Compliance**: Failover completes within 30 seconds
- **Zero Data Loss**: All committed transactions preserved
- **Application Continuity**: No application errors during failover
- **Monitoring Accuracy**: All events properly logged and alerted
- **System Stability**: No resource leaks or performance degradation

---

## 2. Test Environment Setup

### 2.1 Prerequisites

#### System Requirements
- **Docker Engine**: 20.10 or higher
- **Docker Compose**: Plugin 2.0 or higher
- **Memory**: 8GB RAM minimum (12GB recommended)
- **Storage**: 60GB free disk space
- **Network**: Open ports 5431-5434, 6010-6012, 9090, 9187, 3000

#### Required Tools
- **jq**: For JSON parsing and formatting
- **curl**: For API testing and metrics verification
- **psql**: PostgreSQL client for database operations
- **bc**: For floating-point calculations

### 2.2 Environment Preparation

#### Step 1: Environment Setup
```bash
# Navigate to project directory
cd postgresql-ha-challenge

# Copy test environment configuration
cp .env.test .env

# Start the complete HA stack
docker compose --env-file .env up -d --build

# Verify all services are running
docker compose --env-file .env ps
```

#### Step 2: Health Verification
```bash
# Check cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Verify monitoring stack
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3000/api/health

# Test database connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT version(), pg_is_in_recovery();"
```

#### Expected Initial State
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

---

## 3. Test Scenarios

### 3.1 Scenario 1: Automated Failover Testing

#### Test Case: Primary Node Failure
**Objective**: Verify automatic failover when primary node fails

**Preconditions**:
- Cluster in healthy state (1 primary, 2 replicas)
- All nodes responding to health checks
- Replication lag < 1 second

**Test Steps**:

1. **Identify Current Primary**
   ```bash
   CURRENT_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
   echo "Current primary: $CURRENT_PRIMARY"
   ```

2. **Start Background Load** (Optional)
   ```bash
   # Generate continuous load
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "INSERT INTO audit_log (actor, action) SELECT 'test_user', 'load_test_' || generate_series(1,1000);" &
   LOAD_PID=$!
   ```

3. **Trigger Primary Failure**
   ```bash
   # Stop current primary node
   docker compose --env-file .env stop $CURRENT_PRIMARY
   ```

4. **Monitor Failover Process**
   ```bash
   echo "Monitoring failover process..."
   START=$(date +%s.%3N)

   for i in {1..12}; do
     echo "Attempt $i/12..."
     docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
     sleep 5
   done

   END=$(date +%s.%3N)
   DURATION=$(echo "$END - $START" | bc)
   echo "Total failover time: $DURATION seconds"
   ```

5. **Verify New Primary**
   ```bash
   NEW_PRIMARY=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
   echo "New primary: $NEW_PRIMARY"

   # Test new primary functionality
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT pg_is_in_recovery(), now();"
   ```

6. **Verify Data Consistency**
   ```bash
   # Check data preservation
   COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT COUNT(*) FROM audit_log WHERE actor = 'test_user';" | tail -3 | head -1 | tr -d ' ')
   echo "Records preserved: $COUNT"
   ```

7. **Restore Failed Node**
   ```bash
   # Restart old primary (should rejoin as replica)
   docker compose --env-file .env start $CURRENT_PRIMARY

   # Verify it rejoins cluster
   sleep 30
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
   ```

8. **Cleanup**
   ```bash
   # Stop background load if running
   if [ ! -z "$LOAD_PID" ]; then
     kill $LOAD_PID 2>/dev/null || true
   fi
   ```

**Expected Results**:
- Failover completes within 30 seconds
- New primary is promoted automatically
- Data remains consistent across nodes
- Failed node rejoins as replica
- No data loss during transition

### 3.2 Scenario 2: Manual Failover Testing

#### Test Case: Controlled Failover
**Objective**: Test manual failover for planned maintenance

**Test Steps**:

1. **Pre-Failover Health Check**
   ```bash
   # Verify cluster state
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

   # Check replication status
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
   ```

2. **Perform Controlled Failover**
   ```bash
   # Execute controlled failover
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

   # Monitor transition
   echo "Monitoring controlled failover..."
   START=$(date +%s.%3N)

   for i in {1..6}; do
     echo "Attempt $i/6..."
     docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
     sleep 5
   done

   END=$(date +%s.%3N)
   DURATION=$(echo "$END - $START" | bc)
   echo "Controlled failover completed in $DURATION seconds"
   ```

3. **Verify Application Connectivity**
   ```bash
   # Test new primary
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "INSERT INTO audit_log (actor, action, context) VALUES ('test_user', 'controlled_failover_test', '{\"test\": true}');"

   # Verify data persistence
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT * FROM audit_log WHERE actor = 'test_user' ORDER BY created_at DESC LIMIT 1;"
   ```

**Expected Results**:
- Controlled failover completes smoothly
- No data loss during transition
- Application connections recover automatically
- Audit log entry persists after failover

### 3.3 Scenario 3: Network Partition Testing

#### Test Case: Network Isolation
**Objective**: Test behavior during network failures

**Test Steps**:

1. **Baseline Health Check**
   ```bash
   # Verify initial cluster state
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
   ```

2. **Simulate Network Partition**
   ```bash
   # Stop primary node (simulates network isolation)
   docker compose --env-file .env stop postgres-primary

   # Monitor automatic failover
   echo "Monitoring failover during network partition..."
   for i in {1..6}; do
     echo "Check $i/6..."
     docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
     sleep 5
   done
   ```

3. **Verify Split-Brain Prevention**
   ```bash
   # Check that only one primary exists
   PRIMARIES=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | select(.reportedstate == "primary") | .nodename' | wc -l)
   echo "Number of primaries: $PRIMARIES"

   if [ "$PRIMARIES" -eq 1 ]; then
     echo "✓ Split-brain prevention working correctly"
   else
     echo "✗ Multiple primaries detected - split-brain scenario!"
   fi
   ```

4. **Restore Connectivity**
   ```bash
   # Restart isolated node
   docker compose --env-file .env start postgres-primary

   # Verify recovery
   sleep 30
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq
   ```

**Expected Results**:
- Monitor detects failure within 15 seconds
- Only one primary exists (no split-brain)
- Automatic failover occurs normally
- Isolated node rejoins as replica when restored

### 3.4 Scenario 4: Load Testing During Failover

#### Test Case: High Load Failover
**Objective**: Test failover under production-like load

**Test Steps**:

1. **Setup Load Generation**
   ```bash
   # Create load test script
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
   ```

2. **Start Continuous Load**
   ```bash
   # Start background load generation
   echo "Starting continuous load test..."
   while true; do
     PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -f load_test.sql
     sleep 1
   done &
   LOAD_PID=$!
   ```

3. **Trigger Failover During Load**
   ```bash
   # Wait for load to stabilize
   sleep 10

   # Trigger failover
   echo "Triggering failover under load..."
   START=$(date +%s.%3N)
   docker compose --env-file .env stop postgres-primary
   ```

4. **Monitor Performance During Failover**
   ```bash
   # Monitor cluster state during failover
   for i in {1..12}; do
     echo "Check $i/12 - $(date)"
     docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | {name: .nodename, state: .reportedstate, health: .health}'
     sleep 5
   done

   END=$(date +%s.%3N)
   DURATION=$(echo "$END - $START" | bc)
   echo "Failover under load completed in $DURATION seconds"
   ```

5. **Verify Data Integrity**
   ```bash
   # Check data consistency
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT COUNT(*) FROM appointments WHERE chief_complaint = 'Load test appointment';" | tail -3 | head -1 | tr -d ' '

   # Stop load generation
   kill $LOAD_PID 2>/dev/null || true
   ```

6. **Cleanup Test Data**
   ```bash
   # Clean up test appointments
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "DELETE FROM appointments WHERE chief_complaint = 'Load test appointment';"
   ```

**Expected Results**:
- Failover completes successfully under load
- No transaction loss during high-load failover
- System maintains performance during transition
- Data consistency preserved throughout test

### 3.5 Scenario 5: Monitoring and Observability Testing

#### Test Case: Monitoring Stack Verification
**Objective**: Verify monitoring systems work during failover

**Test Steps**:

1. **Baseline Monitoring Check**
   ```bash
   # Check Prometheus metrics
   curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code | jq

   # Verify Grafana dashboards
   curl -s http://localhost:3000/api/health

   # Check postgres-exporter
   curl -s http://localhost:9187/metrics | grep -E "(pg_auto_failover|pg_stat_replication)" | head -10
   ```

2. **Trigger Failover Event**
   ```bash
   # Start monitoring
   echo "Starting failover monitoring test..."

   # Trigger failover
   docker compose --env-file .env stop postgres-primary
   ```

3. **Monitor Metrics During Failover**
   ```bash
   # Monitor metrics throughout failover
   for i in {1..8}; do
     echo "Metrics check $i/8 - $(date)"
     curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code | jq '.data.result[] | {node: .metric.nodename, health: .value[1]}'
     sleep 5
   done
   ```

4. **Verify Alert Generation**
   ```bash
   # Check if alerts would be triggered (if configured)
   curl -s http://localhost:9090/api/v1/query?query=ALERTS | jq

   # Verify replication lag metrics
   curl -s http://localhost:9090/api/v1/query?query=pg_stat_replication_replay_lag_bytes | jq
   ```

5. **Post-Failover Monitoring**
   ```bash
   # Verify final state in monitoring
   curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_reported_state_code | jq

   # Check monitor database directly
   docker compose --env-file .env exec pgaf-monitor \
     psql -U postgres -d pg_auto_failover \
     -c 'SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;'
   ```

**Expected Results**:
- Prometheus shows cluster metrics throughout failover
- Grafana dashboards remain accessible
- postgres-exporter collects HA metrics correctly
- Monitor database tracks all state changes
- No monitoring gaps during transition

---

## 4. Validation Criteria

### 4.1 Functional Validation

#### Cluster State Validation
- [ ] Exactly one primary node exists
- [ ] All nodes report healthy status (health = 1)
- [ ] Failed nodes rejoin as replicas
- [ ] No split-brain scenarios occur

#### Data Consistency Validation
- [ ] All committed transactions preserved
- [ ] No data loss during failover
- [ ] Replication lag < 1 second after recovery
- [ ] Data identical across all nodes

#### Application Connectivity Validation
- [ ] Database connections recover automatically
- [ ] No application errors during failover
- [ ] Connection pooling handles failover gracefully
- [ ] Read/write operations continue normally

### 4.2 Performance Validation

#### Recovery Time Validation
- [ ] Automated failover completes within 30 seconds
- [ ] Manual failover completes within 15 seconds
- [ ] Node rejoin completes within 60 seconds
- [ ] No performance degradation post-failover

#### Resource Usage Validation
- [ ] CPU usage remains within normal bounds
- [ ] Memory usage doesn't leak during failover
- [ ] Disk I/O normalizes after recovery
- [ ] Network traffic returns to baseline

### 4.3 Monitoring Validation

#### Metrics Collection Validation
- [ ] All pg_auto_failover metrics collected
- [ ] Replication lag metrics accurate
- [ ] Node health status correctly reported
- [ ] No monitoring gaps during failover

#### Alert Generation Validation
- [ ] Failover events trigger appropriate alerts
- [ ] Recovery events properly logged
- [ ] No false positive alerts generated
- [ ] Alert timing matches actual events

---

## 5. Troubleshooting Guide

### 5.1 Common Issues and Solutions

#### Issue 1: Failover Not Triggering
**Symptoms**: Primary failure doesn't trigger automatic failover

**Diagnosis**:
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

**Solution**:
- Verify monitor connectivity from all nodes
- Check network connectivity between nodes
- Ensure adequate system resources
- Review pg_auto_failover configuration

#### Issue 2: Slow Failover Performance
**Symptoms**: Failover takes longer than expected RTO

**Diagnosis**:
```bash
# Check system resources
docker stats

# Monitor promotion process
docker compose --env-file .env logs -f pgaf-monitor

# Check replication lag
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_replication;"
```

**Solution**:
- Increase system resources (CPU/memory)
- Tune pg_auto_failover heartbeat settings
- Optimize PostgreSQL configuration
- Check for resource contention

#### Issue 3: Data Inconsistency After Failover
**Symptoms**: Data differs between nodes after failover

**Diagnosis**:
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

**Solution**:
- Verify replication slots are active
- Check for network connectivity issues
- Resynchronize replica if necessary
- Review PostgreSQL logs for errors

#### Issue 4: Monitoring Dashboard Not Loading
**Symptoms**: Grafana shows no data or fails to load

**Diagnosis**:
```bash
# Check Prometheus connectivity
curl -s http://localhost:9090/-/healthy

# Verify postgres-exporter
curl -s http://localhost:9187/metrics | head -5

# Check Grafana logs
docker compose --env-file .env logs grafana
```

**Solution**:
- Restart monitoring stack components
- Verify postgres-exporter configuration
- Check network connectivity to exporters
- Review Prometheus scrape configuration

### 5.2 Debug Commands

#### Complete Cluster Status
```bash
# Get comprehensive cluster state
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

#### Performance Monitoring
```bash
# System resource usage
docker stats

# PostgreSQL performance metrics
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_bgwriter;"

# Replication performance
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT * FROM pg_stat_replication;"
```

### 5.3 Recovery Procedures

#### Emergency Recovery Steps

1. **Assess Current State**
   ```bash
   # Check all nodes
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

   # Check individual node status
   docker compose --env-file .env ps
   ```

2. **Identify Issues**
   ```bash
   # Check logs for errors
   docker compose --env-file .env logs pgaf-monitor
   docker compose --env-file .env logs postgres-primary

   # Test connectivity
   docker compose --env-file .env exec postgres-primary \
     pg_isready -h pgaf-monitor -p 5431 -U autoctl_node
   ```

3. **Apply Fixes**
   ```bash
   # Restart failed components
   docker compose --env-file .env restart pgaf-monitor

   # Resync failed nodes
   docker compose --env-file .env stop postgres-primary
   docker volume rm postgresql-ha-challenge_postgres-primary
   docker compose --env-file .env start postgres-primary
   ```

4. **Verify Recovery**
   ```bash
   # Confirm cluster health
   docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

   # Test functionality
   PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
     -c "SELECT COUNT(*) FROM patients;"
   ```

---

## 6. Best Practices

### 6.1 Testing Best Practices

#### Test Environment Management
- **Use dedicated test environment** for all failover testing
- **Reset environment** between test scenarios
- **Document test results** for future reference
- **Version control** test scripts and configurations

#### Test Execution Guidelines
- **Test during low-traffic periods** when possible
- **Notify stakeholders** before running destructive tests
- **Have rollback plan** ready for each test scenario
- **Monitor system resources** throughout testing

#### Documentation Standards
- **Record test parameters** and environment conditions
- **Capture timing measurements** for performance analysis
- **Document any issues** encountered during testing
- **Update procedures** based on test findings

### 6.2 Operational Best Practices

#### Regular Testing Schedule
- **Automated failover testing**: Monthly
- **Manual failover testing**: Quarterly
- **Load testing during failover**: Bi-annually
- **Network partition testing**: Quarterly

#### Monitoring and Alerting
- **Configure alerts** for failover events
- **Monitor replication lag** continuously
- **Track system performance** during failovers
- **Review logs** after each failover event

#### Performance Optimization
- **Regular performance benchmarking** of failover times
- **Resource monitoring** during peak loads
- **Configuration tuning** based on test results
- **Capacity planning** for growth scenarios

### 6.3 Emergency Procedures

#### When Automated Failover Fails
1. **Assess the situation** - Check cluster state and logs
2. **Manual intervention** - Use controlled failover if appropriate
3. **Emergency promotion** - Promote replica manually if needed
4. **Notify stakeholders** - Communicate status and ETA
5. **Document incident** - Record all actions taken

#### Communication Protocol
- **Define escalation paths** for different failure types
- **Establish communication channels** for incident response
- **Create status page** for system availability
- **Document post-incident procedures**

---

## 7. Test Automation

### 7.1 Automated Test Scripts

#### Basic Failover Test Script
```bash
#!/bin/bash
# scripts/test-automated-failover.sh
set -euo pipefail

echo "Starting automated failover test..."

# 1. Pre-test health check
echo "✓ Pre-test health check"
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# 2. Trigger failover
echo "✓ Triggering failover"
START=$(date +%s.%3N)
docker compose --env-file .env stop postgres-primary

# 3. Monitor recovery
echo "✓ Monitoring recovery..."
for i in {1..12}; do
  echo "Check $i/12..."
  STATE=$(docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.nodename == "node2") | .reportedstate')
  if [ "$STATE" = "primary" ]; then
    END=$(date +%s.%3N)
    DURATION=$(echo "$END - $START" | bc)
    echo "✓ Failover completed in $DURATION seconds"
    break
  fi
  sleep 5
done

# 4. Verify data integrity
echo "✓ Verifying data integrity"
COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM audit_log;" | tail -3 | head -1 | tr -d ' ')
echo "✓ Records preserved: $COUNT"

# 5. Restore environment
echo "✓ Restoring environment"
docker compose --env-file .env start postgres-primary
sleep 30

echo "✓ Automated failover test completed successfully!"
```

#### Load Test During Failover Script
```bash
#!/bin/bash
# scripts/test-load-failover.sh
set -euo pipefail

echo "Starting load test during failover..."

# 1. Start background load
echo "✓ Starting background load"
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "INSERT INTO audit_log (actor, action) SELECT 'test_user', 'load_test_' || generate_series(1,1000);" &
LOAD_PID=$!

# 2. Trigger failover
echo "✓ Triggering failover under load"
START=$(date +%s.%3N)
docker compose --env-file .env stop postgres-primary

# 3. Monitor recovery
echo "✓ Monitoring recovery under load..."
for i in {1..12}; do
  echo "Check $i/12..."
  docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | {name: .nodename, state: .reportedstate}'
  sleep 5
done

END=$(date +%s.%3N)
DURATION=$(echo "$END - $START" | bc)
echo "✓ Failover under load completed in $DURATION seconds"

# 4. Verify data integrity
echo "✓ Verifying data integrity"
COUNT=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT COUNT(*) FROM audit_log WHERE actor = 'test_user';" | tail -3 | head -1 | tr -d ' ')
echo "✓ Records preserved: $COUNT"

# 5. Cleanup
echo "✓ Cleaning up"
kill $LOAD_PID 2>/dev/null || true

echo "✓ Load test during failover completed successfully!"
```

### 7.2 CI/CD Integration

#### GitHub Actions Example
```yaml
name: PostgreSQL HA Failover Tests
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Set up Docker
      uses: docker/setup-build-action@v2

    - name: Run failover tests
      run: |
        cp .env.test .env
        docker compose --env-file .env up -d --build
        sleep 60
        chmod +x scripts/test-automated-failover.sh
        ./scripts/test-automated-failover.sh
        chmod +x scripts/test-load-failover.sh
        ./scripts/test-load-failover.sh

    - name: Cleanup
      if: always()
      run: |
        docker compose --env-file .env down -v
```

---

## 8. Conclusion

This comprehensive failover testing guidelines document provides developers and QA engineers with the tools and procedures needed to thoroughly test the PostgreSQL HA system. By following these guidelines, teams can ensure:

- **Reliable failover** within specified RTO/RPO targets
- **Data consistency** during all failure scenarios
- **Application compatibility** with HA operations
- **Proper monitoring** and alerting during failovers
- **System stability** under various load conditions

Regular testing using these procedures will help identify issues early, validate system improvements, and ensure the HA system meets production requirements.

---

## 9. Appendices

### 9.1 Reference Commands

#### Health Check Commands
```bash
# Cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Database connectivity
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT 1;"

# Monitoring health
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3000/api/health
```

#### Performance Monitoring
```bash
# System resources
docker stats

# PostgreSQL metrics
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_bgwriter;"

# Replication status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT * FROM pg_stat_replication;"
```

### 9.2 Configuration Files

#### Environment Variables
```bash
# .env.test
LOAD_SCHEMA=true
LOAD_TEST_DATA=true
APP_USER=admin
APP_PASSWORD=admin
POSTGRES_PASSWORD=postgres_password
PG_HBA_CIDR=0.0.0.0/0
```

#### PostgreSQL Configuration
- **Primary**: `config/primary/postgresql.conf`
- **Replica**: `config/replica/postgresql.conf`
- **HBA**: `config/primary/pg_hba.conf`, `config/replica/pg_hba.conf`

### 9.3 Test Data Schema

The test environment includes realistic healthcare data:
- **Patients**: Medical patient records
- **Providers**: Healthcare provider information
- **Facilities**: Medical facility details
- **Appointments**: Patient appointment scheduling
- **Audit Log**: System activity tracking

This schema provides realistic testing scenarios for healthcare applications.

---

**Document Version**: 1.0
**Last Updated**: 2025-01-22
**Contact**: Development Team