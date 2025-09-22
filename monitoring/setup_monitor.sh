#!/bin/bash
# PostgreSQL HA Monitor Setup Script
# This script helps set up and test the PostgreSQL HA monitoring system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MONITOR_DIR="monitoring"
CONFIG_FILE="$MONITOR_DIR/config.yaml"
LOG_FILE="$MONITOR_DIR/pg_ha_monitor.log"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8 or higher."
        exit 1
    fi

    # Check Docker (optional)
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. Docker integration will not be available."
    fi

    # Check if PostgreSQL HA cluster is running
    if ! docker compose ps | grep -q "pgaf-monitor\|postgres-primary"; then
        log_warning "PostgreSQL HA cluster does not appear to be running."
        log_warning "Please start the cluster first: docker compose up -d"
    fi

    log_success "Prerequisites check completed"
}

install_dependencies() {
    log_info "Installing Python dependencies..."

    if [ -f "$MONITOR_DIR/requirements.txt" ]; then
        pip3 install -r "$MONITOR_DIR/requirements.txt"
        log_success "Dependencies installed successfully"
    else
        log_error "requirements.txt not found in $MONITOR_DIR"
        exit 1
    fi
}

create_config() {
    log_info "Setting up configuration..."

    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Creating default configuration file..."

        # Create config from template or defaults
        cat > "$CONFIG_FILE" << 'EOF'
# PostgreSQL HA Monitor Configuration
database:
  monitor_host: "localhost"
  monitor_port: 5431
  monitor_database: "pg_auto_failover"
  monitor_user: "autoctl_node"
  monitor_password: "autoctl_node"
  postgres_password: "postgres_password"

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

thresholds:
  max_replication_lag_bytes: 1048576
  connection_timeout_seconds: 5
  health_check_interval_seconds: 30

alerting:
  email:
    enabled: false
    to_emails: []
  webhooks:
    enabled: false
    urls: []
EOF
        log_success "Configuration file created at $CONFIG_FILE"
        log_warning "Please review and update the configuration file with your settings"
    else
        log_info "Configuration file already exists at $CONFIG_FILE"
    fi
}

test_monitor() {
    log_info "Testing monitor installation..."

    if [ ! -f "$MONITOR_DIR/pg_ha_monitor.py" ]; then
        log_error "Monitor script not found at $MONITOR_DIR/pg_ha_monitor.py"
        exit 1
    fi

    # Test basic functionality
    cd "$MONITOR_DIR"
    python3 pg_ha_monitor.py health > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Monitor script is working correctly"
    else
        log_error "Monitor script test failed"
        exit 1
    fi
}

run_comprehensive_test() {
    log_info "Running comprehensive test suite..."

    cd "$MONITOR_DIR"
    python3 test_monitor.py comprehensive
}

run_quick_test() {
    log_info "Running quick health check..."

    cd "$MONITOR_DIR"
    python3 test_monitor.py quick
}

build_docker_image() {
    log_info "Building Docker image..."

    if command -v docker &> /dev/null; then
        docker build -t pg-ha-monitor "$MONITOR_DIR"
        log_success "Docker image built successfully"
    else
        log_error "Docker is not available"
        exit 1
    fi
}

start_monitoring() {
    log_info "Starting continuous monitoring..."

    cd "$MONITOR_DIR"
    python3 pg_ha_monitor.py monitor
}

show_usage() {
    echo "PostgreSQL HA Monitor Setup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup         - Complete setup (install deps, create config, test)"
    echo "  install       - Install Python dependencies"
    echo "  config        - Create/update configuration file"
    echo "  test          - Run comprehensive test suite"
    echo "  quick-test    - Run quick health check"
    echo "  docker-build  - Build Docker image"
    echo "  monitor       - Start continuous monitoring"
    echo "  help          - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 test"
    echo "  $0 monitor"
}

# Main script
main() {
    case "${1:-help}" in
        "setup")
            check_prerequisites
            install_dependencies
            create_config
            test_monitor
            log_success "Setup completed successfully!"
            log_info "Run '$0 test' to validate the installation"
            ;;
        "install")
            install_dependencies
            ;;
        "config")
            create_config
            ;;
        "test")
            check_prerequisites
            run_comprehensive_test
            ;;
        "quick-test")
            check_prerequisites
            run_quick_test
            ;;
        "docker-build")
            build_docker_image
            ;;
        "monitor")
            check_prerequisites
            start_monitoring
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"