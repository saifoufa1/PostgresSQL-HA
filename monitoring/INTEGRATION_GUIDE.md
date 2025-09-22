# PostgreSQL HA Monitor Integration Guide

This guide explains how to integrate the PostgreSQL HA monitoring system with your existing PostgreSQL HA cluster setup.

## Overview

The monitoring system consists of:
- **pg_ha_monitor.py**: Main monitoring script
- **config.yaml**: Configuration file
- **test_monitor.py**: Test suite
- **Docker integration**: Containerized deployment
- **Prometheus/Grafana integration**: Enhanced monitoring

## Quick Start

### 1. Setup the Monitor

```bash
# Navigate to monitoring directory
cd monitoring

# Install dependencies
pip install -r requirements.txt

# Setup configuration
./setup_monitor.sh setup
```

### 2. Test the Installation

```bash
# Quick test
./setup_monitor.sh quick-test

# Comprehensive test
./setup_monitor.sh test
```

### 3. Start Monitoring

```bash
# Start continuous monitoring
./setup_monitor.sh monitor

# Or run directly
python pg_ha_monitor.py monitor
```

## Integration with Existing Docker Setup

### Option 1: Docker Compose Integration

Add the monitoring service to your existing `docker-compose.yml`:

```yaml
services:
  pg-ha-monitor:
    build:
      context: ./monitoring
      dockerfile: Dockerfile
    container_name: pg-ha-monitor
    environment:
      - PGAF_MONITOR_HOST=pgaf-monitor
      - POSTGRES_PASSWORD=postgres_password
    volumes:
      - ./monitoring/logs:/app/logs
    networks:
      - postgres-cluster
    depends_on:
      - pgaf-monitor
    restart: unless-stopped
```

### Option 2: Standalone Docker Container

```bash
# Build the image
docker build -t pg-ha-monitor ./monitoring

# Run the container
docker run -it --network postgres-cluster \
  -e PGAF_MONITOR_HOST=pgaf-monitor \
  -e POSTGRES_PASSWORD=postgres_password \
  -v $(pwd)/monitoring/logs:/app/logs \
  pg-ha-monitor
```

## Configuration

### Basic Configuration

Edit `monitoring/config.yaml`:

```yaml
database:
  monitor_host: "pgaf-monitor"  # Use container name in Docker
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

### Alert Configuration

```yaml
alerting:
  email:
    enabled: true
    smtp_server: "your-smtp-server.com"
    from_email: "monitor@yourcompany.com"
    to_emails:
      - "admin@yourcompany.com"
      - "dba@yourcompany.com"

  webhooks:
    enabled: true
    urls:
      - "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Usage Examples

### Health Check

```bash
python pg_ha_monitor.py health
```

Output:
```
PostgreSQL HA Cluster Health Report
==================================
Generated: 2024-01-15 10:30:00

Cluster Overview:
- Primary nodes: 1
- Replica nodes: 2
- Unhealthy nodes: 0
- Failover ready: true

Node Details:
✅ postgres-primary (172.28.0.10:5432) - primary
✅ postgres-replica1 (172.28.0.11:5432) - secondary, Lag: 0.12MB
✅ postgres-replica2 (172.28.0.12:5432) - secondary, Lag: 0.08MB
```

### Failover Testing

```bash
python pg_ha_monitor.py test-failover
```

### Continuous Monitoring

```bash
python pg_ha_monitor.py monitor
```

### Get Cluster State (JSON)

```bash
python pg_ha_monitor.py cluster-state | jq
```

## Monitoring Features

### Health Checks
- **Node connectivity**: Verify all nodes are reachable
- **PostgreSQL status**: Check PostgreSQL process health
- **Role validation**: Ensure proper primary/replica roles
- **Replication status**: Monitor replication health

### Replication Monitoring
- **Lag detection**: Track replication lag in bytes and time
- **Sync status**: Monitor synchronous/asynchronous replication
- **WAL status**: Check write-ahead log status

### Failover Validation
- **Readiness check**: Verify cluster is ready for failover
- **Priority validation**: Check node priorities
- **Network connectivity**: Test inter-node communication

### Alerting
- **Email alerts**: SMTP-based email notifications
- **Webhook alerts**: HTTP POST to external systems
- **Configurable thresholds**: Custom alert conditions
- **Cooldown periods**: Prevent alert spam

## Integration with Prometheus/Grafana

### Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'pg-ha-monitor'
    static_configs:
      - targets: ['pg-ha-monitor:8000']
    scrape_interval: 15s
```

### Grafana Dashboard

The monitoring system integrates with your existing Grafana setup. Import the enhanced dashboard:

```bash
# Copy dashboard to Grafana dashboards directory
cp monitoring/grafana/dashboard.json /path/to/grafana/dashboards/
```

## Troubleshooting

### Common Issues

1. **Connection Refused**
   ```bash
   # Check if PostgreSQL HA cluster is running
   docker compose ps

   # Check network connectivity
   docker compose exec pgaf-monitor netstat -tlnp | grep 5431
   ```

2. **Authentication Failed**
   ```bash
   # Verify credentials in config.yaml
   # Check pg_auto_failover monitor logs
   docker compose logs pgaf-monitor
   ```

3. **High Replication Lag**
   ```bash
   # Check replication status
   python pg_ha_monitor.py health

   # Check system resources
   docker stats
   ```

### Debug Mode

Enable debug logging in `config.yaml`:

```yaml
logging:
  level: "DEBUG"
```

### Manual Testing

```bash
# Test individual components
python -c "from pg_ha_monitor import PGHAMonitor; m = PGHAMonitor(); print(m.get_cluster_state())"
python -c "from pg_ha_monitor import PGHAMonitor; m = PGHAMonitor(); print(m.perform_health_check())"
```

## Performance Impact

- **Resource Usage**: ~50MB RAM, minimal CPU
- **Network Traffic**: Light queries every 30 seconds
- **Storage**: Log rotation (100MB max, 5 backups)
- **Database Load**: Minimal (health checks only)

## Security Considerations

- Store credentials in environment variables
- Use TLS for email/webhook communications
- Implement proper authentication for webhooks
- Regularly rotate database passwords
- Run container as non-root user

## Maintenance

### Log Rotation
Logs automatically rotate when they reach 100MB, keeping 5 backups.

### Health Check Frequency
Default: 30 seconds (configurable in config.yaml)

### Alert Cooldown
Prevents alert spam with configurable cooldown periods.

## Support

For issues:
1. Check logs in `monitoring/pg_ha_monitor.log`
2. Run comprehensive tests: `./setup_monitor.sh test`
3. Review troubleshooting section
4. Check GitHub issues for known problems

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   pg-ha-monitor │────│ pg_auto_failover │────│ PostgreSQL Nodes│
│                 │    │    monitor       │    │                 │
│ - Health checks │    │ - State tracking │    │ - Primary       │
│ - Alerting      │    │ - Failover coord │    │ - Replicas      │
│ - Reporting     │    │ - Node management│    │ - Replication   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Email/Webhook   │    │ Prometheus/Grafana│    │ Log Files       │
│ Alerts          │    │ Metrics Export   │    │ Detailed Reports│
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Next Steps

1. **Deploy**: Set up the monitoring system in your environment
2. **Configure**: Customize alerting and thresholds
3. **Test**: Run comprehensive tests to validate setup
4. **Monitor**: Start continuous monitoring
5. **Integrate**: Connect with your existing monitoring tools
6. **Alert**: Set up alerting for your team

The monitoring system is now ready for production use! 🚀