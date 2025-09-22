# Monitoring Dashboard Guide

This comprehensive guide explains the monitoring and observability features of the PostgreSQL High Availability solution, including Prometheus metrics collection and Grafana dashboard visualization.

## Overview

The monitoring stack provides:
- **Real-time metrics** collection from all PostgreSQL nodes
- **Health monitoring** of the pg_auto_failover cluster
- **Performance tracking** of database operations
- **Alerting capabilities** for proactive issue detection
- **Historical data** for trend analysis and capacity planning

## Architecture

### Monitoring Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ PostgreSQL Nodes│────│ postgres-exporter│────│   Prometheus    │
│                 │    │ (9187/metrics)   │    │ (9090/api)      │
│ - Primary       │    │                  │    │                 │
│ - Replicas      │    │ - Metrics        │    │ - Time Series   │
│ - pg_auto_failover│  │ - Health Status  │    │ - Storage       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Grafana       │    │ pg-ha-monitor    │    │   Alerting      │
│ (3000/dashboards)│  │ (Enhanced)       │    │                 │
│                 │    │                  │    │ - Email         │
│ - Visualizations│    │ - Health Checks  │    │ - Webhooks      │
│ - Dashboards    │    │ - Custom Metrics │    │ - Slack         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Data Flow

1. **Metrics Collection**: postgres-exporter scrapes PostgreSQL nodes every 15 seconds
2. **Data Storage**: Prometheus stores time-series data with configurable retention
3. **Visualization**: Grafana queries Prometheus and displays real-time dashboards
4. **Alerting**: Both systems can trigger alerts based on configurable thresholds

## Quick Start

### Access Points

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Grafana** | http://localhost:3000 | admin/admin | Dashboard visualization |
| **Prometheus** | http://localhost:9090 | N/A | Metrics exploration |
| **postgres-exporter** | http://localhost:9187/metrics | N/A | Raw metrics |

### Initial Setup

```bash
# Verify monitoring stack is running
docker compose --env-file .env ps | grep -E "(prometheus|grafana|postgres-exporter)"

# Check Prometheus health
curl -s http://localhost:9090/-/healthy

# Check metrics collection
curl -s http://localhost:9187/metrics | head -10
```

## Grafana Dashboard

### Pre-configured Dashboard

The system includes a comprehensive pg_auto_failover dashboard with the following sections:

#### 1. Cluster Overview
- **Node Status**: Health status of all cluster nodes
- **Role Distribution**: Primary vs replica node visualization
- **Failover Events**: Historical failover tracking
- **Uptime Statistics**: Node availability metrics

#### 2. pg_auto_failover Metrics
- **Node Health Codes**: Real-time health status (1=healthy, 0=unhealthy)
- **State Transitions**: Node state changes over time
- **Replication Lag**: Lag between primary and replicas
- **Connection Status**: Monitor and node connectivity

#### 3. PostgreSQL Performance
- **Query Performance**: Slow query tracking
- **Connection Pool**: Active vs idle connections
- **WAL Activity**: Write-ahead log generation
- **Lock Statistics**: Database lock monitoring

#### 4. System Resources
- **CPU Usage**: Per-node CPU utilization
- **Memory Consumption**: RAM usage across nodes
- **Disk I/O**: Read/write operations
- **Network Traffic**: Inter-node communication

### Dashboard Navigation

1. **Access Grafana**: Navigate to http://localhost:3000
2. **Login**: Use admin/admin credentials
3. **Select Dashboard**: Choose "PostgreSQL HA Cluster" from the dashboard list
4. **Time Range**: Adjust time range for historical data (default: last 15 minutes)
5. **Auto-refresh**: Enable auto-refresh for real-time monitoring

### Key Metrics Explained

#### Health Metrics

```sql
-- Node health status
pg_auto_failover_node_state_health_code

-- Node state (primary/secondary)
pg_auto_failover_node_state_reported_state_code

-- Replication lag in bytes
pg_stat_replication_replay_lag_bytes
```

#### Performance Metrics

```sql
-- Active connections
pg_stat_activity_count{state="active"}

-- Database size
pg_database_size_bytes{datname="healthcare_db"}

-- WAL generation rate
pg_stat_wal_wal_bytes_total
```

## Prometheus Metrics

### Query Interface

Access Prometheus at http://localhost:9090 to explore metrics:

#### Basic Queries

```promql
# Node health status
pg_auto_failover_node_state_health_code

# Replication lag
pg_stat_replication_replay_lag_bytes

# Connection count
pg_stat_activity_count{state="active"}
```

#### Advanced Queries

```promql
# Average replication lag across all replicas
avg(pg_stat_replication_replay_lag_bytes) by (client_addr)

# Health status summary
count(pg_auto_failover_node_state_health_code == 1) by (state)

# Query performance (95th percentile)
histogram_quantile(0.95, rate(pg_stat_statements_total_time_sum[5m]))
```

### Alert Rules

#### Pre-configured Alerts

1. **Node Down Alert**
   ```yaml
   alert: PostgreSQLNodeDown
   expr: pg_auto_failover_node_state_health_code == 0
   for: 30s
   labels:
     severity: critical
   ```

2. **High Replication Lag**
   ```yaml
   alert: HighReplicationLag
   expr: pg_stat_replication_replay_lag_bytes > 100000000
   for: 1m
   labels:
     severity: warning
   ```

3. **Primary Node Failure**
   ```yaml
   alert: PrimaryNodeFailure
   expr: pg_auto_failover_node_state_reported_state_code{state="primary"} == 0
   for: 10s
   labels:
     severity: critical
   ```

### Custom Alert Configuration

Add custom alerts to `monitoring/prometheus.rules.yml`:

```yaml
groups:
  - name: postgresql_ha_alerts
    rules:
      - alert: CustomHighLoad
        expr: pg_stat_activity_count{state="active"} > 50
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High active connection count detected"
          description: "More than 50 active connections for 5 minutes"
```

## Enhanced Monitoring with pg-ha-monitor

### Integration Features

The pg-ha-monitor provides additional monitoring capabilities:

#### Health Checks
- **Node connectivity** verification
- **PostgreSQL process** health monitoring
- **Role validation** (primary/replica consistency)
- **Replication status** tracking

#### Custom Metrics
- **Failover readiness** assessment
- **Priority validation** for nodes
- **Network connectivity** testing
- **Performance benchmarking**

### Configuration

#### Basic Setup

```yaml
# monitoring/config.yaml
database:
  monitor_host: "pgaf-monitor"
  monitor_port: 5431
  postgres_password: "postgres_password"

nodes:
  primary:
    host: "postgres-primary"
    port: 5432
  replica1:
    host: "postgres-replica1"
    port: 5432
  replica2:
    host: "postgres-replica2"
    port: 5432
```

#### Alert Configuration

```yaml
alerting:
  email:
    enabled: true
    smtp_server: "smtp.company.com"
    from_email: "monitor@company.com"
    to_emails:
      - "dba@company.com"
      - "admin@company.com"

  webhooks:
    enabled: true
    urls:
      - "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

### Usage Examples

#### Health Check

```bash
# Run health check
python pg_ha_monitor.py health

# Output:
# PostgreSQL HA Cluster Health Report
# ==================================
# Generated: 2024-01-15 10:30:00
#
# Cluster Overview:
# - Primary nodes: 1
# - Replica nodes: 2
# - Unhealthy nodes: 0
# - Failover ready: true
#
# Node Details:
# ✅ postgres-primary (172.28.0.10:5432) - primary
# ✅ postgres-replica1 (172.28.0.11:5432) - secondary, Lag: 0.12MB
# ✅ postgres-replica2 (172.28.0.12:5432) - secondary, Lag: 0.08MB
```

#### Continuous Monitoring

```bash
# Start continuous monitoring
python pg_ha_monitor.py monitor

# Get cluster state (JSON)
python pg_ha_monitor.py cluster-state | jq
```

## Troubleshooting Monitoring

### Common Issues

#### 1. Grafana Dashboard Not Loading

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

#### 2. Missing Metrics

```bash
# Check if postgres-exporter is running
docker compose --env-file .env ps postgres-exporter

# Verify metrics endpoint
curl -s http://localhost:9187/metrics | grep pg_auto_failover

# Check exporter logs
docker compose --env-file .env logs postgres-exporter
```

#### 3. Prometheus Not Scraping

```bash
# Check Prometheus configuration
docker compose --env-file .env exec prometheus \
  cat /etc/prometheus/prometheus.yml

# Test scrape target
curl -s http://localhost:9090/api/v1/targets | jq

# Check Prometheus logs
docker compose --env-file .env logs prometheus
```

### Debug Commands

#### Metrics Verification

```bash
# Check all available metrics
curl -s http://localhost:9187/metrics | grep -E "(pg_auto_failover|pg_stat_replication)" | head -10

# Verify specific metric
curl -s "http://localhost:9090/api/v1/query?query=pg_auto_failover_node_state_health_code" | jq

# Check target status
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.scrapeUrl | contains("9187"))'
```

#### Cluster State Verification

```bash
# Direct monitor database query
docker compose --env-file .env exec pgaf-monitor \
  psql -U postgres -d pg_auto_failover \
  -c 'SELECT nodeid, nodename, reportedstate, health FROM pgautofailover.node;'

# pg_autoctl state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Node-specific checks
docker compose --env-file .env exec postgres-primary \
  psql -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery(), pg_last_wal_receive_time();"
```

## Performance Impact

### Resource Usage

| Component | CPU | Memory | Network | Storage |
|-----------|-----|--------|---------|---------|
| **postgres-exporter** | <1% | ~50MB | Low | Minimal |
| **Prometheus** | 2-5% | ~200MB | Moderate | 1GB/day |
| **Grafana** | 1-2% | ~100MB | Low | Minimal |
| **pg-ha-monitor** | <1% | ~50MB | Low | 100MB logs |

### Optimization Tips

1. **Retention Policy**: Configure appropriate data retention in Prometheus
2. **Scrape Intervals**: Adjust scrape frequency based on needs
3. **Metric Filtering**: Use metric relabeling to reduce cardinality
4. **Storage Optimization**: Use compressed storage backends

## Security Considerations

### Access Control

```bash
# Configure Grafana authentication
# Edit grafana.ini or use environment variables
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=secure_password
GF_USERS_ALLOW_SIGN_UP=false
```

### Network Security

```bash
# Restrict access to monitoring endpoints
# Use firewall rules or reverse proxy
iptables -A INPUT -p tcp --dport 9090 -s 192.168.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -s 192.168.0.0/16 -j ACCEPT
```

### TLS Configuration

```yaml
# Enable HTTPS for Grafana
GF_SERVER_PROTOCOL=https
GF_SERVER_CERT_FILE=/path/to/cert.pem
GF_SERVER_CERT_KEY=/path/to/key.pem
```

## Maintenance

### Log Rotation

```bash
# Configure log rotation for monitoring components
# Grafana logs
docker compose --env-file .env exec grafana \
  find /var/log/grafana -name "*.log" -exec ls -la {} \;

# Prometheus data cleanup
docker compose --env-file .env exec prometheus \
  find /prometheus -name "*.db" -exec ls -lh {} \;
```

### Data Retention

```yaml
# Configure Prometheus retention
storage:
  tsdb:
    retention:
      time: 30d  # Keep data for 30 days
      size: 10GB # Or limit by size
```

### Backup Monitoring Data

```bash
# Backup Prometheus data
docker run --rm -v prometheus_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/prometheus_backup_$(date +%Y%m%d).tar.gz /data

# Backup Grafana configuration
docker run --rm -v grafana_data:/var/lib/grafana -v $(pwd):/backup alpine \
  tar czf /backup/grafana_backup_$(date +%Y%m%d).tar.gz /var/lib/grafana
```

## Integration with External Systems

### Alerting Integration

#### Email Alerts

```yaml
# SMTP configuration in Grafana
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.company.com:587
GF_SMTP_USER=monitoring@company.com
GF_SMTP_PASSWORD=secure_password
```

#### Slack Integration

```yaml
# Webhook configuration
alerting:
  webhooks:
    enabled: true
    urls:
      - "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

#### PagerDuty Integration

```yaml
# PagerDuty routing
route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'pagerduty'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
```

## Best Practices

### 1. Dashboard Organization
- **Group related metrics** logically
- **Use consistent color schemes** for similar metrics
- **Include documentation** in dashboard descriptions
- **Set appropriate refresh rates** for different panels

### 2. Alert Configuration
- **Test all alerts** before production deployment
- **Use appropriate thresholds** based on normal behavior
- **Include context** in alert messages
- **Configure escalation policies** for critical alerts

### 3. Performance Monitoring
- **Monitor resource usage** of monitoring components
- **Set up alerts** for monitoring system health
- **Regularly review** and optimize queries
- **Archive historical data** for trend analysis

### 4. Security
- **Use strong authentication** for Grafana
- **Restrict network access** to monitoring endpoints
- **Regularly rotate credentials** and tokens
- **Monitor access logs** for suspicious activity

## Conclusion

The monitoring dashboard provides comprehensive visibility into the PostgreSQL HA cluster's health, performance, and operational status. Key features include:

- **Real-time metrics** from all cluster components
- **Automated alerting** for proactive issue detection
- **Historical data** for trend analysis
- **Integration capabilities** with external systems
- **Customizable dashboards** for specific monitoring needs

Regular monitoring and alerting are essential for maintaining high availability and ensuring optimal performance of the PostgreSQL cluster.

For operational procedures, see the [Automated Failover Documentation](02-automated-failover.md) and [Manual Failover Documentation](03-manual-failover.md).