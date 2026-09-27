#!/bin/bash

# DHCP SQL Server - Master Integration Test Runner
# This script orchestrates the execution of all integration tests

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

# Test execution options
PARALLEL_EXECUTION="${PARALLEL_EXECUTION:-false}"
INCLUDE_LOAD_TESTS="${INCLUDE_LOAD_TESTS:-true}"
INCLUDE_NETWORK_TESTS="${INCLUDE_NETWORK_TESTS:-false}"
GENERATE_REPORTS="${GENERATE_REPORTS:-true}"
CLEANUP_AFTER_TESTS="${CLEANUP_AFTER_TESTS:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global counters
TOTAL_TEST_SUITES=0
PASSED_TEST_SUITES=0
FAILED_TEST_SUITES=0
START_TIME=$(date +%s)

# Test execution log
EXECUTION_LOG="$TEST_RESULTS_DIR/test_execution.log"

# Helper functions
log_info() {
    echo -e "${BLUE}[MASTER]${NC} $1" | tee -a "$EXECUTION_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$EXECUTION_LOG"
}

log_error() {
    echo -e "${RED}[FAILED]${NC} $1" | tee -a "$EXECUTION_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$EXECUTION_LOG"
}

log_header() {
    echo | tee -a "$EXECUTION_LOG"
    echo -e "${CYAN}${BOLD}$1${NC}" | tee -a "$EXECUTION_LOG"
    echo "$(printf '%.0s=' {1..60})" | tee -a "$EXECUTION_LOG"
}

# Display usage information
show_usage() {
    cat <<EOF
DHCP SQL Server Integration Test Suite
=====================================

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -p, --parallel          Run tests in parallel where possible
    -l, --load-tests        Include load testing (default: true)
    -n, --network-tests     Include network simulation tests (default: false)
    --no-reports            Skip report generation
    --no-cleanup            Skip cleanup after tests
    -v, --verbose           Verbose output
    --quick                 Run only essential tests (skip load and network tests)

ENVIRONMENT VARIABLES:
    MYSQL_HOST              MySQL server hostname (default: mysql-test)
    MYSQL_USER              MySQL username (default: dhcp_test)
    MYSQL_PASSWORD          MySQL password (default: dhcp_test)
    MYSQL_DATABASE          MySQL database name (default: dhcp_test)
    DHCP_SERVER_IP          DHCP server IP address (default: 172.20.0.10)
    PARALLEL_EXECUTION      Enable parallel execution (default: false)
    INCLUDE_LOAD_TESTS      Include load tests (default: true)
    INCLUDE_NETWORK_TESTS   Include network tests (default: false)

EXAMPLES:
    # Run all tests with default settings
    $0

    # Run tests in parallel with load testing
    $0 --parallel --load-tests

    # Quick test run (essential tests only)
    $0 --quick

    # Full test suite including network tests
    $0 --parallel --load-tests --network-tests

EXIT CODES:
    0   All tests passed
    1   Some tests failed
    2   Test setup/environment error
    130 Tests interrupted by user
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -h | --help)
            show_usage
            exit 0
            ;;
        -p | --parallel)
            PARALLEL_EXECUTION="true"
            shift
            ;;
        -l | --load-tests)
            INCLUDE_LOAD_TESTS="true"
            shift
            ;;
        -n | --network-tests)
            INCLUDE_NETWORK_TESTS="true"
            shift
            ;;
        --no-reports)
            GENERATE_REPORTS="false"
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER_TESTS="false"
            shift
            ;;
        -v | --verbose)
            set -x
            shift
            ;;
        --quick)
            INCLUDE_LOAD_TESTS="false"
            INCLUDE_NETWORK_TESTS="false"
            log_info "Quick test mode: skipping load and network tests"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 2
            ;;
        esac
    done
}

# Setup test environment
setup_test_environment() {
    log_header "Setting Up Test Environment"

    # Create necessary directories
    mkdir -p "$TEST_RESULTS_DIR" "$LOG_DIR"

    # Create execution log
    cat >"$EXECUTION_LOG" <<EOF
DHCP SQL Server Integration Test Execution Log
==============================================
Started: $(date)
Configuration:
  - MySQL Host: $MYSQL_HOST
  - DHCP Server: $DHCP_SERVER_IP
  - Parallel Execution: $PARALLEL_EXECUTION
  - Include Load Tests: $INCLUDE_LOAD_TESTS
  - Include Network Tests: $INCLUDE_NETWORK_TESTS
  - Generate Reports: $GENERATE_REPORTS

EOF

    # Check required tools
    local required_tools=("mysql" "nc" "python3")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please ensure all required tools are installed"
        exit 2
    fi

    # Verify Python modules
    if ! python3 -c "import socket, struct, time, threading" &>/dev/null; then
        log_error "Required Python modules not available"
        exit 2
    fi

    # Check for bc calculator if load tests are enabled
    if [ "$INCLUDE_LOAD_TESTS" = "true" ] && ! command -v bc &>/dev/null; then
        log_warning "bc calculator not available - some metrics may be limited"
    fi

    log_success "Test environment setup completed"
}

# Wait for dependencies to be ready
wait_for_dependencies() {
    log_header "Waiting for Dependencies"

    local max_wait=120
    local wait_count=0

    # Wait for MySQL
    log_info "Waiting for MySQL database..."
    while [ $wait_count -lt $max_wait ]; do
        if mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT 1" &>/dev/null; then
            log_success "MySQL database is ready"
            break
        fi

        wait_count=$((wait_count + 5))
        if [ $wait_count -ge $max_wait ]; then
            log_error "MySQL database not ready after ${max_wait}s"
            exit 2
        fi

        sleep 5
    done

    # Wait for DHCP server
    log_info "Waiting for DHCP server..."
    wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        if nc -u -z "$DHCP_SERVER_IP" 67 2>/dev/null; then
            log_success "DHCP server is ready"
            break
        fi

        wait_count=$((wait_count + 5))
        if [ $wait_count -ge $max_wait ]; then
            log_error "DHCP server not ready after ${max_wait}s"
            exit 2
        fi

        sleep 5
    done

    log_success "All dependencies are ready"
}

# Execute a test suite
run_test_suite() {
    local suite_name="$1"
    local script_path="$2"
    local description="$3"
    local timeout="${4:-300}"

    log_header "Running $suite_name Tests"
    log_info "$description"

    ((TOTAL_TEST_SUITES++))

    local start_time=$(date +%s)

    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        if timeout "$timeout" "$script_path" 2>&1 | tee "$TEST_RESULTS_DIR/${suite_name}_execution.log"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_success "$suite_name tests completed successfully in ${duration}s"
            ((PASSED_TEST_SUITES++))
            return 0
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_error "$suite_name tests failed after ${duration}s"
            ((FAILED_TEST_SUITES++))
            return 1
        fi
    else
        log_error "$suite_name test script not found or not executable: $script_path"
        ((FAILED_TEST_SUITES++))
        return 1
    fi
}

# Run core test suites
run_core_tests() {
    log_header "Executing Core Integration Tests"

    local core_tests=(
        "database:/app/tests/run-database-tests.sh:Database connectivity and operations:180"
        "server:/app/tests/run-server-tests.sh:DHCP server functionality:240"
        "client:/app/tests/run-client-tests.sh:DHCP client functionality:180"
        "integration:/app/tests/run-integration-tests.sh:End-to-end integration:300"
    )

    if [ "$PARALLEL_EXECUTION" = "true" ]; then
        log_info "Running core tests in parallel..."

        local pids=()
        local test_names=()

        for test_spec in "${core_tests[@]}"; do
            IFS=':' read -r name script desc timeout <<<"$test_spec"
            test_names+=("$name")

            (run_test_suite "$name" "$script" "$desc" "$timeout") &
            pids+=($!)
        done

        # Wait for all parallel tests to complete
        local failed_parallel=0
        for i in "${!pids[@]}"; do
            if wait "${pids[$i]}"; then
                log_success "${test_names[$i]} completed successfully (parallel)"
            else
                log_error "${test_names[$i]} failed (parallel)"
                ((failed_parallel++))
            fi
        done

        if [ $failed_parallel -gt 0 ]; then
            log_error "$failed_parallel core test suite(s) failed in parallel execution"
        fi
    else
        log_info "Running core tests sequentially..."

        for test_spec in "${core_tests[@]}"; do
            IFS=':' read -r name script desc timeout <<<"$test_spec"
            run_test_suite "$name" "$script" "$desc" "$timeout"
        done
    fi
}

# Run load tests
run_load_tests() {
    if [ "$INCLUDE_LOAD_TESTS" = "true" ]; then
        log_header "Executing Load Tests"
        run_test_suite "load" "/app/tests/run-load-tests.sh" "Performance and load testing" "600"
    else
        log_info "Load tests skipped (disabled)"
    fi
}

# Run network simulation tests
run_network_tests() {
    if [ "$INCLUDE_NETWORK_TESTS" = "true" ]; then
        log_header "Executing Network Simulation Tests"
        run_test_suite "network" "/app/tests/run-network-tests.sh" "Advanced network scenario testing" "300"
    else
        log_info "Network simulation tests skipped (disabled)"
    fi
}

# Generate comprehensive test report
generate_test_reports() {
    if [ "$GENERATE_REPORTS" = "true" ]; then
        log_header "Generating Test Reports"

        if [ -f "/app/tests/generate-test-report.sh" ] && [ -x "/app/tests/generate-test-report.sh" ]; then
            if /app/tests/generate-test-report.sh; then
                log_success "Test reports generated successfully"
            else
                log_warning "Test report generation had issues"
            fi
        else
            log_warning "Test report generator not found - creating basic summary"

            cat >"$TEST_RESULTS_DIR/basic_summary.txt" <<EOF
Basic Test Summary
==================
Generated: $(date)

Test Suite Results:
- Total Suites: $TOTAL_TEST_SUITES
- Passed: $PASSED_TEST_SUITES
- Failed: $FAILED_TEST_SUITES

Overall Status: $([ $FAILED_TEST_SUITES -eq 0 ] && echo "PASSED" || echo "FAILED")

For detailed results, check individual test logs in:
$TEST_RESULTS_DIR/
EOF
        fi
    else
        log_info "Report generation skipped (disabled)"
    fi
}

# Cleanup test environment
cleanup_test_environment() {
    if [ "$CLEANUP_AFTER_TESTS" = "true" ]; then
        log_header "Cleaning Up Test Environment"

        # Clean up temporary files
        find "$TEST_RESULTS_DIR" -name "*.tmp" -delete 2>/dev/null || true

        # Compress large log files
        find "$LOG_DIR" -name "*.log" -size +10M -exec gzip {} \; 2>/dev/null || true

        # Remove old test results (keep last 5 runs)
        find "$TEST_RESULTS_DIR" -name "*_execution.log" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true

        log_success "Test environment cleanup completed"
    else
        log_info "Cleanup skipped (disabled)"
    fi
}

# Display final summary
display_final_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local hours=$((total_duration / 3600))
    local minutes=$(((total_duration % 3600) / 60))
    local seconds=$((total_duration % 60))

    echo | tee -a "$EXECUTION_LOG"
    log_header "FINAL TEST EXECUTION SUMMARY"

    cat | tee -a "$EXECUTION_LOG" <<EOF

Execution Details:
- Start Time: $(date -d "@$START_TIME")
- End Time: $(date)
- Total Duration: ${hours}h ${minutes}m ${seconds}s

Test Suite Results:
- Total Suites Executed: $TOTAL_TEST_SUITES
- Passed: $PASSED_TEST_SUITES
- Failed: $FAILED_TEST_SUITES
- Success Rate: $(echo "scale=2; $PASSED_TEST_SUITES * 100 / $TOTAL_TEST_SUITES" | bc 2>/dev/null || echo "N/A")%

Configuration Used:
- Parallel Execution: $PARALLEL_EXECUTION
- Load Tests Included: $INCLUDE_LOAD_TESTS
- Network Tests Included: $INCLUDE_NETWORK_TESTS
- Reports Generated: $GENERATE_REPORTS

Result Files Location: $TEST_RESULTS_DIR

EOF

    if [ $FAILED_TEST_SUITES -eq 0 ]; then
        echo -e "${GREEN}${BOLD}🎉 ALL TEST SUITES PASSED! 🎉${NC}" | tee -a "$EXECUTION_LOG"
        echo "The DHCP SQL Server has successfully passed all integration tests." | tee -a "$EXECUTION_LOG"
        echo "The system is ready for production deployment." | tee -a "$EXECUTION_LOG"
    else
        echo -e "${RED}${BOLD}❌ SOME TEST SUITES FAILED ❌${NC}" | tee -a "$EXECUTION_LOG"
        echo "Failed Test Suites: $FAILED_TEST_SUITES out of $TOTAL_TEST_SUITES" | tee -a "$EXECUTION_LOG"
        echo "Please review the detailed logs and reports for more information." | tee -a "$EXECUTION_LOG"
        echo "Fix the issues before considering production deployment." | tee -a "$EXECUTION_LOG"
    fi

    echo | tee -a "$EXECUTION_LOG"
    echo "$(printf '%.0s=' {1..60})" | tee -a "$EXECUTION_LOG"
}

# Handle script interruption
handle_interrupt() {
    log_error "Test execution interrupted by user"

    # Kill any background processes
    jobs -p | xargs kill -TERM 2>/dev/null || true

    # Brief cleanup
    log_info "Performing emergency cleanup..."
    cleanup_test_environment

    display_final_summary
    exit 130
}

# Main execution function
main() {
    # Display startup banner
    cat <<'EOF'

    ╔══════════════════════════════════════════════════════════╗
    ║             DHCP SQL Server Test Suite                  ║
    ║                Integration Testing                       ║
    ╚══════════════════════════════════════════════════════════╝

EOF

    log_info "Starting DHCP SQL Server Integration Test Suite"
    log_info "Execution ID: $(date +%Y%m%d_%H%M%S)"

    # Parse arguments
    parse_arguments "$@"

    # Setup signal handlers
    trap handle_interrupt INT TERM

    # Execute test phases
    setup_test_environment
    wait_for_dependencies
    run_core_tests
    run_load_tests
    run_network_tests
    generate_test_reports
    cleanup_test_environment
    display_final_summary

    # Set exit code based on results
    if [ $FAILED_TEST_SUITES -eq 0 ]; then
        log_success "All integration tests completed successfully"
        exit 0
    else
        log_error "Some integration tests failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
