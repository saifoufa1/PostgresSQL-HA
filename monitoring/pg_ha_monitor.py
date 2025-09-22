#!/usr/bin/env python3
"""
PostgreSQL High Availability Cluster Monitor

A comprehensive monitoring script for PostgreSQL HA clusters using pg_auto_failover.
Monitors cluster health, replication status, failover mechanisms, and generates alerts.

Features:
- Health checks for all nodes
- Replication lag monitoring
- Failover validation
- Configurable alerting system
- Integration with Docker setup
- Comprehensive logging and reporting
"""

import asyncio
import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
import psycopg2
from psycopg2.extras import RealDictCursor
import requests
import yaml
from dataclasses import dataclass, asdict
from enum import Enum
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import socket


class NodeState(Enum):
    UNKNOWN = -1
    DRAINING = 0
    WAIT_STANDBY = 1
    SECONDARY = 2
    PRIMARY = 3
    SINGLE = 4


class HealthStatus(Enum):
    HEALTHY = 1
    UNHEALTHY = -1
    UNKNOWN = 0


@dataclass
class NodeInfo:
    """Information about a PostgreSQL node"""
    name: str
    hostname: str
    port: int
    role: str
    state: NodeState
    health: HealthStatus
    replication_lag: Optional[int] = None
    last_seen: Optional[datetime] = None
    connection_status: bool = False
    pg_version: Optional[str] = None


@dataclass
class ClusterHealth:
    """Overall cluster health status"""
    timestamp: datetime
    nodes: List[NodeInfo]
    primary_count: int
    replica_count: int
    unhealthy_nodes: int
    max_replication_lag: Optional[int]
    failover_ready: bool
    issues: List[str]


@dataclass
class AlertRule:
    """Alert configuration"""
    name: str
    condition: str
    threshold: float
    severity: str  # 'critical', 'warning', 'info'
    enabled: bool = True
    cooldown_minutes: int = 5


class PGHAMonitor:
    """Main PostgreSQL HA monitoring class"""

    def __init__(self, config_path: str = "monitoring/config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.alert_history: Dict[str, datetime] = {}
        self.monitor_connection = None
        self.node_connections: Dict[str, psycopg2.connection] = {}

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML file"""
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)

            # Set defaults
            config.setdefault('database', {})
            config['database'].setdefault('monitor_host', 'localhost')
            config['database']['monitor_host'] = os.getenv('PGAF_MONITOR_HOST', config['database']['monitor_host'])
            config['database'].setdefault('monitor_port', 5431)
            config['database'].setdefault('monitor_database', 'pg_auto_failover')
            config['database'].setdefault('monitor_user', 'autoctl_node')
            config['database'].setdefault('monitor_password', 'autoctl_node')

            config.setdefault('nodes', {})
            config['nodes'].setdefault('primary', {'host': 'localhost', 'port': 5432})
            config['nodes'].setdefault('replica1', {'host': 'localhost', 'port': 5433})
            config['nodes'].setdefault('replica2', {'host': 'localhost', 'port': 5434})

            config.setdefault('thresholds', {})
            config['thresholds'].setdefault('max_replication_lag_bytes', 1000000)  # 1MB
            config['thresholds'].setdefault('max_replication_lag_seconds', 30)
            config['thresholds'].setdefault('connection_timeout_seconds', 5)
            config['thresholds'].setdefault('health_check_interval_seconds', 30)

            config.setdefault('alerting', {})
            config['alerting'].setdefault('email', {})
            config['alerting']['email'].setdefault('smtp_server', 'localhost')
            config['alerting']['email'].setdefault('smtp_port', 587)
            config['alerting']['email'].setdefault('from_email', 'monitor@example.com')
            config['alerting']['email'].setdefault('to_emails', [])
            config['alerting'].setdefault('webhook_urls', [])

            return config

        except FileNotFoundError:
            self.logger.error(f"Configuration file not found: {config_path}")
            return {}
        except yaml.YAMLError as e:
            self.logger.error(f"Error parsing configuration file: {e}")
            return {}

    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logger = logging.getLogger('pg_ha_monitor')
        logger.setLevel(logging.INFO)

        # Create handlers
        console_handler = logging.StreamHandler(sys.stdout)
        file_handler = logging.FileHandler('monitoring/pg_ha_monitor.log')

        # Create formatters
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        console_handler.setFormatter(formatter)
        file_handler.setFormatter(formatter)

        # Add handlers to logger
        logger.addHandler(console_handler)
        logger.addHandler(file_handler)

        return logger

    def _get_monitor_connection(self) -> Optional[psycopg2.connection]:
        """Get connection to pg_auto_failover monitor"""
        try:
            conn = psycopg2.connect(
                host=self.config['database']['monitor_host'],
                port=self.config['database']['monitor_port'],
                database=self.config['database']['monitor_database'],
                user=self.config['database']['monitor_user'],
                password=self.config['database']['monitor_password'],
                connect_timeout=self.config['thresholds']['connection_timeout_seconds']
            )
            return conn
        except Exception as e:
            self.logger.error(f"Failed to connect to monitor: {e}")
            return None

    def _get_node_connection(self, node_name: str) -> Optional[psycopg2.connection]:
        """Get connection to a specific PostgreSQL node"""
        if node_name in self.node_connections:
            return self.node_connections[node_name]

        try:
            node_config = self.config['nodes'].get(node_name, {})
            conn = psycopg2.connect(
                host=node_config.get('host', 'localhost'),
                port=node_config.get('port', 5432),
                database='postgres',
                user='postgres',
                password=self.config['database'].get('postgres_password', 'postgres_password'),
                connect_timeout=self.config['thresholds']['connection_timeout_seconds']
            )
            self.node_connections[node_name] = conn
            return conn
        except Exception as e:
            self.logger.error(f"Failed to connect to node {node_name}: {e}")
            return None

    def get_cluster_state(self) -> Optional[Dict[str, Any]]:
        """Get cluster state from pg_auto_failover monitor"""
        conn = self._get_monitor_connection()
        if not conn:
            return None

        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT nodeid, nodename, nodehost, nodeport,
                           reportedstate, health, reportedlsn,
                           goalstate, statechangetime
                    FROM pgautofailover.node
                    ORDER BY nodeid
                """)
                nodes = cursor.fetchall()

                cursor.execute("""
                    SELECT name, kind, number_sync_standbys
                    FROM pgautofailover.formation
                """)
                formation = cursor.fetchone()

                return {
                    'nodes': nodes,
                    'formation': formation,
                    'timestamp': datetime.now()
                }
        except Exception as e:
            self.logger.error(f"Failed to get cluster state: {e}")
            return None
        finally:
            conn.close()

    def check_node_health(self, node_info: Dict[str, Any]) -> Tuple[HealthStatus, str]:
        """Check health of a specific node"""
        node_name = node_info['nodename']
        conn = self._get_node_connection(node_name)

        if not conn:
            return HealthStatus.UNHEALTHY, "Cannot connect to node"

        try:
            with conn.cursor() as cursor:
                # Check if PostgreSQL is responding
                cursor.execute("SELECT 1")
                result = cursor.fetchone()

                if not result:
                    return HealthStatus.UNHEALTHY, "No response from PostgreSQL"

                # Get PostgreSQL version
                cursor.execute("SELECT version()")
                version = cursor.fetchone()[0]

                # Check if node is in recovery (replica)
                cursor.execute("SELECT pg_is_in_recovery()")
                in_recovery = cursor.fetchone()[0]

                # Get replication lag if this is a replica
                lag_bytes = None
                if in_recovery:
                    cursor.execute("""
                        SELECT COALESCE(
                            pg_last_wal_receive_time(),
                            pg_last_wal_replay_time()
                        ) as last_activity
                    """)
                    last_activity = cursor.fetchone()[0]

                    if last_activity:
                        lag_seconds = (datetime.now() - last_activity.replace(tzinfo=None)).total_seconds()
                        lag_bytes = int(lag_seconds * 1024 * 1024)  # Rough estimate
                    else:
                        lag_bytes = 999999999  # Very high lag

                return HealthStatus.HEALTHY, f"PostgreSQL {version.split()[1]}"

        except Exception as e:
            return HealthStatus.UNHEALTHY, f"Health check failed: {e}"
        finally:
            conn.close()
            if node_name in self.node_connections:
                del self.node_connections[node_name]

    def get_replication_status(self, node_name: str) -> Optional[Dict[str, Any]]:
        """Get detailed replication status for a node"""
        conn = self._get_node_connection(node_name)
        if not conn:
            return None

        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT
                        client_addr,
                        client_hostname,
                        state,
                        sync_state,
                        pg_current_wal_lsn() - replay_lsn as replay_lag_bytes,
                        pg_current_wal_lsn() - received_lsn as receive_lag_bytes,
                        extract(epoch from now() - pg_last_wal_receive_time()) as receive_lag_seconds,
                        extract(epoch from now() - pg_last_wal_replay_time()) as replay_lag_seconds,
                        backend_start
                    FROM pg_stat_replication
                """)
                replication_stats = cursor.fetchall()

                return {
                    'node': node_name,
                    'replication_slots': replication_stats,
                    'timestamp': datetime.now()
                }
        except Exception as e:
            self.logger.error(f"Failed to get replication status for {node_name}: {e}")
            return None
        finally:
            conn.close()
            if node_name in self.node_connections:
                del self.node_connections[node_name]

    def perform_health_check(self) -> ClusterHealth:
        """Perform comprehensive health check of the cluster"""
        cluster_state = self.get_cluster_state()
        if not cluster_state:
            return ClusterHealth(
                timestamp=datetime.now(),
                nodes=[],
                primary_count=0,
                replica_count=0,
                unhealthy_nodes=1,
                max_replication_lag=None,
                failover_ready=False,
                issues=["Cannot connect to pg_auto_failover monitor"]
            )

        nodes = []
        primary_count = 0
        replica_count = 0
        unhealthy_nodes = 0
        max_lag = 0
        issues = []

        for node_data in cluster_state['nodes']:
            # Map state codes to enum
            state_code = node_data['reportedstate']
            try:
                state = NodeState(state_code)
            except ValueError:
                state = NodeState.UNKNOWN

            # Check node health
            health, health_message = self.check_node_health(node_data)

            # Count roles
            if state == NodeState.PRIMARY:
                primary_count += 1
            elif state in [NodeState.SECONDARY, NodeState.WAIT_STANDBY]:
                replica_count += 1

            # Track unhealthy nodes
            if health == HealthStatus.UNHEALTHY:
                unhealthy_nodes += 1
                issues.append(f"Node {node_data['nodename']}: {health_message}")

            # Get replication lag for replicas
            replication_lag = None
            if state in [NodeState.SECONDARY, NodeState.WAIT_STANDBY]:
                rep_status = self.get_replication_status(node_data['nodename'])
                if rep_status and rep_status['replication_slots']:
                    for slot in rep_status['replication_slots']:
                        lag = slot.get('replay_lag_bytes', 0)
                        if lag and lag > max_lag:
                            max_lag = lag
                        if lag:
                            replication_lag = lag

            node_info = NodeInfo(
                name=node_data['nodename'],
                hostname=node_data['nodehost'],
                port=node_data['nodeport'],
                role=state.name.lower(),
                state=state,
                health=health,
                replication_lag=replication_lag,
                last_seen=node_data['statechangetime']
            )

            nodes.append(node_info)

        # Determine if failover is ready
        failover_ready = (
            primary_count == 1 and
            replica_count >= 1 and
            unhealthy_nodes == 0
        )

        if primary_count == 0:
            issues.append("No primary node found")
            failover_ready = False
        elif primary_count > 1:
            issues.append("Multiple primary nodes detected")
            failover_ready = False

        return ClusterHealth(
            timestamp=cluster_state['timestamp'],
            nodes=nodes,
            primary_count=primary_count,
            replica_count=replica_count,
            unhealthy_nodes=unhealthy_nodes,
            max_replication_lag=max_lag if max_lag > 0 else None,
            failover_ready=failover_ready,
            issues=issues
        )

    def check_alerts(self, health: ClusterHealth) -> List[Dict[str, Any]]:
        """Check if any alert conditions are met"""
        alerts = []
        current_time = datetime.now()

        # Define alert rules
        alert_rules = [
            AlertRule(
                name="no_primary",
                condition="primary_count == 0",
                threshold=0,
                severity="critical"
            ),
            AlertRule(
                name="multiple_primaries",
                condition="primary_count > 1",
                threshold=1,
                severity="critical"
            ),
            AlertRule(
                name="unhealthy_nodes",
                condition="unhealthy_nodes > 0",
                threshold=0,
                severity="warning"
            ),
            AlertRule(
                name="high_replication_lag",
                condition="max_replication_lag is not None",
                threshold=self.config['thresholds']['max_replication_lag_bytes'],
                severity="warning"
            ),
            AlertRule(
                name="failover_not_ready",
                condition="not failover_ready",
                threshold=0,
                severity="info"
            )
        ]

        for rule in alert_rules:
            if not rule.enabled:
                continue

            # Check cooldown period
            last_alert = self.alert_history.get(rule.name)
            if last_alert and (current_time - last_alert).total_seconds() < (rule.cooldown_minutes * 60):
                continue

            # Evaluate condition
            should_alert = False
            try:
                if rule.name == "no_primary":
                    should_alert = health.primary_count == 0
                elif rule.name == "multiple_primaries":
                    should_alert = health.primary_count > 1
                elif rule.name == "unhealthy_nodes":
                    should_alert = health.unhealthy_nodes > 0
                elif rule.name == "high_replication_lag":
                    should_alert = (
                        health.max_replication_lag is not None and
                        health.max_replication_lag > rule.threshold
                    )
                elif rule.name == "failover_not_ready":
                    should_alert = not health.failover_ready
            except Exception as e:
                self.logger.error(f"Error evaluating alert rule {rule.name}: {e}")
                continue

            if should_alert:
                alert = {
                    'rule': rule.name,
                    'severity': rule.severity,
                    'message': self._generate_alert_message(rule, health),
                    'timestamp': current_time,
                    'health_data': asdict(health)
                }
                alerts.append(alert)
                self.alert_history[rule.name] = current_time

        return alerts

    def _generate_alert_message(self, rule: AlertRule, health: ClusterHealth) -> str:
        """Generate human-readable alert message"""
        if rule.name == "no_primary":
            return "CRITICAL: No primary node found in the cluster"
        elif rule.name == "multiple_primaries":
            return "CRITICAL: Multiple primary nodes detected"
        elif rule.name == "unhealthy_nodes":
            return f"WARNING: {health.unhealthy_nodes} unhealthy node(s) detected"
        elif rule.name == "high_replication_lag":
            lag_mb = health.max_replication_lag / (1024 * 1024) if health.max_replication_lag else 0
            return f"WARNING: High replication lag detected: {lag_mb:.2f} MB"
        elif rule.name == "failover_not_ready":
            return "INFO: Cluster not ready for failover"
        return f"Alert triggered: {rule.name}"

    def send_alert(self, alert: Dict[str, Any]) -> bool:
        """Send alert via configured channels"""
        success = False

        # Send email alerts
        if self.config['alerting']['email']['to_emails']:
            success = self._send_email_alert(alert) or success

        # Send webhook alerts
        if self.config['alerting']['webhook_urls']:
            success = self._send_webhook_alert(alert) or success

        return success

    def _send_email_alert(self, alert: Dict[str, Any]) -> bool:
        """Send alert via email"""
        try:
            config = self.config['alerting']['email']

            msg = MIMEMultipart()
            msg['From'] = config['from_email']
            msg['To'] = ', '.join(config['to_emails'])
            msg['Subject'] = f"PostgreSQL HA Alert: {alert['severity'].upper()}"

            body = f"""
PostgreSQL HA Cluster Alert

Severity: {alert['severity'].upper()}
Time: {alert['timestamp']}
Rule: {alert['rule']}

Message: {alert['message']}

Cluster Status:
- Primary nodes: {alert['health_data']['primary_count']}
- Replica nodes: {alert['health_data']['replica_count']}
- Unhealthy nodes: {alert['health_data']['unhealthy_nodes']}
- Failover ready: {alert['health_data']['failover_ready']}

Issues detected:
{chr(10).join('- ' + issue for issue in alert['health_data']['issues'])}
            """

            msg.attach(MIMEText(body, 'plain'))

            server = smtplib.SMTP(config['smtp_server'], config['smtp_port'])
            server.starttls()
            server.send_message(msg)
            server.quit()

            self.logger.info(f"Email alert sent: {alert['message']}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to send email alert: {e}")
            return False

    def _send_webhook_alert(self, alert: Dict[str, Any]) -> bool:
        """Send alert via webhook"""
        success = False
        for webhook_url in self.config['alerting']['webhook_urls']:
            try:
                response = requests.post(
                    webhook_url,
                    json=alert,
                    headers={'Content-Type': 'application/json'},
                    timeout=10
                )

                if response.status_code in [200, 201, 202]:
                    self.logger.info(f"Webhook alert sent to {webhook_url}")
                    success = True
                else:
                    self.logger.error(f"Webhook alert failed: {response.status_code} - {response.text}")

            except Exception as e:
                self.logger.error(f"Failed to send webhook alert to {webhook_url}: {e}")

        return success

    def generate_report(self, health: ClusterHealth) -> str:
        """Generate detailed cluster health report"""
        report = f"""
PostgreSQL HA Cluster Health Report
==================================
Generated: {health.timestamp}
Duration: {datetime.now() - health.timestamp}

Cluster Overview:
- Primary nodes: {health.primary_count}
- Replica nodes: {health.replica_count}
- Unhealthy nodes: {health.unhealthy_nodes}
- Failover ready: {health.failover_ready}

Node Details:
"""

        for node in health.nodes:
            status_icon = "✅" if node.health == HealthStatus.HEALTHY else "❌"
            lag_info = f", Lag: {node.replication_lag / (1024*1024):.2f}MB" if node.replication_lag else ""
            report += f"{status_icon} {node.name} ({node.hostname}:{node.port}) - {node.role}{lag_info}\n"

        if health.issues:
            report += "\nIssues Detected:\n"
            for issue in health.issues:
                report += f"- {issue}\n"

        return report

    async def monitor_loop(self):
        """Main monitoring loop"""
        self.logger.info("Starting PostgreSQL HA monitoring...")

        while True:
            try:
                # Perform health check
                health = self.perform_health_check()

                # Check for alerts
                alerts = self.check_alerts(health)

                # Send alerts
                for alert in alerts:
                    self.send_alert(alert)

                # Log status
                if alerts:
                    self.logger.warning(f"Alerts triggered: {len(alerts)}")
                    for alert in alerts:
                        self.logger.warning(f"  - {alert['message']}")
                else:
                    self.logger.info(f"Cluster healthy - Primary: {health.primary_count}, Replicas: {health.replica_count}")

                # Generate and save report
                report = self.generate_report(health)
                with open('monitoring/cluster_report.txt', 'w') as f:
                    f.write(report)

                # Wait for next check
                await asyncio.sleep(self.config['thresholds']['health_check_interval_seconds'])

            except Exception as e:
                self.logger.error(f"Error in monitoring loop: {e}")
                await asyncio.sleep(60)  # Wait longer on errors

    def test_failover(self) -> Dict[str, Any]:
        """Test failover mechanism"""
        self.logger.info("Testing failover mechanism...")

        # Get current state
        initial_state = self.get_cluster_state()
        if not initial_state:
            return {'success': False, 'error': 'Cannot get cluster state'}

        # Find current primary
        primary_node = None
        for node in initial_state['nodes']:
            if node['reportedstate'] == 3:  # PRIMARY
                primary_node = node
                break

        if not primary_node:
            return {'success': False, 'error': 'No primary node found'}

        self.logger.info(f"Current primary: {primary_node['nodename']}")

        # Simulate failover by stopping primary (in real scenario, this would be done differently)
        # For testing, we'll just check if failover would be possible
        health = self.perform_health_check()

        test_result = {
            'success': health.failover_ready,
            'current_primary': primary_node['nodename'],
            'replica_count': health.replica_count,
            'unhealthy_nodes': health.unhealthy_nodes,
            'issues': health.issues,
            'timestamp': datetime.now()
        }

        if health.failover_ready:
            self.logger.info("✅ Failover test passed - cluster is ready for failover")
        else:
            self.logger.warning("❌ Failover test failed - cluster not ready for failover")

        return test_result


def main():
    """Main entry point"""
    monitor = PGHAMonitor()

    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == "health":
            health = monitor.perform_health_check()
            print(monitor.generate_report(health))

        elif command == "test-failover":
            result = monitor.test_failover()
            print(json.dumps(result, indent=2, default=str))

        elif command == "cluster-state":
            state = monitor.get_cluster_state()
            if state:
                print(json.dumps(state, indent=2, default=str))
            else:
                print("Failed to get cluster state")

        elif command == "monitor":
            asyncio.run(monitor.monitor_loop())

        else:
            print("Usage: python pg_ha_monitor.py [health|test-failover|cluster-state|monitor]")
            sys.exit(1)
    else:
        # Default to health check
        health = monitor.perform_health_check()
        print(monitor.generate_report(health))


if __name__ == "__main__":
    main()