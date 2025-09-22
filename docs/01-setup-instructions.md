# PostgreSQL High Availability Setup Guide

This comprehensive guide provides step-by-step instructions for setting up and configuring the PostgreSQL High Availability solution using pg_auto_failover.

## Overview

The PostgreSQL HA solution consists of:
- **1 Monitor Node**: Orchestrates failover and health monitoring
- **3 PostgreSQL Nodes**: Primary + 2 replicas with different failover priorities
- **Monitoring Stack**: Prometheus metrics collection + Grafana dashboards
- **Healthcare Database**: Realistic schema with sample patient/provider data

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   pgaf-monitor  │────│ pg_auto_failover │────│ PostgreSQL Nodes│
│   (172.28.0.5)  │    │    monitor       │    │                 │
│ - Coordination  │    │ - State tracking │    │ - Primary       │
│ - Health checks │    │ - Failover coord │    │ - Replicas      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ postgres-exporter│    │ Prometheus       │    │ Grafana         │
│ (172.28.0.20)   │    │ (172.28.0.21)    │    │ (172.28.0.30)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Prerequisites

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

## Quick Start

### 1. Clone and Setup Environment

```bash
# Clone the repository
git clone <repository-url>
cd postgresql-ha-challenge

# Copy environment configuration
cp .env.test .env

# Start the complete stack
docker compose --env-file .env up -d --build
```

### 2. Verify Deployment

```bash
# Check container status
docker compose --env-file .env ps

# Verify cluster state
docker compose --env-file .env exec pgaf-monitor bash /opt/pgaf/show-state.sh | jq

# Check primary node
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5432 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery();"

# Check replica status
PGPASSWORD=postgres_password psql -h 127.0.0.1 -p 5433 -U postgres -d healthcare_db \
  -c "SELECT pg_is_in_recovery();"
```

**Expected Results**:
- Monitor shows 1 primary, 2 replicas
- Primary returns `f` (not in recovery)
- Replicas return `t` (in recovery)
- Both nodes show same record count

### 3. Access Monitoring Dashboard

- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090

## Detailed Setup Process

### Environment Configuration

The system supports two environment profiles:

#### Test Environment (`.env.test`)
```bash
LOAD_SCHEMA=true
LOAD_TEST_DATA=true
APP_USER=admin
APP_PASSWORD=admin
POSTGRES_PASSWORD=postgres_password
PG_HBA_CIDR=0.0.0.0/0
```

#### Production Environment (`.env.prod`)
```bash
LOAD_SCHEMA=true
LOAD_TEST_DATA=false
APP_USER=your_app_user
APP_PASSWORD=secure_password
POSTGRES_PASSWORD=secure_postgres_password
PG_HBA_CIDR=172.28.0.0/24
```

### Node Configuration

#### Monitor Node (`pgaf-monitor`)
- **Role**: Cluster coordination and health monitoring
- **Port**: 5431
- **Database**: `pg_auto_failover`
- **Volume**: `monitor_data`

#### Primary Node (`postgres-primary`)
- **Role**: Bootstrap and primary database operations
- **Port**: 5432
- **Priority**: 100 (highest)
- **Volume**: `postgres-primary`
- **Features**: Schema and test data loading

#### Replica Nodes
- **Replica 1** (`postgres-replica1`): Port 5433, Priority 90
- **Replica 2** (`postgres-replica2`): Port 5434, Priority 80

### Boot Sequence

1. **Monitor Initialization**: `pgaf-monitor` creates the monitor database and starts listening on port 5431
2. **Primary Bootstrap**: `postgres-primary` registers, becomes primary, applies schema/data, exposes port 5432
3. **Replica Registration**: `postgres-replica1` and `postgres-replica2` register and enter streaming replication
4. **Monitoring Stack**: `postgres-exporter`, Prometheus, and Grafana come online

## Configuration Files

### Docker Compose Configuration
- **File**: `docker-compose.yml`
- **Services**: Monitor, 3 PostgreSQL nodes, exporter, Prometheus, Grafana
- **Network**: `postgres-cluster` (172.28.0.0/24)
- **Volumes**: Persistent data storage for all nodes

### PostgreSQL Configuration
- **Primary**: `config/primary/postgresql.conf`
- **Replicas**: `config/replica/postgresql.conf`
- **HBA**: `config/*/pg_hba.conf`

### Monitoring Configuration
- **Prometheus**: `monitoring/prometheus.yml`
- **Grafana**: `monitoring/grafana/dashboards/pg_auto_failover.json`

## Initial Data Setup

### Schema Loading
The primary node automatically loads the healthcare database schema:
- **File**: `sql/01-schema.sql`
- **Database**: `healthcare_db`
- **Tables**: Patients, providers, facilities, appointments, audit logs

### Test Data
Sample healthcare data is loaded for testing:
- **File**: `sql/02-test-data.sql`
- **Records**: Sample patients, providers, facilities, appointments

## Security Considerations

### Authentication
- **Superuser**: `postgres` / `postgres_password`
- **Application User**: Configurable via `APP_USER` / `APP_PASSWORD`
- **Monitor Access**: `autoctl_node` (internal use only)

### Network Security
- **Test Environment**: Open access (`0.0.0.0/0`)
- **Production Environment**: Restricted to cluster network (`172.28.0.0/24`)

### TLS/SSL
- Not configured by default
- Recommended for production deployments
- Configure in PostgreSQL configuration files

## Performance Tuning

### Memory Configuration
```bash
# Recommended settings for 8GB+ systems
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 64MB
maintenance_work_mem = 512MB
```

### Connection Limits
```bash
max_connections = 200
```

### Replication Settings
```bash
wal_level = replica
max_wal_senders = 10
wal_keep_segments = 64
```

## Troubleshooting Setup Issues

### Port Conflicts
```bash
# Check port usage
netstat -tulpn | grep -E ':(5431|5432|5433|5434|6010|6011|6012|9090|9187|3000)'

# Stop conflicting services or modify ports in docker-compose.yml
```

### Monitor Connection Issues
```bash
# Check monitor logs
docker compose --env-file .env logs pgaf-monitor

# Test monitor connectivity
docker compose --env-file .env exec postgres-primary \
  psql -h pgaf-monitor -p 5431 -U autoctl_node -d pg_auto_failover -c "SELECT 1;"
```

### Data Directory Issues
```bash
# Check volume permissions
docker volume ls
docker volume inspect postgresql-ha-challenge_postgres-primary

# Reset volumes if needed
docker compose --env-file .env down -v
```

## Next Steps

After successful setup:
1. **Verify cluster health** using the monitoring dashboard
2. **Test failover scenarios** (see failover documentation)
3. **Configure backups** for production use
4. **Set up alerting** for critical events
5. **Performance test** with your application workload

## Support

For issues during setup:
1. Check the troubleshooting section above
2. Review container logs: `docker compose --env-file .env logs`
3. Verify system resources: `docker stats`
4. Check network connectivity between containers

The setup is now complete and ready for testing and production use! 🚀