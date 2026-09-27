#!/bin/bash

# DHCP SQL Server - Server Component Test Runner
# This script tests the DHCP server component specifically

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
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
SERVER_PID=""

# Helper functions
log_info() {
    echo -e "${BLUE}[SERVER-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SERVER-PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[SERVER-FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[SERVER-WARN]${NC} $1"
}

# MySQL helper function
mysql_query() {
    mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN "$@"
}

run_server_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_info "Running server test: $test_name"

    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Wait for database to be ready
wait_for_database() {
    log_info "Waiting for database connection..."

    for i in {1..30}; do
        if mysql_query -e "SELECT 1" &>/dev/null; then
            log_success "Database connection established"
            return 0
        fi
        sleep 2
    done

    log_error "Database connection timeout"
    return 1
}

# Start DHCP server for testing
start_dhcp_server() {
    log_info "Starting DHCP server for testing..."

    # Ensure directories exist
    mkdir -p /var/lib/dhcp /var/log/dhcp

    # Check if udhcpd binary exists
    if ! command -v udhcpd &>/dev/null; then
        log_error "udhcpd binary not found"
        return 1
    fi

    # Start server in background
    udhcpd -f /etc/udhcpd.conf &
    SERVER_PID=$!

    # Wait for server to start
    sleep 3

    # Check if server is running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_error "DHCP server failed to start"
        return 1
    fi

    # Check if server is listening
    if ! netstat -lun | grep -q ":67 "; then
        log_error "DHCP server not listening on port 67"
        return 1
    fi

    log_success "DHCP server started (PID: $SERVER_PID)"
    return 0
}

# Stop DHCP server
stop_dhcp_server() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        log_info "Stopping DHCP server (PID: $SERVER_PID)..."
        kill $SERVER_PID
        wait $SERVER_PID 2>/dev/null || true
        log_success "DHCP server stopped"
    fi
}

# Test server binary functionality
test_server_binary() {
    # Test if binary exists and is executable
    if ! command -v udhcpd &>/dev/null; then
        log_error "udhcpd binary not found in PATH"
        return 1
    fi

    # Test version/help output
    if ! timeout 5 udhcpd --version &>/dev/null && ! timeout 5 udhcpd -h &>/dev/null; then
        log_warning "udhcpd version/help not available (this may be normal)"
    fi

    # Test configuration file parsing
    if ! udhcpd -t /etc/udhcpd.conf &>/dev/null; then
        log_warning "Configuration test failed (option may not be available)"
    fi

    return 0
}

# Test configuration file validation
test_configuration_validation() {
    local config_file="/etc/udhcpd.conf"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Check required configuration parameters
    local required_params=("interface" "start" "end" "lease_file")

    for param in "${required_params[@]}"; do
        if ! grep -q "^$param" "$config_file"; then
            log_error "Missing required parameter: $param"
            return 1
        fi
    done

    # Check MySQL configuration
    if ! grep -q "sqlserver" "$config_file"; then
        log_error "Missing MySQL server configuration"
        return 1
    fi

    # Check network configuration
    if ! grep -q "172.20" "$config_file"; then
        log_error "Missing test network configuration"
        return 1
    fi

    return 0
}

# Test server network binding
test_network_binding() {
    # Check if server can bind to DHCP port
    if ! netstat -lun | grep -q ":67 "; then
        log_error "DHCP server not bound to UDP port 67"
        return 1
    fi

    # Test socket permissions
    local socket_info
    socket_info=$(netstat -lupa 2>/dev/null | grep ":67 " | head -1)

    if [[ "$socket_info" == *"udhcpd"* ]]; then
        log_success "DHCP server properly bound to port 67"
    else
        log_warning "Port 67 bound but process not identified as udhcpd"
    fi

    return 0
}

# Test database connectivity from server
test_server_database_connection() {
    # The server should be able to connect to MySQL
    # We'll test this by checking if the server can read static leases

    # Insert a test lease
    local test_mac="0x123456789abc"
    local test_ip="INET_ATON('172.20.1.200')"

    mysql_query -e "INSERT INTO staticleases (mac, ip, class) VALUES ($test_mac, $test_ip, 1) ON DUPLICATE KEY UPDATE ip=$test_ip" &>/dev/null

    # Check server logs for database connections
    sleep 2

    if [ -f "/var/log/dhcp/udhcpd.log" ]; then
        if grep -q -i "mysql\|sql\|database" /var/log/dhcp/udhcpd.log; then
            log_success "Server appears to be using database"
        else
            log_warning "No database activity found in server logs"
        fi
    else
        log_warning "Server log file not found"
    fi

    # Clean up test data
    mysql_query -e "DELETE FROM staticleases WHERE mac = $test_mac" &>/dev/null

    return 0
}

# Test DHCP packet handling
test_dhcp_packet_handling() {
    # Test if server responds to DHCP DISCOVER packets
    local discover_response
    discover_response=$(timeout 10 python3 -c "
import socket
import struct
import time
import sys

def create_dhcp_discover():
    # Create a basic DHCP DISCOVER packet
    packet = bytearray(240)

    # DHCP header
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0

    # Transaction ID (random)
    packet[4:8] = struct.pack('>I', 0x12345678)

    # All other fields are 0 for DISCOVER

    # Magic cookie
    packet[236:240] = b'\x63\x82\x53\x63'

    return packet

try:
    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(5)

    # Bind to client port
    sock.bind(('0.0.0.0', 68))

    # Create and send DISCOVER packet
    discover_packet = create_dhcp_discover()
    sock.sendto(discover_packet, ('$DHCP_SERVER_IP', 67))

    # Wait for response
    response, addr = sock.recvfrom(1024)

    if len(response) >= 240:
        print('SUCCESS: Received DHCP response of {} bytes'.format(len(response)))
    else:
        print('WARNING: Received short response of {} bytes'.format(len(response)))

except socket.timeout:
    print('TIMEOUT: No response from DHCP server')
except Exception as e:
    print('ERROR: {}'.format(e))
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$discover_response" == *"SUCCESS"* ]]; then
        log_success "Server responds to DHCP DISCOVER packets"
        return 0
    elif [[ "$discover_response" == *"WARNING"* ]]; then
        log_warning "Server response seems incomplete: $discover_response"
        return 0
    else
        log_error "Server not responding to DHCP packets: $discover_response"
        return 1
    fi
}

# Test lease management
test_lease_management() {
    local lease_file="/var/lib/dhcp/udhcpd-test.leases"

    # Check if lease file exists and is writable
    if [ ! -f "$lease_file" ]; then
        touch "$lease_file" || {
            log_error "Cannot create lease file: $lease_file"
            return 1
        }
    fi

    if [ ! -w "$lease_file" ]; then
        log_error "Lease file not writable: $lease_file"
        return 1
    fi

    # Test dumpleases utility if available
    if command -v dumpleases &>/dev/null; then
        if dumpleases "$lease_file" &>/dev/null; then
            log_success "dumpleases utility working with lease file"
        else
            log_warning "dumpleases failed (may be normal if no active leases)"
        fi
    else
        log_warning "dumpleases utility not available"
    fi

    return 0
}

# Test static lease functionality
test_static_lease_functionality() {
    # Insert a test static lease
    local test_mac="001122334455"
    local test_ip="172.20.1.150"
    local test_class="1"

    mysql_query -e "INSERT INTO staticleases_readable (mac, ip, class) VALUES ('$test_mac', '$test_ip', $test_class) ON DUPLICATE KEY UPDATE ip='$test_ip'" &>/dev/null

    # The server should now be aware of this lease
    # We can't easily test the actual lease assignment without a real client,
    # but we can verify the data is accessible

    local lease_count
    lease_count=$(mysql_query -e "SELECT COUNT(*) FROM staticleases_readable WHERE mac='$test_mac'")

    if [ "$lease_count" != "1" ]; then
        log_error "Static lease not properly stored"
        return 1
    fi

    # Clean up
    mysql_query -e "DELETE FROM staticleases_readable WHERE mac='$test_mac'" &>/dev/null

    return 0
}

# Test server logging
test_server_logging() {
    local log_file="/var/log/dhcp/udhcpd.log"

    # Check if log directory exists
    if [ ! -d "/var/log/dhcp" ]; then
        mkdir -p /var/log/dhcp
    fi

    # Send a signal to the server to trigger log activity
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        kill -USR1 $SERVER_PID 2>/dev/null || true
        sleep 1
    fi

    # Check if logs are being written
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        log_success "Server logging is active"
    else
        log_warning "Server log file empty or missing"
    fi

    # Check for error messages in logs
    if [ -f "$log_file" ]; then
        local error_count
        error_count=$(grep -ci "error\|fail\|critical" "$log_file" 2>/dev/null || echo "0")

        if [ "$error_count" -gt 5 ]; then
            log_warning "Found $error_count error messages in server logs"
        fi
    fi

    return 0
}

# Test server resource usage
test_resource_usage() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        # Get memory usage
        local memory_kb
        memory_kb=$(ps -o rss= -p $SERVER_PID 2>/dev/null || echo "0")

        # Convert to MB
        local memory_mb=$((memory_kb / 1024))

        log_info "Server memory usage: ${memory_mb}MB"

        # Check if memory usage is reasonable (less than 100MB for a simple DHCP server)
        if [ "$memory_mb" -gt 100 ]; then
            log_warning "Server using more memory than expected: ${memory_mb}MB"
        fi

        # Get CPU usage (simplified check)
        local cpu_percent
        cpu_percent=$(ps -o %cpu= -p $SERVER_PID 2>/dev/null | tr -d ' ' || echo "0")

        log_info "Server CPU usage: ${cpu_percent}%"
    else
        log_error "Server process not running for resource usage test"
        return 1
    fi

    return 0
}

# Test server graceful shutdown
test_graceful_shutdown() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        # Send TERM signal for graceful shutdown
        kill -TERM $SERVER_PID

        # Wait for graceful shutdown (up to 10 seconds)
        local countdown=10
        while [ $countdown -gt 0 ] && kill -0 $SERVER_PID 2>/dev/null; do
            sleep 1
            ((countdown--))
        done

        if kill -0 $SERVER_PID 2>/dev/null; then
            log_warning "Server did not shut down gracefully, forcing..."
            kill -KILL $SERVER_PID
            wait $SERVER_PID 2>/dev/null || true
        else
            log_success "Server shut down gracefully"
        fi

        SERVER_PID=""
    fi

    return 0
}

# Generate server test report
generate_server_test_report() {
    mkdir -p "$TEST_RESULTS_DIR"

    cat >"$TEST_RESULTS_DIR/server_test_report.json" <<EOF
{
    "server_tests": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%",
        "timestamp": "$(date -Iseconds)"
    },
    "server_info": {
        "ip": "$DHCP_SERVER_IP",
        "config_file": "/etc/udhcpd.conf",
        "lease_file": "/var/lib/dhcp/udhcpd-test.leases"
    }
}
EOF

    echo
    echo "============================================"
    echo "           SERVER TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:    $TESTS_RUN"
    echo "Passed:         $TESTS_PASSED"
    echo "Failed:         $TESTS_FAILED"
    echo "Success Rate:   $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL SERVER TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED server tests failed"
        return 1
    fi
}

# Cleanup function
cleanup() {
    stop_dhcp_server
}

# Main execution
main() {
    log_info "Starting DHCP Server Component Tests..."

    # Setup cleanup trap
    trap cleanup EXIT INT TERM

    # Wait for database
    if ! wait_for_database; then
        log_error "Database not available"
        exit 1
    fi

    # Run tests that don't require a running server first
    run_server_test "server_binary" "test_server_binary"
    run_server_test "configuration_validation" "test_configuration_validation"

    # Start the server for runtime tests
    if start_dhcp_server; then
        run_server_test "network_binding" "test_network_binding"
        run_server_test "server_database_connection" "test_server_database_connection"
        run_server_test "dhcp_packet_handling" "test_dhcp_packet_handling"
        run_server_test "lease_management" "test_lease_management"
        run_server_test "static_lease_functionality" "test_static_lease_functionality"
        run_server_test "server_logging" "test_server_logging"
        run_server_test "resource_usage" "test_resource_usage"
        run_server_test "graceful_shutdown" "test_graceful_shutdown"
    else
        log_error "Could not start DHCP server for runtime tests"
        ((TESTS_FAILED += 8)) # Count the tests we couldn't run
        TESTS_RUN=$((TESTS_RUN + 8))
    fi

    # Generate report
    generate_server_test_report
}

# Execute main function
main "$@"
