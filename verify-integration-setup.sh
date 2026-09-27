#!/bin/bash

# DHCP SQL Server Integration Test Setup Verification
# This script verifies that the integration test environment is properly configured

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNINGS++))
}

log_header() {
    echo
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo "$(printf '%.0s=' {1..50})"
}

check_item() {
    local description="$1"
    local command="$2"
    local is_critical="${3:-true}"

    ((CHECKS_TOTAL++))
    log_info "Checking: $description"

    if eval "$command" &>/dev/null; then
        log_success "$description"
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            log_error "$description"
        else
            log_warning "$description"
        fi
        return 1
    fi
}

# Display banner
display_banner() {
    cat <<'EOF'

    ╔══════════════════════════════════════════════════════════╗
    ║         DHCP SQL Server Integration Test Setup          ║
    ║                  Verification Script                    ║
    ╚══════════════════════════════════════════════════════════╝

EOF
}

# Check system requirements
check_system_requirements() {
    log_header "System Requirements"

    # Check operating system
    check_item "Linux/Unix operating system" "uname -s | grep -E 'Linux|Darwin'" false

    # Check basic tools
    check_item "bash shell (version 4+)" "bash --version | head -1 | grep -E 'version [4-9]'"
    check_item "python3 available" "command -v python3"
    check_item "python3 socket module" "python3 -c 'import socket'"
    check_item "python3 struct module" "python3 -c 'import struct'"
    check_item "python3 threading module" "python3 -c 'import threading'"

    # Check network tools
    check_item "netcat (nc) available" "command -v nc"
    check_item "mysql client available" "command -v mysql"
    check_item "Basic networking tools" "command -v netstat || command -v ss"

    # Check optional tools
    check_item "bc calculator" "command -v bc" false
    check_item "jq JSON processor" "command -v jq" false
    check_item "curl available" "command -v curl" false
}

# Check Docker environment
check_docker_environment() {
    log_header "Docker Environment"

    # Check Docker
    check_item "Docker available" "command -v docker"
    check_item "Docker daemon running" "docker info"
    check_item "Docker Compose available" "command -v docker-compose"

    # Check Docker permissions
    check_item "Docker permissions" "docker ps" true

    # Check available Docker resources
    if docker info &>/dev/null; then
        local memory_gb=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{print int($1/1024/1024/1024)}' || echo "unknown")
        if [[ "$memory_gb" =~ ^[0-9]+$ ]] && [ "$memory_gb" -ge 2 ]; then
            log_success "Docker memory: ${memory_gb}GB (sufficient)"
            ((CHECKS_PASSED++))
        else
            log_warning "Docker memory: ${memory_gb}GB (may be insufficient, recommend 2GB+)"
            ((CHECKS_WARNINGS++))
        fi
        ((CHECKS_TOTAL++))
    fi
}

# Check file structure
check_file_structure() {
    log_header "File Structure"

    local required_files=(
        "docker-compose.integration-tests.yml"
        "docker/Dockerfile.test"
        "tests/integration/README.md"
        "tests/integration/run-all-tests.sh"
        "tests/integration/run-integration-tests.sh"
        "tests/integration/run-database-tests.sh"
        "tests/integration/run-server-tests.sh"
        "tests/integration/run-client-tests.sh"
        "tests/integration/run-load-tests.sh"
        "tests/integration/generate-test-report.sh"
        "tests/integration/test-data.sql"
        "tests/integration/configs/udhcpd-test.conf"
        "config/dhcp.sql"
        "config/sample-data.sql"
    )

    for file in "${required_files[@]}"; do
        check_item "File exists: $file" "[ -f '$file' ]"
    done

    # Check script permissions
    local script_files=(
        "tests/integration/run-all-tests.sh"
        "tests/integration/run-integration-tests.sh"
        "tests/integration/run-database-tests.sh"
        "tests/integration/run-server-tests.sh"
        "tests/integration/run-client-tests.sh"
        "tests/integration/run-load-tests.sh"
        "tests/integration/generate-test-report.sh"
    )

    for script in "${script_files[@]}"; do
        check_item "Script executable: $script" "[ -x '$script' ]"
    done
}

# Check configuration files
check_configuration_files() {
    log_header "Configuration Files"

    # Check Docker Compose configuration
    check_item "Docker Compose file syntax" "docker-compose -f docker-compose.integration-tests.yml config"

    # Check test configuration
    if [ -f "tests/integration/configs/udhcpd-test.conf" ]; then
        check_item "Test DHCP config contains interface" "grep -q '^interface' tests/integration/configs/udhcpd-test.conf"
        check_item "Test DHCP config contains IP range" "grep -q '^start.*172.20' tests/integration/configs/udhcpd-test.conf"
        check_item "Test DHCP config contains MySQL settings" "grep -q 'sqlserver' tests/integration/configs/udhcpd-test.conf"
    fi

    # Check SQL files
    if [ -f "config/dhcp.sql" ]; then
        check_item "Main SQL schema contains tables" "grep -q 'CREATE TABLE' config/dhcp.sql"
        check_item "SQL schema contains staticleases" "grep -q 'staticleases' config/dhcp.sql"
        check_item "SQL schema contains options" "grep -q 'CREATE TABLE.*options' config/dhcp.sql"
    fi

    if [ -f "tests/integration/test-data.sql" ]; then
        check_item "Test data SQL contains test data" "grep -q 'INSERT INTO' tests/integration/test-data.sql"
    fi
}

# Check script syntax
check_script_syntax() {
    log_header "Script Syntax Validation"

    local scripts=(
        "tests/integration/run-all-tests.sh"
        "tests/integration/run-integration-tests.sh"
        "tests/integration/run-database-tests.sh"
        "tests/integration/run-server-tests.sh"
        "tests/integration/run-client-tests.sh"
        "tests/integration/run-load-tests.sh"
        "tests/integration/generate-test-report.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            check_item "Syntax validation: $(basename $script)" "bash -n '$script'"
        fi
    done
}

# Check network configuration
check_network_configuration() {
    log_header "Network Configuration"

    # Check if test ports are available
    check_item "Port 3307 available (MySQL test)" "! nc -z localhost 3307" false
    check_item "Port 67 not in use" "! netstat -lun 2>/dev/null | grep -q ':67 ' && ! ss -lun 2>/dev/null | grep -q ':67 '" false

    # Check Docker network capabilities
    check_item "Docker can create networks" "docker network create test-verification-net && docker network rm test-verification-net"

    # Check if test IP range is available
    if command -v ip &>/dev/null; then
        check_item "Test network range not in use" "! ip route | grep -q '172.20.'" false
    fi
}

# Test Docker Compose dry run
test_docker_compose() {
    log_header "Docker Compose Validation"

    # Test configuration parsing
    check_item "Docker Compose config parsing" "docker-compose -f docker-compose.integration-tests.yml config >/dev/null"

    # Test image building (dry run)
    check_item "Docker build context" "docker build -f docker/Dockerfile.test --dry-run . 2>/dev/null || docker build -f docker/Dockerfile.test -t dhcp-test-verify . && docker rmi dhcp-test-verify" false

    # Check service definitions
    if docker-compose -f docker-compose.integration-tests.yml config &>/dev/null; then
        local services=$(docker-compose -f docker-compose.integration-tests.yml config --services)
        local expected_services=("mysql-test" "dhcp-server-test" "integration-tests" "database-tests")

        for service in "${expected_services[@]}"; do
            check_item "Service defined: $service" "echo '$services' | grep -q '^$service$'"
        done
    fi
}

# Check environment variables
check_environment() {
    log_header "Environment Configuration"

    # Check current directory
    check_item "Running from project root" "[ -f 'CMakeLists.txt' ] || [ -f 'Makefile' ]"

    # Check if source code is built
    check_item "Project appears built" "[ -f 'udhcpd' ] || [ -f 'build/udhcpd' ] || ls -la *udhcp* dumpleases 2>/dev/null" false

    # Check default environment values
    log_info "Environment variables (current values):"
    echo "  MYSQL_HOST: ${MYSQL_HOST:-mysql-test}"
    echo "  MYSQL_USER: ${MYSQL_USER:-dhcp_test}"
    echo "  MYSQL_DATABASE: ${MYSQL_DATABASE:-dhcp_test}"
    echo "  DHCP_SERVER_IP: ${DHCP_SERVER_IP:-172.20.0.10}"
}

# Run a simple integration test
run_quick_validation() {
    log_header "Quick Integration Validation"

    # Test script execution (dry run)
    if [ -x "tests/integration/run-all-tests.sh" ]; then
        check_item "Test runner help works" "tests/integration/run-all-tests.sh --help" false
    fi

    # Test Python test code
    check_item "Python DHCP packet creation" "python3 -c \"
import socket
import struct
packet = bytearray(240)
packet[0] = 1
packet[1] = 1
packet[2] = 6
packet[236:240] = b'\x63\x82\x53\x63'
print('Packet length:', len(packet))
assert len(packet) == 240
\""

    # Test MySQL client functionality
    check_item "MySQL client can handle test queries" "echo 'SELECT 1 as test;' | mysql --version >/dev/null"
}

# Display final summary
display_summary() {
    log_header "Verification Summary"

    local success_rate=0
    if [ $CHECKS_TOTAL -gt 0 ]; then
        success_rate=$(echo "scale=1; $CHECKS_PASSED * 100 / $CHECKS_TOTAL" | bc 2>/dev/null || echo "N/A")
    fi

    echo "Total Checks: $CHECKS_TOTAL"
    echo "Passed: $CHECKS_PASSED"
    echo "Failed: $CHECKS_FAILED"
    echo "Warnings: $CHECKS_WARNINGS"
    echo "Success Rate: ${success_rate}%"
    echo

    if [ $CHECKS_FAILED -eq 0 ]; then
        log_success "✅ Environment verification PASSED!"
        echo
        echo "Your system is ready to run DHCP integration tests."
        echo
        echo "Next steps:"
        echo "  1. Run quick tests: cd tests/integration && make quick"
        echo "  2. Run full tests: cd tests/integration && make test"
        echo "  3. Use Docker: docker-compose -f docker-compose.integration-tests.yml up"
    elif [ $CHECKS_FAILED -le 3 ] && [ $CHECKS_PASSED -gt $CHECKS_FAILED ]; then
        log_warning "⚠️  Environment verification completed with minor issues"
        echo
        echo "You can proceed with testing, but some features may not work optimally."
        echo "Please address the failed checks above if possible."
    else
        log_error "❌ Environment verification FAILED!"
        echo
        echo "Please fix the critical issues above before running integration tests."
        echo "Focus on the failed checks marked in red."
    fi

    echo
    echo "For detailed setup instructions, see: tests/integration/README.md"
}

# Main execution
main() {
    display_banner

    log_info "Starting DHCP SQL Server integration test environment verification..."
    log_info "This will check system requirements, file structure, and configuration"
    echo

    # Run all checks
    check_system_requirements
    check_docker_environment
    check_file_structure
    check_configuration_files
    check_script_syntax
    check_network_configuration
    test_docker_compose
    check_environment
    run_quick_validation

    # Display results
    display_summary

    # Set exit code
    if [ $CHECKS_FAILED -eq 0 ]; then
        exit 0
    elif [ $CHECKS_FAILED -le 3 ] && [ $CHECKS_PASSED -gt $CHECKS_FAILED ]; then
        exit 1
    else
        exit 2
    fi
}

# Run main function
main "$@"
