# PostgreSQL HA Monitor

A comprehensive monitoring solution for PostgreSQL High Availability clusters using pg_auto_failover. This monitoring script provides real-time health checks, replication monitoring, failover validation, and alerting capabilities.

## Features

- **Health Monitoring**: Continuous monitoring of all PostgreSQL nodes in the cluster
- **Replication Lag Monitoring**: Real-time tracking of replication lag across all replicas
- **Failover Validation**: Automated testing of failover mechanisms and readiness
- **Alerting System**: Configurable alerts via email and webhooks
- **Docker Integration**: Seamless integration with existing Docker-based HA setup
- **Comprehensive Reporting**: Detailed health reports and cluster status
- **Prometheus Integration**: Optional metrics export for Grafana dashboards

## Installation

### Prerequisites

- Python 3.8 or higher
- Access to PostgreSQL HA cluster with pg_auto_failover
- Docker (for containerized deployment)

### Install Dependencies

```bash
cd monitoring
pip install -r requirements.txt
```

### Configuration

1. Copy the configuration template:
```bash
cp config.yaml.example config.yaml
```

2. Edit `config.yaml` with your cluster settings:
```yaml
database:
  monitor_host: "localhost"
  monitor_port: 5431
  postgres_password: "your_password"

nodes:
  primary:
    host: "localhost"
    port: 5432
  replica1:
    host: "localhost"
    port: 5433
  replica2:
    host: "localhost"
    port: 5434

alerting:
  email:
    to_emails:
      - "admin@example.com"
```

## Usage

### Basic Health Check

```bash
python pg_ha_monitor.py health
```

### Continuous Monitoring

```bash
python pg_ha_monitor.py monitor
```

### Test Failover Readiness

```bash
python pg_ha_monitor.py test-failover
```

### Get Cluster State

```bash
python pg_ha_monitor.py cluster-state
```

## Docker Integration

### Using Docker Compose

Add the monitoring service to your `docker-compose.yml`:

```yaml
services:
  pg-ha-monitor:
    build:
      context: .
      dockerfile: Dockerfile.monitor
    container_name: pg-ha-monitor
    volumes:
      - ./monitoring:/app/monitoring
    environment:
      - PGAF_MONITOR_HOST=pgaf-monitor
      - POSTGRES_PASSWORD=postgres_password
    networks:
      - postgres-cluster
    depends_on:
      - pgaf-monitor
      - postgres-primary
      - postgres-replica1
      - postgres-replica2
```

### Using Docker Run

```bash
docker run -it --network postgres-cluster \
  -e PGAF_MONITOR_HOST=pgaf-monitor \
  -e POSTGRES_PASSWORD=postgres_password \
  -v $(pwd)/monitoring:/app/monitoring \
  pg-ha-monitor python pg_ha_monitor.py monitor
```

## Configuration Options

### Database Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `monitor_host` | pg_auto_failover monitor hostname | localhost |
| `monitor_port` | Monitor port | 5431 |
| `postgres_password` | PostgreSQL password | postgres_password |

### Node Configuration

Define each node in your cluster:

```yaml
nodes:
  primary:
    host: "localhost"
    port: 5432
    name: "postgres-primary"
  replica1:
    host: "localhost"
    port: 5433
    name: "postgres-replica1"
```

### Thresholds

| Threshold | Description | Default |
|-----------|-------------|---------|
| `max_replication_lag_bytes` | Max replication lag before alert | 1MB |
| `connection_timeout_seconds` | Database connection timeout | 5s |
| `health_check_interval_seconds` | Health check frequency | 30s |

### Alerting

#### Email Alerts

```yaml
alerting:
  email:
    enabled: true
    smtp_server: "smtp.example.com"
    smtp_port: 587
    from_email: "monitor@example.com"
    to_emails:
      - "admin@example.com"
```

#### Webhook Alerts

```yaml
alerting:
  webhooks:
    enabled: true
    urls:
      - "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Alert Rules

The monitoring system includes several built-in alert rules:

- **Critical**: No primary node, multiple primaries
- **Warning**: Unhealthy nodes, high replication lag
- **Info**: Failover not ready (disabled by default)

### Custom Alert Rules

Extend the `check_alerts` method in `pg_ha_monitor.py` to add custom rules:

```python
AlertRule(
    name="custom_rule",
    condition="custom_condition",
    threshold=100,
    severity="warning"
)
```

## Monitoring Output

### Health Check Report

```
PostgreSQL HA Cluster Health Report
==================================
Generated: 2024-01-15 10:30:00
Duration: 0:00:01.234

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

### JSON Output

```bash
python pg_ha_monitor.py cluster-state | jq
```

## Integration with Existing Monitoring

### Prometheus

Enable Prometheus metrics export:

```yaml
integration:
  prometheus:
    enabled: true
    gateway_url: "http://localhost:9091"
```

### Grafana

The monitoring script integrates with your existing Grafana setup. The generated metrics can be visualized using the existing pg_auto_failover dashboard.

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Ensure the monitor and nodes are running
   - Check network connectivity
   - Verify port mappings in Docker

2. **Authentication Failed**
   - Check database credentials in config
   - Ensure pg_auto_failover monitor is accessible

3. **High Replication Lag**
   - Check network bandwidth
   - Verify disk I/O performance
   - Monitor system resources

### Debug Mode

Enable debug logging:

```yaml
logging:
  level: "DEBUG"
```

### Manual Testing

Test individual components:

```bash
# Test database connections
python -c "from pg_ha_monitor import PGHAMonitor; m = PGHAMonitor(); print(m.get_cluster_state())"

# Test health checks
python -c "from pg_ha_monitor import PGHAMonitor; m = PGHAMonitor(); print(m.perform_health_check())"
```

## Performance Considerations

- **Resource Usage**: The monitor uses minimal resources (~50MB RAM)
- **Network Impact**: Health checks generate light database queries
- **Storage**: Log files rotate automatically (max 100MB, 5 backups)
- **Scalability**: Designed for clusters up to 10 nodes

## Security

- Store sensitive credentials in environment variables
- Use TLS/SSL for email and webhook communications
- Implement proper authentication for webhook endpoints
- Regularly rotate database passwords

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review the logs in `monitoring/pg_ha_monitor.log`
3. Test with the provided debug commands
4. Open an issue with detailed information