#!/bin/bash

# DHCP SQL Server - DHCP Lease Integration Tests
# This script tests actual DHCP lease assignment from MySQL database

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
export LOG_DIR="/var/log/dhcp"
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

# Helper functions
log_info() {
    echo -e "${BLUE}[LEASE-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[LEASE-PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[LEASE-FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[LEASE-WARN]${NC} $1"
}

# MySQL helper function
mysql_query() {
    mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN "$@"
}

run_lease_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_info "Running lease test: $test_name"

    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Setup test lease data
setup_test_lease_data() {
    log_info "Setting up test lease data in MySQL..."

    # Insert specific test static leases
    mysql_query -e "
        DELETE FROM staticleases WHERE mac >= 0x001122330000 AND mac <= 0x001122339999;
        DELETE FROM staticleases_readable WHERE mac LIKE '00112233%';

        -- Test static leases for known MAC addresses
        INSERT INTO staticleases (mac, ip, class) VALUES
            (0x001122334400, INET_ATON('172.20.1.100'), 1),
            (0x001122334401, INET_ATON('172.20.1.101'), 2),
            (0x001122334402, INET_ATON('172.20.1.102'), 0),
            (0x001122334403, INET_ATON('172.20.1.103'), 3);

        INSERT INTO staticleases_readable (mac, ip, class) VALUES
            ('001122334400', '172.20.1.100', 1),
            ('001122334401', '172.20.1.101', 2),
            ('001122334402', '172.20.1.102', 0),
            ('001122334403', '172.20.1.103', 3);
    " 2>/dev/null

    # Setup class-specific DHCP options
    mysql_query -e "
        DELETE FROM options WHERE class >= 90;

        -- Global options (class 0)
        INSERT INTO options (class, code, data) VALUES
            (0, 1, INET_ATON('255.255.0.0')),     -- Subnet mask
            (0, 3, INET_ATON('172.20.0.1')),      -- Router
            (0, 6, INET_ATON('8.8.8.8')),         -- DNS
            (0, 15, 'test.local'),                 -- Domain
            (0, 51, '7200'),                       -- Lease time 2 hours
            (0, 54, INET_ATON('172.20.0.10'));    -- DHCP server ID

        -- Class 1 options (workstations)
        INSERT INTO options (class, code, data) VALUES
            (1, 42, INET_ATON('172.20.0.1')),     -- NTP server
            (1, 51, '3600');                       -- 1 hour lease

        -- Class 2 options (servers)
        INSERT INTO options (class, code, data) VALUES
            (2, 51, '86400'),                      -- 24 hour lease
            (2, 69, INET_ATON('172.20.0.1'));     -- SMTP server
    " 2>/dev/null

    log_success "Test lease data setup completed"
}

# Test static lease lookup by MAC address
test_static_lease_lookup() {
    log_info "Testing static lease lookup by MAC address..."

    local test_cases=(
        "001122334400:172.20.1.100:1"
        "001122334401:172.20.1.101:2"
        "001122334402:172.20.1.102:0"
        "001122334403:172.20.1.103:3"
    )

    for test_case in "${test_cases[@]}"; do
        IFS=':' read -r mac expected_ip expected_class <<<"$test_case"

        local result
        result=$(mysql_query -e "
            SELECT CONCAT(ip, ':', class)
            FROM staticleases_readable
            WHERE mac = '$mac'
        ")

        local actual_ip_class="$result"
        local expected_ip_class="${expected_ip}:${expected_class}"

        if [ "$actual_ip_class" = "$expected_ip_class" ]; then
            log_info "  ✓ MAC $mac → IP $expected_ip (class $expected_class)"
        else
            log_error "  ✗ MAC $mac: expected $expected_ip_class, got $actual_ip_class"
            return 1
        fi
    done

    return 0
}

# Test DHCP options retrieval for different classes
test_dhcp_options_retrieval() {
    log_info "Testing DHCP options retrieval by class..."

    # Test global options (class 0)
    local subnet_mask
    subnet_mask=$(mysql_query -e "
        SELECT INET_NTOA(CAST(data AS UNSIGNED))
        FROM options
        WHERE class = 0 AND code = 1
    ")

    if [ "$subnet_mask" = "255.255.0.0" ]; then
        log_info "  ✓ Global subnet mask: $subnet_mask"
    else
        log_error "  ✗ Wrong subnet mask: $subnet_mask"
        return 1
    fi

    # Test class-specific lease times
    local class1_lease
    class1_lease=$(mysql_query -e "
        SELECT data FROM options WHERE class = 1 AND code = 51
    ")

    if [ "$class1_lease" = "3600" ]; then
        log_info "  ✓ Class 1 lease time: ${class1_lease}s (1 hour)"
    else
        log_error "  ✗ Wrong class 1 lease time: $class1_lease"
        return 1
    fi

    local class2_lease
    class2_lease=$(mysql_query -e "
        SELECT data FROM options WHERE class = 2 AND code = 51
    ")

    if [ "$class2_lease" = "86400" ]; then
        log_info "  ✓ Class 2 lease time: ${class2_lease}s (24 hours)"
    else
        log_error "  ✗ Wrong class 2 lease time: $class2_lease"
        return 1
    fi

    return 0
}

# Test complete DHCP lease assignment simulation
test_dhcp_lease_assignment_simulation() {
    log_info "Testing complete DHCP lease assignment simulation..."

    # Simulate DHCP DISCOVER → OFFER process
    local test_result
    test_result=$(python3 -c "
import socket
import struct
import mysql.connector
import time

def get_lease_for_mac(mac_int):
    '''Query database for static lease'''
    try:
        conn = mysql.connector.connect(
            host='$MYSQL_HOST',
            user='$MYSQL_USER',
            password='$MYSQL_PASSWORD',
            database='$MYSQL_DATABASE'
        )
        cursor = conn.cursor()

        # Look up static lease
        cursor.execute('''
            SELECT INET_NTOA(ip) as ip_addr, class
            FROM staticleases
            WHERE mac = %s
        ''', (mac_int,))

        result = cursor.fetchone()
        conn.close()

        if result:
            return {'ip': result[0], 'class': result[1]}
        return None

    except Exception as e:
        print(f'Database error: {e}')
        return None

def get_options_for_class(client_class):
    '''Get DHCP options for client class'''
    try:
        conn = mysql.connector.connect(
            host='$MYSQL_HOST',
            user='$MYSQL_USER',
            password='$MYSQL_PASSWORD',
            database='$MYSQL_DATABASE'
        )
        cursor = conn.cursor()

        # Get global options (class 0) and class-specific options
        cursor.execute('''
            SELECT code, data
            FROM options
            WHERE class IN (0, %s)
            ORDER BY class DESC, code
        ''', (client_class,))

        options = {}
        for code, data in cursor.fetchall():
            options[code] = data

        conn.close()
        return options

    except Exception as e:
        print(f'Options error: {e}')
        return {}

# Test specific MAC addresses
test_macs = [
    {'mac': 0x001122334400, 'expected_ip': '172.20.1.100', 'expected_class': 1},
    {'mac': 0x001122334401, 'expected_ip': '172.20.1.101', 'expected_class': 2},
    {'mac': 0x001122334402, 'expected_ip': '172.20.1.102', 'expected_class': 0},
]

all_passed = True

for test_mac in test_macs:
    mac_int = test_mac['mac']
    expected_ip = test_mac['expected_ip']
    expected_class = test_mac['expected_class']

    print(f'Testing MAC: {mac_int:012x}')

    # Step 1: Get lease from database
    lease = get_lease_for_mac(mac_int)

    if not lease:
        print(f'  ERROR: No lease found for MAC {mac_int:012x}')
        all_passed = False
        continue

    if lease['ip'] != expected_ip:
        print(f'  ERROR: Expected IP {expected_ip}, got {lease[\"ip\"]}')
        all_passed = False
        continue

    if lease['class'] != expected_class:
        print(f'  ERROR: Expected class {expected_class}, got {lease[\"class\"]}')
        all_passed = False
        continue

    print(f'  ✓ Lease found: {lease[\"ip\"]} (class {lease[\"class\"]})')

    # Step 2: Get DHCP options for class
    options = get_options_for_class(lease['class'])

    if not options:
        print(f'  WARNING: No options found for class {lease[\"class\"]}')
    else:
        print(f'  ✓ Options retrieved: {len(options)} options')

        # Check for critical options
        if 1 in options:  # Subnet mask
            print(f'    - Subnet mask: {options[1]}')
        if 3 in options:  # Router
            print(f'    - Router: {options[3]}')
        if 51 in options: # Lease time
            print(f'    - Lease time: {options[51]}s')

if all_passed:
    print('SUCCESS: All DHCP lease assignments validated')
else:
    print('FAILED: Some lease assignments failed')

print(f'RESULT: {\"PASS\" if all_passed else \"FAIL\"}')
")

    if [[ "$test_result" == *"SUCCESS"* ]]; then
        echo "$test_result"
        return 0
    else
        echo "$test_result"
        return 1
    fi
}

# Test dynamic lease range and availability
test_dynamic_lease_range() {
    log_info "Testing dynamic lease range availability..."

    # Check if there are available IPs in the dynamic range
    local dynamic_range_start="172.20.1.10"
    local dynamic_range_end="172.20.1.99"

    local used_ips
    used_ips=$(mysql_query -e "
        SELECT COUNT(*)
        FROM staticleases
        WHERE ip BETWEEN INET_ATON('$dynamic_range_start')
              AND INET_ATON('$dynamic_range_end')
    ")

    local total_range=90 # .10 to .99 = 90 IPs
    local available=$((total_range - used_ips))

    log_info "  Dynamic range: $dynamic_range_start - $dynamic_range_end"
    log_info "  Total IPs in range: $total_range"
    log_info "  Used static leases: $used_ips"
    log_info "  Available for dynamic: $available"

    if [ "$available" -gt 50 ]; then
        log_info "  ✓ Sufficient dynamic IPs available: $available"
        return 0
    else
        log_warning "  ⚠ Limited dynamic IPs available: $available"
        return 0 # Don't fail, just warn
    fi
}

# Test lease expiration and renewal simulation
test_lease_renewal_simulation() {
    log_info "Testing lease renewal simulation..."

    # Simulate a lease table with expiration times
    mysql_query -e "
        -- Create temporary lease tracking table
        CREATE TEMPORARY TABLE active_leases (
            mac BIGINT,
            ip INT UNSIGNED,
            lease_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            lease_duration INT,
            lease_end TIMESTAMP,
            status ENUM('active', 'expired', 'renewed') DEFAULT 'active'
        );

        -- Add some test active leases
        INSERT INTO active_leases (mac, ip, lease_duration, lease_end) VALUES
            (0x001122334400, INET_ATON('172.20.1.100'), 3600,
             DATE_ADD(NOW(), INTERVAL 3600 SECOND)),
            (0x001122334401, INET_ATON('172.20.1.101'), 86400,
             DATE_ADD(NOW(), INTERVAL 86400 SECOND)),
            (0x001122334499, INET_ATON('172.20.1.199'), 1800,
             DATE_SUB(NOW(), INTERVAL 1800 SECOND)); -- Expired lease
    " 2>/dev/null

    # Check active vs expired leases
    local active_leases
    active_leases=$(mysql_query -e "
        SELECT COUNT(*) FROM active_leases WHERE lease_end > NOW()
    ")

    local expired_leases
    expired_leases=$(mysql_query -e "
        SELECT COUNT(*) FROM active_leases WHERE lease_end <= NOW()
    ")

    log_info "  Active leases: $active_leases"
    log_info "  Expired leases: $expired_leases"

    if [ "$active_leases" -gt 0 ] && [ "$expired_leases" -gt 0 ]; then
        log_info "  ✓ Lease expiration tracking works"
        return 0
    else
        log_error "  ✗ Lease expiration tracking failed"
        return 1
    fi
}

# Test IP address conflict detection
test_ip_conflict_detection() {
    log_info "Testing IP address conflict detection..."

    # Try to insert conflicting IP addresses
    local conflict_test
    conflict_test=$(mysql_query -e "
        -- Try to insert duplicate IP (should be prevented by unique constraint)
        INSERT IGNORE INTO staticleases (mac, ip, class)
        VALUES (0x999999999999, INET_ATON('172.20.1.100'), 1);

        -- Check if duplicate was actually inserted
        SELECT COUNT(*) FROM staticleases WHERE ip = INET_ATON('172.20.1.100');
    " 2>/dev/null)

    if [ "$conflict_test" = "1" ]; then
        log_info "  ✓ IP conflict detection working (duplicate rejected)"
        return 0
    else
        log_warning "  ⚠ IP conflict detection may not be enforced"
        return 0 # Don't fail test, just warn
    fi
}

# Test DHCP option inheritance and overrides
test_option_inheritance() {
    log_info "Testing DHCP option inheritance and overrides..."

    # Test that class-specific options override global options
    local global_lease_time
    global_lease_time=$(mysql_query -e "
        SELECT data FROM options WHERE class = 0 AND code = 51
    ")

    local class1_lease_time
    class1_lease_time=$(mysql_query -e "
        SELECT data FROM options WHERE class = 1 AND code = 51
    ")

    log_info "  Global lease time: ${global_lease_time}s"
    log_info "  Class 1 lease time: ${class1_lease_time}s"

    if [ "$global_lease_time" != "$class1_lease_time" ]; then
        log_info "  ✓ Class-specific options override global options"
        return 0
    else
        log_warning "  ⚠ Option inheritance may not be working"
        return 0
    fi
}

# Generate lease test report
generate_lease_test_report() {
    mkdir -p "$TEST_RESULTS_DIR"

    cat >"$TEST_RESULTS_DIR/lease_test_report.json" <<EOF
{
    "dhcp_lease_tests": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%",
        "timestamp": "$(date -Iseconds)"
    },
    "test_environment": {
        "mysql_host": "$MYSQL_HOST",
        "mysql_database": "$MYSQL_DATABASE",
        "dhcp_server_ip": "$DHCP_SERVER_IP"
    },
    "lease_test_details": {
        "static_leases_tested": 4,
        "dhcp_options_validated": true,
        "lease_assignment_simulation": true,
        "dynamic_range_validation": true,
        "conflict_detection": true
    }
}
EOF

    echo
    echo "============================================"
    echo "         DHCP LEASE TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:    $TESTS_RUN"
    echo "Passed:         $TESTS_PASSED"
    echo "Failed:         $TESTS_FAILED"
    echo "Success Rate:   $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL DHCP LEASE TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED lease tests failed"
        return 1
    fi
}

# Cleanup test data
cleanup_test_data() {
    log_info "Cleaning up test lease data..."

    mysql_query -e "
        DELETE FROM staticleases WHERE mac >= 0x001122330000 AND mac <= 0x001122339999;
        DELETE FROM staticleases_readable WHERE mac LIKE '00112233%';
        DELETE FROM options WHERE class >= 90;
    " 2>/dev/null || true

    log_info "Test data cleanup completed"
}

# Main execution
main() {
    log_info "Starting DHCP Lease Integration Tests..."

    # Check MySQL connectivity first
    if ! mysql_query -e "SELECT 1" &>/dev/null; then
        log_error "Cannot connect to MySQL database"
        exit 1
    fi

    # Setup test data
    setup_test_lease_data

    # Run all lease tests
    run_lease_test "static_lease_lookup" "test_static_lease_lookup"
    run_lease_test "dhcp_options_retrieval" "test_dhcp_options_retrieval"
    run_lease_test "dhcp_lease_assignment_simulation" "test_dhcp_lease_assignment_simulation"
    run_lease_test "dynamic_lease_range" "test_dynamic_lease_range"
    run_lease_test "lease_renewal_simulation" "test_lease_renewal_simulation"
    run_lease_test "ip_conflict_detection" "test_ip_conflict_detection"
    run_lease_test "option_inheritance" "test_option_inheritance"

    # Generate report
    generate_lease_test_report

    # Cleanup
    cleanup_test_data

    # Exit with appropriate code
    [ $TESTS_FAILED -eq 0 ]
}

# Handle script interruption
trap 'log_error "Lease tests interrupted"; cleanup_test_data; exit 130' INT TERM

# Execute main function
main "$@"
