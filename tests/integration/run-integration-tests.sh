#!/bin/bash

# DHCP SQL Server - Comprehensive Integration Test Runner
# This script runs all integration tests and validates the complete DHCP system

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-/tmp/test-results}"
export LOG_DIR="/var/log/dhcp"
export CONFIG_DIR="/app/config"
export MYSQL_HOST="${MYSQL_HOST:-mysql-test}"
export MYSQL_USER="${MYSQL_USER:-dhcp_test}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-dhcp_test}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-dhcp_test}"
export DHCP_SERVER_IP="${DHCP_SERVER_IP:-172.20.0.10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s)

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local timeout="${3:-30}"

    ((TESTS_RUN++))
    log_info "Running test: $test_name"

    if timeout "$timeout" bash -c "$test_command" &>"$TEST_RESULTS_DIR/${test_name}.log"; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name (see ${test_name}.log for details)"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service="$1"
    local port="$2"
    local host="${3:-localhost}"
    local timeout="${4:-60}"

    log_info "Waiting for $service on $host:$port..."

    for i in $(seq 1 $timeout); do
        if nc -z "$host" "$port" 2>/dev/null; then
            log_success "$service is ready"
            return 0
        fi
        sleep 1
    done

    log_error "$service failed to start within $timeout seconds"
    return 1
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."

    # Create directories with proper permissions
    mkdir -p "$TEST_RESULTS_DIR" "$LOG_DIR" 2>/dev/null || true
    chmod 777 "$TEST_RESULTS_DIR" 2>/dev/null || true

    # Ensure results directory exists and is writable
    mkdir -p "$TEST_RESULTS_DIR" 2>/dev/null || true
    chmod 777 "$TEST_RESULTS_DIR" 2>/dev/null || true

    # Create test summary file
    cat >"$TEST_RESULTS_DIR/test_summary.json" <<EOF
{
    "test_run": {
        "start_time": "$(date -Iseconds)",
        "environment": {
            "mysql_host": "$MYSQL_HOST",
            "dhcp_server": "$DHCP_SERVER_IP",
            "test_mode": "$TEST_MODE"
        }
    }
}
EOF

    log_success "Test environment setup complete"
}

# Test database connectivity
test_database_connectivity() {
    log_info "Testing database connectivity..."

    # Test basic connection
    if ! mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT 1" &>/dev/null; then
        log_error "Cannot connect to MySQL database"
        return 1
    fi

    # Test schema validation
    local expected_tables=("options" "staticleases" "staticleases_readable" "metaoptions")
    for table in "${expected_tables[@]}"; do
        if ! mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "DESCRIBE $table" &>/dev/null; then
            log_error "Required table $table not found"
            return 1
        fi
    done

    # Test data validation
    local lease_count
    lease_count=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "SELECT COUNT(*) FROM staticleases")
    if [ "$lease_count" -lt 5 ]; then
        log_error "Insufficient test data in staticleases table (found: $lease_count, expected: >=5)"
        return 1
    fi

    log_success "Database connectivity and schema validation passed"
}

# Test DHCP server process
test_dhcp_server_process() {
    log_info "Testing DHCP server process..."

    # Check if server is listening on DHCP port
    if ! nc -u -z "$DHCP_SERVER_IP" 67 2>/dev/null; then
        log_error "DHCP server not listening on port 67"
        return 1
    fi

    # Test server response to DHCP discover
    local test_result
    test_result=$(timeout 10 python3 -c "
import socket
import struct
import time

# Create DHCP discover packet
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.settimeout(5)

# Basic DHCP discover packet structure
discover_packet = bytearray(240)
discover_packet[0] = 1    # Message type: Boot Request
discover_packet[1] = 1    # Hardware type: Ethernet
discover_packet[2] = 6    # Hardware address length
discover_packet[3] = 0    # Hops
discover_packet[4:8] = struct.pack('>I', 0x12345678)  # Transaction ID
discover_packet[236:240] = b'\x63\x82\x53\x63'  # Magic cookie

try:
    sock.sendto(discover_packet, ('$DHCP_SERVER_IP', 67))
    response, addr = sock.recvfrom(1024)
    print('SUCCESS: Received DHCP response')
except Exception as e:
    print(f'FAILED: {e}')
finally:
    sock.close()
" 2>&1)

    if [[ "$test_result" == *"SUCCESS"* ]]; then
        log_success "DHCP server responding to requests"
    else
        log_error "DHCP server not responding properly: $test_result"
        return 1
    fi
}

# Test static lease assignment
test_static_lease_assignment() {
    log_info "Testing static lease assignment..."

    # Test database static lease lookup
    local test_mac="001122aabbcc"
    local expected_ip="172.20.1.100"

    local assigned_ip
    assigned_ip=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "
        SELECT ip FROM staticleases_readable WHERE mac='$test_mac'
    ")

    if [ "$assigned_ip" != "$expected_ip" ]; then
        log_error "Static lease lookup failed. Expected: $expected_ip, Got: $assigned_ip"
        return 1
    fi

    log_success "Static lease assignment test passed"
}

# Test DHCP options retrieval
test_dhcp_options() {
    log_info "Testing DHCP options retrieval..."

    # Test global options
    local global_options_count
    global_options_count=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "
        SELECT COUNT(*) FROM options WHERE class = 0
    ")

    if [ "$global_options_count" -lt 5 ]; then
        log_error "Insufficient global DHCP options (found: $global_options_count, expected: >=5)"
        return 1
    fi

    # Test class-specific options
    local class1_options_count
    class1_options_count=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "
        SELECT COUNT(*) FROM options WHERE class = 1
    ")

    if [ "$class1_options_count" -lt 2 ]; then
        log_error "Insufficient class 1 DHCP options (found: $class1_options_count, expected: >=2)"
        return 1
    fi

    log_success "DHCP options retrieval test passed"
}

# Test lease file operations
test_lease_file_operations() {
    log_info "Testing lease file operations..."

    local lease_file="/var/lib/dhcp/udhcpd-test.leases"

    # Create test lease entry if file doesn't exist
    if [ ! -f "$lease_file" ]; then
        touch "$lease_file"
    fi

    # Test lease file is writable
    if [ ! -w "$lease_file" ]; then
        log_error "Lease file is not writable: $lease_file"
        return 1
    fi

    # Test dumpleases utility if available
    if command -v dumpleases &>/dev/null; then
        if ! dumpleases "$lease_file" &>/dev/null; then
            log_warning "dumpleases utility test failed (may be expected if no active leases)"
        else
            log_success "dumpleases utility working"
        fi
    fi

    log_success "Lease file operations test passed"
}

# Test configuration file parsing
test_configuration_parsing() {
    log_info "Testing configuration file parsing..."

    local config_file="/etc/udhcpd.conf"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Test configuration syntax
    if ! grep -q "interface" "$config_file"; then
        log_error "Missing interface configuration in $config_file"
        return 1
    fi

    if ! grep -q "start.*172.20" "$config_file"; then
        log_error "Missing or incorrect IP range in $config_file"
        return 1
    fi

    # Test MySQL configuration
    if ! grep -q "sqlserver.*$MYSQL_HOST" "$config_file"; then
        log_error "Missing or incorrect MySQL server configuration"
        return 1
    fi

    log_success "Configuration file parsing test passed"
}

# Test error handling and edge cases
test_error_handling() {
    log_info "Testing error handling..."

    # Test invalid MAC address handling
    local invalid_result
    invalid_result=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "
        SELECT COUNT(*) FROM staticleases_readable WHERE mac='invalid_mac'
    " 2>/dev/null || echo "0")

    if [ "$invalid_result" != "0" ]; then
        log_error "Invalid MAC address should return 0 results, got: $invalid_result"
        return 1
    fi

    # Test IP address boundary conditions
    local boundary_test
    boundary_test=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN -e "
        SELECT COUNT(*) FROM staticleases WHERE ip = INET_ATON('0.0.0.0')
    ")

    if [ "$boundary_test" -gt 0 ]; then
        log_warning "Found leases with invalid IP 0.0.0.0"
    fi

    log_success "Error handling test passed"
}

# Test performance with multiple operations
test_performance() {
    log_info "Testing performance with multiple database operations..."

    local start_time_perf
    start_time_perf=$(date +%s%N)

    # Perform multiple database queries to test performance
    for i in {1..10}; do
        mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "
            SELECT COUNT(*) FROM staticleases;
            SELECT COUNT(*) FROM options;
            SELECT * FROM staticleases LIMIT 5;
        " &>/dev/null || {
            log_error "Performance test query failed on iteration $i"
            return 1
        }
    done

    local end_time_perf
    end_time_perf=$(date +%s%N)
    local duration_ms=$(((end_time_perf - start_time_perf) / 1000000))

    if [ "$duration_ms" -gt 5000 ]; then
        log_warning "Performance test took ${duration_ms}ms (expected <5000ms)"
    else
        log_success "Performance test passed (${duration_ms}ms for 10 iterations)"
    fi
}

# Test cleanup and resource management
test_cleanup() {
    log_info "Testing cleanup and resource management..."

    # Test that test procedures exist and work
    if mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "CALL validate_test_setup()" &>/dev/null; then
        log_success "Test validation procedure working"
    else
        log_error "Test validation procedure failed"
        return 1
    fi

    # Test cleanup procedure
    if mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "CALL cleanup_test_leases()" &>/dev/null; then
        log_success "Test cleanup procedure working"
    else
        log_warning "Test cleanup procedure failed (may be expected)"
    fi
}

# Generate test report
generate_test_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    # Ensure results directory exists
    mkdir -p "$TEST_RESULTS_DIR" 2>/dev/null || true

    cat >"$TEST_RESULTS_DIR/integration_test_report.json" <<EOF
{
    "test_summary": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc)%",
        "duration_seconds": $duration,
        "timestamp": "$(date -Iseconds)"
    },
    "environment": {
        "mysql_host": "$MYSQL_HOST",
        "mysql_database": "$MYSQL_DATABASE",
        "dhcp_server_ip": "$DHCP_SERVER_IP"
    }
}
EOF

    echo
    echo "============================================"
    echo "         INTEGRATION TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:    $TESTS_RUN"
    echo "Passed:         $TESTS_PASSED"
    echo "Failed:         $TESTS_FAILED"
    echo "Success Rate:   $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc)%"
    echo "Duration:       ${duration}s"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL INTEGRATION TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED integration tests failed"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting DHCP SQL Server Integration Tests..."

    # Setup
    setup_test_environment

    # Wait for dependencies
    if ! wait_for_service "MySQL" 3306 "$MYSQL_HOST" 60; then
        log_error "MySQL service not available"
        exit 1
    fi

    # Run all tests
    run_test "database_connectivity" "test_database_connectivity" 30
    run_test "dhcp_server_process" "test_dhcp_server_process" 30
    run_test "static_lease_assignment" "test_static_lease_assignment" 15
    run_test "dhcp_options" "test_dhcp_options" 15
    run_test "lease_file_operations" "test_lease_file_operations" 15
    run_test "configuration_parsing" "test_configuration_parsing" 10
    run_test "error_handling" "test_error_handling" 20
    run_test "performance" "test_performance" 60
    run_test "cleanup" "test_cleanup" 15

    # Generate report and exit
    generate_test_report
}

# Handle script interruption
trap 'log_error "Integration tests interrupted"; exit 130' INT TERM

# Execute main function
main "$@"
