#!/bin/bash
# Comprehensive PostgreSQL HA Failover Test Suite
# This script runs a complete set of failover tests

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV_FILE=".env"
LOG_FILE="test-results-$(date +%Y%m%d-%H%M%S).log"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO:${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

run_test() {
    local test_name="$1"
    local test_command="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    log "Running test: $test_name"

    if eval "$test_command"; then
        success "Test passed: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        error "Test failed: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running"
        return 1
    fi

    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "docker-compose is not available"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is not available"
        return 1
    fi

    # Check if bc is available
    if ! command -v bc >/dev/null 2>&1; then
        error "bc is not available"
        return 1
    fi

    success "All prerequisites met"
    return 0
}

setup_environment() {
    log "Setting up test environment..."

    # Copy test environment
    if [ ! -f "$ENV_FILE" ]; then
        cp .env.test "$ENV_FILE"
        success "Created .env file from .env.test"
    fi

    # Start the cluster
    log "Starting PostgreSQL HA cluster..."
    docker compose --env-file "$ENV_FILE" up -d --build

    # Wait for cluster to be ready
    log "Waiting for cluster to initialize..."
    sleep 60

    # Verify cluster health
    if ! docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh >/dev/null 2>&1; then
        error "Failed to initialize cluster"
        return 1
    fi

    success "Test environment ready"
    return 0
}

cleanup_environment() {
    log "Cleaning up test environment..."

    # Stop background processes if any
    pkill -f "load_test" || true

    # Stop the cluster
    docker compose --env-file "$ENV_FILE" down -v

    # Remove test data
    rm -f load_test.sql

    success "Cleanup completed"
}

test_cluster_health() {
    log "Testing cluster health..."

    # Check cluster state
    local state_output
    state_output=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh)

    # Verify we have exactly one primary
    local primary_count
    primary_count=$(echo "$state_output" | jq '.nodes[] | select(.reportedstate == "primary") | .nodename' | wc -l)

    if [ "$primary_count" -ne 1 ]; then
        error "Expected exactly 1 primary, found $primary_count"
        return 1
    fi

    # Verify all nodes are healthy
    local unhealthy_count
    unhealthy_count=$(echo "$state_output" | jq '.nodes[] | select(.health != 1) | .nodename' | wc -l)

    if [ "$unhealthy_count" -ne 0 ]; then
        error "Found $unhealthy_count unhealthy nodes"
        return 1
    fi

    success "Cluster health check passed"
    return 0
}

test_automated_failover() {
    log "Testing automated failover..."

    # Get current primary
    local current_primary
    current_primary=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')

    # Start timing
    local start_time
    start_time=$(date +%s.%3N)

    # Stop current primary
    docker compose --env-file "$ENV_FILE" stop "$current_primary"

    # Monitor failover
    local max_attempts=12
    local attempt=1
    local failover_success=false

    while [ $attempt -le $max_attempts ]; do
        log "Failover check $attempt/$max_attempts..."

        local new_primary
        new_primary=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')

        if [ "$new_primary" != "$current_primary" ] && [ "$new_primary" != "null" ]; then
            failover_success=true
            break
        fi

        sleep 5
        attempt=$((attempt + 1))
    done

    # Calculate failover time
    local end_time
    end_time=$(date +%s.%3N)
    local failover_time
    failover_time=$(echo "$end_time - $start_time" | bc)

    if [ "$failover_success" = false ]; then
        error "Automated failover failed - no new primary detected after $failover_time seconds"
        return 1
    fi

    # Verify failover time is within limits
    if (( $(echo "$failover_time > 60" | bc -l) )); then
        warning "Failover took $failover_time seconds (expected < 60s)"
    else
        success "Automated failover completed in $failover_time seconds"
    fi

    # Test data consistency
    local count1 count2
    count1=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM patients;" | tail -3 | head -1 | tr -d ' ')
    count2=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM patients;" | tail -3 | head -1 | tr -d ' ')

    if [ "$count1" != "$count2" ]; then
        error "Data inconsistency detected: primary=$count1, replica=$count2"
        return 1
    fi

    success "Data consistency verified"
    return 0
}

test_manual_failover() {
    log "Testing manual failover..."

    # Start timing
    local start_time
    start_time=$(date +%s.%3N)

    # Perform controlled failover
    docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/perform-failover.sh

    # Monitor transition
    local max_attempts=6
    local attempt=1
    local failover_success=false

    while [ $attempt -le $max_attempts ]; do
        log "Manual failover check $attempt/$max_attempts..."

        local state
        state=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq '.nodes[] | {name: .nodename, state: .reportedstate}')

        # Check if we have a new primary
        local primary_count
        primary_count=$(echo "$state" | jq 'map(select(.state == "primary")) | length')

        if [ "$primary_count" -eq 1 ]; then
            failover_success=true
            break
        fi

        sleep 5
        attempt=$((attempt + 1))
    done

    # Calculate failover time
    local end_time
    end_time=$(date +%s.%3N)
    local failover_time
    failover_time=$(echo "$end_time - $start_time" | bc)

    if [ "$failover_success" = false ]; then
        error "Manual failover failed after $failover_time seconds"
        return 1
    fi

    success "Manual failover completed in $failover_time seconds"

    # Test application connectivity
    if PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT 1;" >/dev/null 2>&1; then
        success "Application connectivity verified"
    else
        error "Application connectivity failed"
        return 1
    fi

    return 0
}

test_monitoring_stack() {
    log "Testing monitoring stack..."

    # Test Prometheus
    if curl -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
        success "Prometheus is healthy"
    else
        error "Prometheus is not responding"
        return 1
    fi

    # Test Grafana
    if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
        success "Grafana is healthy"
    else
        error "Grafana is not responding"
        return 1
    fi

    # Test postgres-exporter
    if curl -s http://localhost:9187/metrics | grep -q "pg_auto_failover" >/dev/null 2>&1; then
        success "postgres-exporter is collecting HA metrics"
    else
        error "postgres-exporter is not collecting HA metrics"
        return 1
    fi

    # Test metrics queries
    local metrics
    metrics=$(curl -s http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code)

    if echo "$metrics" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        success "Prometheus metrics are available"
    else
        error "Prometheus metrics are not available"
        return 1
    fi

    return 0
}

test_load_during_failover() {
    log "Testing failover under load..."

    # Create load test data
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
LIMIT 50;
EOF

    # Start background load
    log "Starting background load..."
    while true; do
        PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -f load_test.sql >/dev/null 2>&1 || true
        sleep 2
    done &
    local load_pid=$!

    # Wait for load to stabilize
    sleep 10

    # Trigger failover during load
    log "Triggering failover under load..."
    local start_time
    start_time=$(date +%s.%3N)

    # Get current primary and stop it
    local current_primary
    current_primary=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')
    docker compose --env-file "$ENV_FILE" stop "$current_primary"

    # Monitor failover
    local max_attempts=12
    local attempt=1
    local failover_success=false

    while [ $attempt -le $max_attempts ]; do
        log "Load failover check $attempt/$max_attempts..."

        local new_primary
        new_primary=$(docker compose --env-file "$ENV_FILE" exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq -r '.nodes[] | select(.reportedstate == "primary") | .nodename')

        if [ "$new_primary" != "$current_primary" ] && [ "$new_primary" != "null" ]; then
            failover_success=true
            break
        fi

        sleep 5
        attempt=$((attempt + 1))
    done

    # Stop load
    kill "$load_pid" 2>/dev/null || true

    # Calculate failover time
    local end_time
    end_time=$(date +%s.%3N)
    local failover_time
    failover_time=$(echo "$end_time - $start_time" | bc)

    if [ "$failover_success" = false ]; then
        error "Failover under load failed after $failover_time seconds"
        return 1
    fi

    success "Failover under load completed in $failover_time seconds"

    # Verify data integrity
    local count
    count=$(PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "SELECT COUNT(*) FROM appointments WHERE chief_complaint = 'Load test appointment';" | tail -3 | head -1 | tr -d ' ')

    if [ "$count" -gt 0 ]; then
        success "Data integrity verified under load ($count records)"
    else
        error "No test data found - possible data loss"
        return 1
    fi

    # Cleanup test data
    PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db -c "DELETE FROM appointments WHERE chief_complaint = 'Load test appointment';" >/dev/null 2>&1

    return 0
}

print_summary() {
    log ""
    log "=== TEST SUMMARY ==="
    log "Tests Run: $TESTS_RUN"
    log "Tests Passed: $TESTS_PASSED"
    log "Tests Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        success "All tests passed! ✓"
        return 0
    else
        error "Some tests failed! ✗"
        return 1
    fi
}

main() {
    log "Starting comprehensive PostgreSQL HA failover test suite..."
    log "Log file: $LOG_FILE"

    # Check prerequisites
    if ! check_prerequisites; then
        error "Prerequisites check failed"
        exit 1
    fi

    # Setup environment
    if ! setup_environment; then
        error "Environment setup failed"
        exit 1
    fi

    # Run tests
    run_test "Cluster Health Check" test_cluster_health
    run_test "Automated Failover" test_automated_failover
    run_test "Manual Failover" test_manual_failover
    run_test "Monitoring Stack" test_monitoring_stack
    run_test "Load During Failover" test_load_during_failover

    # Cleanup
    cleanup_environment

    # Print summary
    if print_summary; then
        log "Test suite completed successfully!"
        exit 0
    else
        log "Test suite completed with failures!"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_environment EXIT

# Run main function
main "$@"