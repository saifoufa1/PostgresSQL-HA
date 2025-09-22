#!/usr/bin/env python3
"""
Test script for PostgreSQL HA Monitor

This script validates the monitoring system functionality and can be used
to test the monitor in a safe environment before production deployment.
"""

import sys
import time
import json
from pg_ha_monitor import PGHAMonitor


def test_database_connections(monitor: PGHAMonitor) -> bool:
    """Test database connections"""
    print("🧪 Testing database connections...")

    try:
        # Test monitor connection
        state = monitor.get_cluster_state()
        if not state:
            print("❌ Failed to connect to pg_auto_failover monitor")
            return False

        print("✅ Monitor connection successful")

        # Test node connections
        for node_name in ['primary', 'replica1', 'replica2']:
            node_config = monitor.config['nodes'].get(node_name, {})
            if node_config:
                conn = monitor._get_node_connection(node_name)
                if conn:
                    print(f"✅ {node_name} connection successful")
                    conn.close()
                else:
                    print(f"❌ {node_name} connection failed")
                    return False

        return True

    except Exception as e:
        print(f"❌ Database connection test failed: {e}")
        return False


def test_health_checks(monitor: PGHAMonitor) -> bool:
    """Test health check functionality"""
    print("🧪 Testing health checks...")

    try:
        health = monitor.perform_health_check()

        print("✅ Health check completed")
        print(f"   Primary nodes: {health.primary_count}")
        print(f"   Replica nodes: {health.replica_count}")
        print(f"   Unhealthy nodes: {health.unhealthy_nodes}")
        print(f"   Failover ready: {health.failover_ready}")

        if health.issues:
            print("   Issues found:")
            for issue in health.issues:
                print(f"   - {issue}")

        return True

    except Exception as e:
        print(f"❌ Health check test failed: {e}")
        return False


def test_alert_system(monitor: PGHAMonitor) -> bool:
    """Test alert system"""
    print("🧪 Testing alert system...")

    try:
        # Perform health check to get current state
        health = monitor.perform_health_check()

        # Check for alerts
        alerts = monitor.check_alerts(health)

        print(f"✅ Alert check completed - {len(alerts)} alerts found")

        for alert in alerts:
            print(f"   {alert['severity'].upper()}: {alert['message']}")

        # Test alert sending (if configured)
        if alerts and monitor.config['alerting']['email']['to_emails']:
            print("🔔 Testing alert delivery...")
            for alert in alerts[:1]:  # Test with first alert only
                success = monitor.send_alert(alert)
                if success:
                    print("✅ Alert sent successfully")
                else:
                    print("❌ Alert sending failed")

        return True

    except Exception as e:
        print(f"❌ Alert system test failed: {e}")
        return False


def test_failover_validation(monitor: PGHAMonitor) -> bool:
    """Test failover validation"""
    print("🧪 Testing failover validation...")

    try:
        result = monitor.test_failover()

        print("✅ Failover test completed")
        print(f"   Success: {result['success']}")
        print(f"   Current primary: {result.get('current_primary', 'N/A')}")
        print(f"   Replica count: {result.get('replica_count', 0)}")

        if result.get('issues'):
            print("   Issues found:")
            for issue in result['issues']:
                print(f"   - {issue}")

        return result['success']

    except Exception as e:
        print(f"❌ Failover validation test failed: {e}")
        return False


def test_reporting(monitor: PGHAMonitor) -> bool:
    """Test reporting functionality"""
    print("🧪 Testing reporting...")

    try:
        health = monitor.perform_health_check()
        report = monitor.generate_report(health)

        # Save report to file
        with open('monitoring/test_report.txt', 'w') as f:
            f.write(report)

        print("✅ Report generated successfully")
        print("   Report saved to: monitoring/test_report.txt")
        print("   Report preview:")
        print("=" * 50)
        print(report[:500] + "..." if len(report) > 500 else report)
        print("=" * 50)

        return True

    except Exception as e:
        print(f"❌ Reporting test failed: {e}")
        return False


def run_comprehensive_test() -> bool:
    """Run comprehensive test suite"""
    print("🚀 Starting PostgreSQL HA Monitor Comprehensive Test")
    print("=" * 60)

    # Initialize monitor
    try:
        monitor = PGHAMonitor("monitoring/config.yaml")
        print("✅ Monitor initialized successfully")
    except Exception as e:
        print(f"❌ Monitor initialization failed: {e}")
        return False

    # Test suite
    tests = [
        ("Database Connections", test_database_connections),
        ("Health Checks", test_health_checks),
        ("Alert System", test_alert_system),
        ("Failover Validation", test_failover_validation),
        ("Reporting", test_reporting)
    ]

    results = []
    for test_name, test_func in tests:
        print(f"\n📋 Running {test_name}...")
        try:
            result = test_func(monitor)
            results.append((test_name, result))
            print(f"{'✅' if result else '❌'} {test_name} {'PASSED' if result else 'FAILED'}")
        except Exception as e:
            print(f"❌ {test_name} ERROR: {e}")
            results.append((test_name, False))

    # Summary
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"  {status} - {test_name}")

    print(f"\nOverall: {passed}/{total} tests passed")

    if passed == total:
        print("🎉 All tests passed! Monitor is ready for production.")
        return True
    else:
        print("⚠️  Some tests failed. Please review the issues above.")
        return False


def run_quick_test() -> bool:
    """Run quick health check only"""
    print("⚡ Running quick health check...")

    try:
        monitor = PGHAMonitor("monitoring/config.yaml")
        health = monitor.perform_health_check()
        report = monitor.generate_report(health)

        print("✅ Quick test completed")
        print(report)

        return health.primary_count > 0 and health.unhealthy_nodes == 0

    except Exception as e:
        print(f"❌ Quick test failed: {e}")
        return False


def main():
    """Main test entry point"""
    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == "comprehensive":
            success = run_comprehensive_test()
            sys.exit(0 if success else 1)

        elif command == "quick":
            success = run_quick_test()
            sys.exit(0 if success else 1)

        elif command == "health":
            monitor = PGHAMonitor("monitoring/config.yaml")
            health = monitor.perform_health_check()
            print(monitor.generate_report(health))
            sys.exit(0)

        else:
            print("Usage: python test_monitor.py [comprehensive|quick|health]")
            sys.exit(1)
    else:
        # Default to quick test
        success = run_quick_test()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()