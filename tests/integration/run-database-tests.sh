#!/bin/bash

# DHCP SQL Server - Database Integration Test Runner
# This script specifically tests database operations and SQL functionality

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
export MYSQL_HOST="${MYSQL_HOST:-mysql-test}"
export MYSQL_USER="${MYSQL_USER:-dhcp_test}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-dhcp_test}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-dhcp_test}"

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
    echo -e "${BLUE}[DB-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DB-PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[DB-FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[DB-WARN]${NC} $1"
}

# MySQL helper function
mysql_query() {
    mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN "$@"
}

mysql_execute() {
    mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "$@"
}

run_db_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_info "Running database test: $test_name"

    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Test database connection and basic functionality
test_database_connection() {
    # Test basic connection
    if ! mysql_query -e "SELECT 1" &>/dev/null; then
        return 1
    fi

    # Test database selection
    if ! mysql_query -e "USE $MYSQL_DATABASE" &>/dev/null; then
        return 1
    fi

    # Test privileges
    if ! mysql_query -e "SELECT COUNT(*) FROM staticleases" &>/dev/null; then
        return 1
    fi

    return 0
}

# Test database schema integrity
test_schema_integrity() {
    local required_tables=("options" "staticleases" "staticleases_readable" "metaoptions")

    for table in "${required_tables[@]}"; do
        if ! mysql_query -e "DESCRIBE $table" &>/dev/null; then
            log_error "Table $table missing or inaccessible"
            return 1
        fi
    done

    # Test table structure
    local options_cols
    options_cols=$(mysql_query -e "SHOW COLUMNS FROM options" | wc -l)
    if [ "$options_cols" -lt 4 ]; then
        log_error "options table has insufficient columns"
        return 1
    fi

    local staticleases_cols
    staticleases_cols=$(mysql_query -e "SHOW COLUMNS FROM staticleases" | wc -l)
    if [ "$staticleases_cols" -lt 3 ]; then
        log_error "staticleases table has insufficient columns"
        return 1
    fi

    return 0
}

# Test static lease operations
test_static_lease_operations() {
    # Test INSERT operation
    local test_mac="0x999999999999"
    local test_ip="INET_ATON('172.20.99.99')"
    local test_class="99"

    # Clean up any existing test data
    mysql_execute "DELETE FROM staticleases WHERE mac = $test_mac" &>/dev/null || true

    # Test INSERT
    if ! mysql_execute "INSERT INTO staticleases (mac, ip, class) VALUES ($test_mac, $test_ip, $test_class)"; then
        log_error "Failed to insert test lease"
        return 1
    fi

    # Test SELECT
    local inserted_count
    inserted_count=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac = $test_mac")
    if [ "$inserted_count" != "1" ]; then
        log_error "Failed to retrieve inserted lease"
        return 1
    fi

    # Test UPDATE
    if ! mysql_execute "UPDATE staticleases SET class = 100 WHERE mac = $test_mac"; then
        log_error "Failed to update test lease"
        return 1
    fi

    local updated_class
    updated_class=$(mysql_query -e "SELECT class FROM staticleases WHERE mac = $test_mac")
    if [ "$updated_class" != "100" ]; then
        log_error "Failed to verify lease update"
        return 1
    fi

    # Test DELETE
    if ! mysql_execute "DELETE FROM staticleases WHERE mac = $test_mac"; then
        log_error "Failed to delete test lease"
        return 1
    fi

    local deleted_count
    deleted_count=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac = $test_mac")
    if [ "$deleted_count" != "0" ]; then
        log_error "Failed to verify lease deletion"
        return 1
    fi

    return 0
}

# Test options table operations
test_options_operations() {
    # Test INSERT operation
    local test_class="99"
    local test_code="99"
    local test_data="'TEST_DATA_VALUE'"

    # Clean up any existing test data
    mysql_execute "DELETE FROM options WHERE class = $test_class AND code = $test_code" &>/dev/null || true

    # Test INSERT
    if ! mysql_execute "INSERT INTO options (class, code, data) VALUES ($test_class, $test_code, $test_data)"; then
        log_error "Failed to insert test option"
        return 1
    fi

    # Test SELECT
    local inserted_data
    inserted_data=$(mysql_query -e "SELECT data FROM options WHERE class = $test_class AND code = $test_code")
    if [ "$inserted_data" != "TEST_DATA_VALUE" ]; then
        log_error "Failed to retrieve inserted option data"
        return 1
    fi

    # Test UPDATE
    if ! mysql_execute "UPDATE options SET data = 'UPDATED_VALUE' WHERE class = $test_class AND code = $test_code"; then
        log_error "Failed to update test option"
        return 1
    fi

    local updated_data
    updated_data=$(mysql_query -e "SELECT data FROM options WHERE class = $test_class AND code = $test_code")
    if [ "$updated_data" != "UPDATED_VALUE" ]; then
        log_error "Failed to verify option update"
        return 1
    fi

    # Test DELETE
    if ! mysql_execute "DELETE FROM options WHERE class = $test_class AND code = $test_code"; then
        log_error "Failed to delete test option"
        return 1
    fi

    return 0
}

# Test IP address functions
test_ip_address_functions() {
    # Test INET_ATON and INET_NTOA functions
    local test_ip="192.168.1.100"
    local converted_back
    converted_back=$(mysql_query -e "SELECT INET_NTOA(INET_ATON('$test_ip'))")

    if [ "$converted_back" != "$test_ip" ]; then
        log_error "IP address conversion failed: expected $test_ip, got $converted_back"
        return 1
    fi

    # Test with edge cases
    local edge_cases=("0.0.0.0" "255.255.255.255" "127.0.0.1" "172.16.0.1")
    for ip in "${edge_cases[@]}"; do
        converted_back=$(mysql_query -e "SELECT INET_NTOA(INET_ATON('$ip'))")
        if [ "$converted_back" != "$ip" ]; then
            log_error "IP address conversion failed for $ip: got $converted_back"
            return 1
        fi
    done

    return 0
}

# Test data constraints and validation
test_data_constraints() {
    # Test unique constraints on staticleases
    local test_mac1="0x888888888888"
    local test_mac2="0x888888888889"
    local test_ip="INET_ATON('172.20.99.88')"

    # Clean up
    mysql_execute "DELETE FROM staticleases WHERE mac IN ($test_mac1, $test_mac2)" &>/dev/null || true

    # Insert first record
    if ! mysql_execute "INSERT INTO staticleases (mac, ip, class) VALUES ($test_mac1, $test_ip, 1)"; then
        log_error "Failed to insert first test record"
        return 1
    fi

    # Try to insert duplicate IP (should fail if constraints exist)
    if mysql_execute "INSERT INTO staticleases (mac, ip, class) VALUES ($test_mac2, $test_ip, 1)" &>/dev/null; then
        log_warning "Database allows duplicate IP addresses (constraint may be missing)"
        # Clean up the duplicate
        mysql_execute "DELETE FROM staticleases WHERE mac = $test_mac2" &>/dev/null || true
    fi

    # Clean up
    mysql_execute "DELETE FROM staticleases WHERE mac = $test_mac1" &>/dev/null || true

    return 0
}

# Test database performance
test_database_performance() {
    local start_time=$(date +%s%N)

    # Run multiple queries to test performance
    for i in {1..100}; do
        mysql_query -e "SELECT COUNT(*) FROM staticleases" &>/dev/null
        mysql_query -e "SELECT COUNT(*) FROM options" &>/dev/null
    done

    local end_time=$(date +%s%N)
    local duration_ms=$(((end_time - start_time) / 1000000))

    log_info "Database performance test: 200 queries in ${duration_ms}ms"

    if [ "$duration_ms" -gt 10000 ]; then
        log_warning "Database performance is slow (${duration_ms}ms for 200 queries)"
        return 1
    fi

    return 0
}

# Test stored procedures and views
test_stored_procedures() {
    # Test validation procedure
    if ! mysql_execute "CALL validate_test_setup()"; then
        log_error "validate_test_setup procedure failed"
        return 1
    fi

    # Test cleanup procedure
    if ! mysql_execute "CALL cleanup_test_leases()"; then
        log_warning "cleanup_test_leases procedure failed"
    fi

    # Test views
    if ! mysql_query -e "SELECT * FROM test_lease_summary LIMIT 1" &>/dev/null; then
        log_error "test_lease_summary view not accessible"
        return 1
    fi

    if ! mysql_query -e "SELECT * FROM test_options_summary LIMIT 1" &>/dev/null; then
        log_error "test_options_summary view not accessible"
        return 1
    fi

    return 0
}

# Test data integrity and relationships
test_data_integrity() {
    # Check for orphaned options (options with classes that don't exist in static leases)
    local orphaned_count
    orphaned_count=$(mysql_query -e "
        SELECT COUNT(DISTINCT o.class)
        FROM options o
        LEFT JOIN staticleases s ON o.class = s.class
        WHERE o.class > 0 AND s.class IS NULL
    ")

    if [ "$orphaned_count" -gt 5 ]; then
        log_warning "Found $orphaned_count orphaned option classes"
    fi

    # Check for invalid IP addresses (NULL or 0)
    local invalid_ips
    invalid_ips=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE ip IS NULL OR ip = 0")

    if [ "$invalid_ips" -gt 0 ]; then
        log_error "Found $invalid_ips invalid IP addresses in staticleases"
        return 1
    fi

    # Check for invalid MAC addresses (NULL or 0)
    local invalid_macs
    invalid_macs=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac IS NULL OR mac = 0")

    if [ "$invalid_macs" -gt 0 ]; then
        log_error "Found $invalid_macs invalid MAC addresses in staticleases"
        return 1
    fi

    return 0
}

# Test transaction handling
test_transactions() {
    # Test transaction rollback
    mysql_execute "START TRANSACTION"
    mysql_execute "INSERT INTO staticleases (mac, ip, class) VALUES (0x777777777777, INET_ATON('172.20.99.77'), 77)"

    # Check if record exists
    local before_rollback
    before_rollback=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac = 0x777777777777")

    mysql_execute "ROLLBACK"

    # Check if record was rolled back
    local after_rollback
    after_rollback=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac = 0x777777777777")

    if [ "$before_rollback" != "1" ] || [ "$after_rollback" != "0" ]; then
        log_error "Transaction rollback test failed"
        return 1
    fi

    # Test transaction commit
    mysql_execute "START TRANSACTION"
    mysql_execute "INSERT INTO staticleases (mac, ip, class) VALUES (0x666666666666, INET_ATON('172.20.99.66'), 66)"
    mysql_execute "COMMIT"

    local after_commit
    after_commit=$(mysql_query -e "SELECT COUNT(*) FROM staticleases WHERE mac = 0x666666666666")

    if [ "$after_commit" != "1" ]; then
        log_error "Transaction commit test failed"
        return 1
    fi

    # Clean up
    mysql_execute "DELETE FROM staticleases WHERE mac = 0x666666666666"

    return 0
}

# Generate database test report
generate_db_test_report() {
    mkdir -p "$TEST_RESULTS_DIR"

    cat >"$TEST_RESULTS_DIR/database_test_report.json" <<EOF
{
    "database_tests": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%",
        "timestamp": "$(date -Iseconds)"
    },
    "database_info": {
        "host": "$MYSQL_HOST",
        "database": "$MYSQL_DATABASE",
        "user": "$MYSQL_USER"
    }
}
EOF

    echo
    echo "============================================"
    echo "         DATABASE TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:    $TESTS_RUN"
    echo "Passed:         $TESTS_PASSED"
    echo "Failed:         $TESTS_FAILED"
    echo "Success Rate:   $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL DATABASE TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED database tests failed"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting DHCP Database Integration Tests..."

    # Wait for MySQL to be ready
    for i in {1..30}; do
        if mysql_query -e "SELECT 1" &>/dev/null; then
            log_success "Database connection established"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "Database connection timeout"
            exit 1
        fi
        sleep 2
    done

    # Run all database tests
    run_db_test "database_connection" "test_database_connection"
    run_db_test "schema_integrity" "test_schema_integrity"
    run_db_test "static_lease_operations" "test_static_lease_operations"
    run_db_test "options_operations" "test_options_operations"
    run_db_test "ip_address_functions" "test_ip_address_functions"
    run_db_test "data_constraints" "test_data_constraints"
    run_db_test "database_performance" "test_database_performance"
    run_db_test "stored_procedures" "test_stored_procedures"
    run_db_test "data_integrity" "test_data_integrity"
    run_db_test "transactions" "test_transactions"

    # Generate report
    generate_db_test_report
}

# Handle script interruption
trap 'log_error "Database tests interrupted"; exit 130' INT TERM

# Execute main function
main "$@"
