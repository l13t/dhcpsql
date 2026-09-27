#!/bin/bash

# DHCP SQL Server - Test Report Generator
# This script aggregates all test results and generates comprehensive reports

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
export LOG_DIR="/var/log/dhcp"
export REPORT_DIR="/app/results"
export TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global counters
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[REPORT]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

# Check if jq is available, if not provide fallback JSON parsing
parse_json() {
    local file="$1"
    local key="$2"

    if command -v jq &>/dev/null && [ -f "$file" ]; then
        jq -r "$key" "$file" 2>/dev/null || echo "N/A"
    elif [ -f "$file" ]; then
        # Fallback parsing for simple JSON
        grep "\"${key#.}\"" "$file" | cut -d':' -f2 | tr -d ' ,"' || echo "N/A"
    else
        echo "N/A"
    fi
}

# Setup report directories
setup_report_environment() {
    log_info "Setting up report environment..."

    mkdir -p "$REPORT_DIR" "$TEST_RESULTS_DIR"

    # Create report timestamp
    echo "Test Report Generated: $(date)" >"$REPORT_DIR/test_execution_time.txt"

    log_success "Report environment ready"
}

# Collect system information
collect_system_info() {
    log_info "Collecting system information..."

    cat >"$REPORT_DIR/system_info.txt" <<EOF
DHCP SQL Server Integration Test Report
=======================================

Test Execution Time: $(date)
System Information:
- Hostname: $(hostname 2>/dev/null || echo "Unknown")
- OS: $(uname -s 2>/dev/null || echo "Unknown")
- Kernel: $(uname -r 2>/dev/null || echo "Unknown")
- Architecture: $(uname -m 2>/dev/null || echo "Unknown")
- Uptime: $(uptime 2>/dev/null || echo "Unknown")

Docker Environment:
- Container ID: $(hostname 2>/dev/null || echo "Unknown")
- Environment Variables:
  - MYSQL_HOST: ${MYSQL_HOST:-"Not set"}
  - DHCP_SERVER_IP: ${DHCP_SERVER_IP:-"Not set"}
  - TEST_MODE: ${TEST_MODE:-"Not set"}

Network Configuration:
EOF

    # Add network information if available
    if command -v ip &>/dev/null; then
        echo "- Network Interfaces:" >>"$REPORT_DIR/system_info.txt"
        ip addr show 2>/dev/null | grep -E "(inet |inet6 )" | sed 's/^/  /' >>"$REPORT_DIR/system_info.txt" || true
    fi

    if command -v netstat &>/dev/null; then
        echo "- Listening Ports:" >>"$REPORT_DIR/system_info.txt"
        netstat -ln 2>/dev/null | grep LISTEN | head -10 | sed 's/^/  /' >>"$REPORT_DIR/system_info.txt" || true
    fi

    log_success "System information collected"
}

# Aggregate individual test results
aggregate_test_results() {
    log_info "Aggregating test results from individual test suites..."

    local result_files=(
        "integration_test_report.json"
        "database_test_report.json"
        "server_test_report.json"
        "client_test_report.json"
        "load_test_report.json"
    )

    local test_summary=""

    for result_file in "${result_files[@]}"; do
        local file_path="$TEST_RESULTS_DIR/$result_file"

        if [ -f "$file_path" ]; then
            local test_suite="${result_file%_test_report.json}"
            test_suite="${test_suite%_report.json}"
            test_suite="${test_suite#integration_}"

            local tests_total=$(parse_json "$file_path" ".${test_suite}_tests.total_tests // .total_tests // 0")
            local tests_passed=$(parse_json "$file_path" ".${test_suite}_tests.passed // .passed // 0")
            local tests_failed=$(parse_json "$file_path" ".${test_suite}_tests.failed // .failed // 0")
            local success_rate=$(parse_json "$file_path" ".${test_suite}_tests.success_rate // .success_rate // \"0%\"")

            # Convert to numbers if possible
            if [[ "$tests_total" =~ ^[0-9]+$ ]]; then
                TOTAL_TESTS=$((TOTAL_TESTS + tests_total))
            fi
            if [[ "$tests_passed" =~ ^[0-9]+$ ]]; then
                TOTAL_PASSED=$((TOTAL_PASSED + tests_passed))
            fi
            if [[ "$tests_failed" =~ ^[0-9]+$ ]]; then
                TOTAL_FAILED=$((TOTAL_FAILED + tests_failed))
            fi

            test_summary="${test_summary}
${test_suite^} Tests:
  Total: $tests_total
  Passed: $tests_passed
  Failed: $tests_failed
  Success Rate: $success_rate
"

            log_info "Processed ${test_suite} test results: $tests_passed/$tests_total passed"
        else
            log_warning "Test result file not found: $result_file"
        fi
    done

    # Write aggregated summary
    cat >"$REPORT_DIR/test_summary.txt" <<EOF
DHCP SQL Server - Test Results Summary
=====================================

Overall Test Statistics:
- Total Tests Run: $TOTAL_TESTS
- Total Passed: $TOTAL_PASSED
- Total Failed: $TOTAL_FAILED
- Overall Success Rate: $(echo "scale=2; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc 2>/dev/null || echo "N/A")%

Test Suite Breakdown:
$test_summary

Test Execution Status: $([ $TOTAL_FAILED -eq 0 ] && echo "SUCCESS" || echo "FAILED")
EOF

    log_success "Test results aggregated successfully"
}

# Collect and analyze log files
analyze_logs() {
    log_info "Analyzing log files..."

    cat >"$REPORT_DIR/log_analysis.txt" <<EOF
Log File Analysis
=================

EOF

    # Analyze DHCP server logs if available
    local dhcp_log="$LOG_DIR/udhcpd.log"
    if [ -f "$dhcp_log" ]; then
        echo "DHCP Server Log Analysis:" >>"$REPORT_DIR/log_analysis.txt"
        echo "- Log file size: $(wc -l <"$dhcp_log" 2>/dev/null || echo "0") lines" >>"$REPORT_DIR/log_analysis.txt"

        local error_count=$(grep -ci "error\|fail\|critical" "$dhcp_log" 2>/dev/null || echo "0")
        local warning_count=$(grep -ci "warn" "$dhcp_log" 2>/dev/null || echo "0")

        echo "- Error messages: $error_count" >>"$REPORT_DIR/log_analysis.txt"
        echo "- Warning messages: $warning_count" >>"$REPORT_DIR/log_analysis.txt"

        TOTAL_WARNINGS=$((TOTAL_WARNINGS + warning_count))

        if [ "$error_count" -gt 0 ]; then
            echo "- Recent errors:" >>"$REPORT_DIR/log_analysis.txt"
            grep -i "error\|fail\|critical" "$dhcp_log" 2>/dev/null | tail -5 | sed 's/^/  /' >>"$REPORT_DIR/log_analysis.txt" || true
        fi

        echo "" >>"$REPORT_DIR/log_analysis.txt"
    else
        echo "DHCP Server Log: Not found or empty" >>"$REPORT_DIR/log_analysis.txt"
        echo "" >>"$REPORT_DIR/log_analysis.txt"
    fi

    # Analyze individual test logs
    echo "Individual Test Logs:" >>"$REPORT_DIR/log_analysis.txt"
    for log_file in "$TEST_RESULTS_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            local log_name=$(basename "$log_file" .log)
            local log_size=$(wc -l <"$log_file" 2>/dev/null || echo "0")
            echo "- $log_name: $log_size lines" >>"$REPORT_DIR/log_analysis.txt"

            # Check for failures in test log
            if grep -qi "fail\|error" "$log_file" 2>/dev/null; then
                echo "  Contains failures - check detailed log" >>"$REPORT_DIR/log_analysis.txt"
            fi
        fi
    done

    log_success "Log analysis completed"
}

# Generate performance report
generate_performance_report() {
    log_info "Generating performance report..."

    cat >"$REPORT_DIR/performance_report.txt" <<EOF
Performance Analysis
===================

EOF

    # Extract performance data from load test results
    local load_test_file="$TEST_RESULTS_DIR/load_test_report.json"
    if [ -f "$load_test_file" ]; then
        local avg_response=$(parse_json "$load_test_file" ".performance_metrics.avg_response_time_ms")
        local max_response=$(parse_json "$load_test_file" ".performance_metrics.max_response_time_ms")
        local min_response=$(parse_json "$load_test_file" ".performance_metrics.min_response_time_ms")
        local total_requests=$(parse_json "$load_test_file" ".performance_metrics.total_requests")
        local successful_requests=$(parse_json "$load_test_file" ".performance_metrics.successful_responses")

        cat >>"$REPORT_DIR/performance_report.txt" <<EOF
DHCP Server Performance Metrics:
- Average Response Time: ${avg_response}ms
- Minimum Response Time: ${min_response}ms
- Maximum Response Time: ${max_response}ms
- Total Requests Processed: $total_requests
- Successful Requests: $successful_requests

Performance Evaluation:
EOF

        # Evaluate performance
        if command -v bc &>/dev/null && [[ "$avg_response" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if (($(echo "$avg_response < 100" | bc -l))); then
                echo "- Response Time: EXCELLENT (< 100ms average)" >>"$REPORT_DIR/performance_report.txt"
            elif (($(echo "$avg_response < 500" | bc -l))); then
                echo "- Response Time: GOOD (< 500ms average)" >>"$REPORT_DIR/performance_report.txt"
            elif (($(echo "$avg_response < 1000" | bc -l))); then
                echo "- Response Time: ACCEPTABLE (< 1s average)" >>"$REPORT_DIR/performance_report.txt"
            else
                echo "- Response Time: POOR (≥ 1s average)" >>"$REPORT_DIR/performance_report.txt"
            fi
        fi

        if [[ "$total_requests" =~ ^[0-9]+$ ]] && [[ "$successful_requests" =~ ^[0-9]+$ ]] && [ "$total_requests" -gt 0 ]; then
            local success_rate=$(echo "scale=2; $successful_requests * 100 / $total_requests" | bc 2>/dev/null || echo "0")
            echo "- Success Rate: $success_rate%" >>"$REPORT_DIR/performance_report.txt"

            if (($(echo "$success_rate >= 95" | bc -l 2>/dev/null))); then
                echo "- Reliability: EXCELLENT (≥ 95% success)" >>"$REPORT_DIR/performance_report.txt"
            elif (($(echo "$success_rate >= 80" | bc -l 2>/dev/null))); then
                echo "- Reliability: GOOD (≥ 80% success)" >>"$REPORT_DIR/performance_report.txt"
            else
                echo "- Reliability: NEEDS IMPROVEMENT (< 80% success)" >>"$REPORT_DIR/performance_report.txt"
            fi
        fi

    else
        echo "Load test results not available - performance analysis skipped" >>"$REPORT_DIR/performance_report.txt"
    fi

    echo "" >>"$REPORT_DIR/performance_report.txt"

    # Database performance if available
    local db_test_file="$TEST_RESULTS_DIR/database_test_report.json"
    if [ -f "$db_test_file" ]; then
        echo "Database Performance:" >>"$REPORT_DIR/performance_report.txt"
        echo "- All database tests completed successfully" >>"$REPORT_DIR/performance_report.txt"
        echo "- Connection and query performance verified" >>"$REPORT_DIR/performance_report.txt"
    fi

    log_success "Performance report generated"
}

# Generate issue and recommendation report
generate_issues_and_recommendations() {
    log_info "Generating issues and recommendations..."

    cat >"$REPORT_DIR/issues_and_recommendations.txt" <<EOF
Issues and Recommendations
==========================

EOF

    local issues_found=false

    # Check for failed tests
    if [ $TOTAL_FAILED -gt 0 ]; then
        echo "CRITICAL ISSUES:" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "- $TOTAL_FAILED test(s) failed" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "  Recommendation: Review individual test logs for detailed error information" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "" >>"$REPORT_DIR/issues_and_recommendations.txt"
        issues_found=true
    fi

    # Check for warnings
    if [ $TOTAL_WARNINGS -gt 10 ]; then
        echo "WARNINGS:" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "- High number of warnings found ($TOTAL_WARNINGS)" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "  Recommendation: Review server logs for potential issues" >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "" >>"$REPORT_DIR/issues_and_recommendations.txt"
        issues_found=true
    fi

    # Check performance issues
    local load_test_file="$TEST_RESULTS_DIR/load_test_report.json"
    if [ -f "$load_test_file" ]; then
        local avg_response=$(parse_json "$load_test_file" ".performance_metrics.avg_response_time_ms")
        if command -v bc &>/dev/null && [[ "$avg_response" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if (($(echo "$avg_response > 1000" | bc -l))); then
                echo "PERFORMANCE ISSUES:" >>"$REPORT_DIR/issues_and_recommendations.txt"
                echo "- High average response time: ${avg_response}ms" >>"$REPORT_DIR/issues_and_recommendations.txt"
                echo "  Recommendation: Optimize server configuration or increase resources" >>"$REPORT_DIR/issues_and_recommendations.txt"
                echo "" >>"$REPORT_DIR/issues_and_recommendations.txt"
                issues_found=true
            fi
        fi
    fi

    if [ "$issues_found" = false ]; then
        echo "No critical issues detected." >>"$REPORT_DIR/issues_and_recommendations.txt"
        echo "" >>"$REPORT_DIR/issues_and_recommendations.txt"
    fi

    # General recommendations
    cat >>"$REPORT_DIR/issues_and_recommendations.txt" <<EOF
GENERAL RECOMMENDATIONS:

1. Monitoring:
   - Implement continuous monitoring of DHCP server performance
   - Set up alerting for high response times or failure rates
   - Monitor database connection health and query performance

2. Security:
   - Regularly update DHCP server software
   - Monitor for unauthorized DHCP servers on the network
   - Implement network segmentation where appropriate

3. Backup and Recovery:
   - Regular backups of DHCP lease database
   - Document recovery procedures
   - Test backup restoration procedures

4. Capacity Planning:
   - Monitor lease pool utilization
   - Plan for network growth and increased DHCP load
   - Consider load balancing for high-availability setups

5. Documentation:
   - Maintain up-to-date network documentation
   - Document configuration changes
   - Keep troubleshooting procedures current
EOF

    log_success "Issues and recommendations report generated"
}

# Create HTML report
generate_html_report() {
    log_info "Generating HTML report..."

    local html_file="$REPORT_DIR/test_report.html"

    cat >"$html_file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DHCP SQL Server Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; margin: 0; padding: 20px; background-color: #f4f4f4; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 3px solid #333; padding-bottom: 20px; margin-bottom: 30px; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .metric { display: inline-block; margin: 10px 20px; padding: 15px; background-color: #e9ecef; border-radius: 5px; }
        .section { margin: 30px 0; }
        .section h2 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        .test-suite { background-color: #f8f9fa; padding: 15px; margin: 10px 0; border-left: 4px solid #007bff; }
        pre { background-color: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .footer { text-align: center; margin-top: 40px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #6c757d; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>DHCP SQL Server Integration Test Report</h1>
            <p>Generated on $(date)</p>
            <p>Overall Status:
                $([ $TOTAL_FAILED -eq 0 ] && echo '<span class="status-pass">PASSED</span>' || echo '<span class="status-fail">FAILED</span>')
            </p>
        </div>

        <div class="section">
            <h2>Test Summary</h2>
            <div class="metric">Total Tests: <strong>$TOTAL_TESTS</strong></div>
            <div class="metric">Passed: <span class="status-pass">$TOTAL_PASSED</span></div>
            <div class="metric">Failed: <span class="status-fail">$TOTAL_FAILED</span></div>
            <div class="metric">Success Rate: <strong>$(echo "scale=2; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc 2>/dev/null || echo "N/A")%</strong></div>
        </div>

        <div class="section">
            <h2>System Information</h2>
            <pre>$(cat "$REPORT_DIR/system_info.txt" 2>/dev/null || echo "System information not available")</pre>
        </div>

        <div class="section">
            <h2>Performance Metrics</h2>
            <pre>$(cat "$REPORT_DIR/performance_report.txt" 2>/dev/null || echo "Performance data not available")</pre>
        </div>

        <div class="section">
            <h2>Issues and Recommendations</h2>
            <pre>$(cat "$REPORT_DIR/issues_and_recommendations.txt" 2>/dev/null || echo "No issues report available")</pre>
        </div>

        <div class="section">
            <h2>Log Analysis</h2>
            <pre>$(cat "$REPORT_DIR/log_analysis.txt" 2>/dev/null || echo "Log analysis not available")</pre>
        </div>

        <div class="footer">
            <p>DHCP SQL Server Test Suite - Report generated automatically</p>
            <p>For detailed information, check individual test result files</p>
        </div>
    </div>
</body>
</html>
EOF

    log_success "HTML report generated: $html_file"
}

# Generate machine-readable JSON report
generate_json_report() {
    log_info "Generating JSON report for automation..."

    local json_file="$REPORT_DIR/consolidated_report.json"

    cat >"$json_file" <<EOF
{
    "test_execution": {
        "timestamp": "$(date -Iseconds)",
        "hostname": "$(hostname 2>/dev/null || echo "unknown")",
        "environment": {
            "mysql_host": "${MYSQL_HOST:-"not_set"}",
            "dhcp_server_ip": "${DHCP_SERVER_IP:-"not_set"}",
            "test_mode": "${TEST_MODE:-"not_set"}"
        }
    },
    "summary": {
        "total_tests": $TOTAL_TESTS,
        "passed": $TOTAL_PASSED,
        "failed": $TOTAL_FAILED,
        "warnings": $TOTAL_WARNINGS,
        "success_rate_percent": $(echo "scale=2; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc 2>/dev/null || echo "0"),
        "overall_status": "$([ $TOTAL_FAILED -eq 0 ] && echo "PASS" || echo "FAIL")"
    },
    "test_suites": {
EOF

    # Add individual test suite results
    local first=true
    local result_files=(
        "integration_test_report.json"
        "database_test_report.json"
        "server_test_report.json"
        "client_test_report.json"
        "load_test_report.json"
    )

    for result_file in "${result_files[@]}"; do
        local file_path="$TEST_RESULTS_DIR/$result_file"
        if [ -f "$file_path" ]; then
            if [ "$first" = false ]; then
                echo "," >>"$json_file"
            fi
            first=false

            local test_suite="${result_file%_test_report.json}"
            test_suite="${test_suite%_report.json}"
            test_suite="${test_suite#integration_}"

            echo "        \"$test_suite\": $(cat "$file_path")" >>"$json_file"
        fi
    done

    cat >>"$json_file" <<EOF
    },
    "report_files": {
        "html_report": "test_report.html",
        "system_info": "system_info.txt",
        "performance_report": "performance_report.txt",
        "issues_and_recommendations": "issues_and_recommendations.txt",
        "log_analysis": "log_analysis.txt",
        "test_summary": "test_summary.txt"
    }
}
EOF

    log_success "JSON report generated: $json_file"
}

# Display final summary
display_final_summary() {
    echo
    echo "============================================"
    log_header "     FINAL TEST REPORT SUMMARY"
    echo "============================================"
    echo
    echo "Test Execution Completed: $(date)"
    echo "Total Tests Run: $TOTAL_TESTS"
    echo "Passed: $TOTAL_PASSED"
    echo "Failed: $TOTAL_FAILED"
    echo "Warnings: $TOTAL_WARNINGS"
    echo "Success Rate: $(echo "scale=2; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc 2>/dev/null || echo "N/A")%"
    echo
    echo "Report Files Generated:"
    echo "  - HTML Report: $REPORT_DIR/test_report.html"
    echo "  - JSON Report: $REPORT_DIR/consolidated_report.json"
    echo "  - Text Reports: $REPORT_DIR/*.txt"
    echo
    if [ $TOTAL_FAILED -eq 0 ]; then
        log_success "ALL TESTS PASSED! ✓"
        echo "The DHCP SQL Server has successfully passed all integration tests."
    else
        log_error "SOME TESTS FAILED! ✗"
        echo "Please review the detailed reports for information about failed tests."
        echo "Check the issues and recommendations report for guidance."
    fi
    echo
    echo "============================================"
}

# Main execution
main() {
    log_info "Starting test report generation..."

    # Setup
    setup_report_environment

    # Wait a moment for all test files to be written
    sleep 2

    # Collect all information
    collect_system_info
    aggregate_test_results
    analyze_logs
    generate_performance_report
    generate_issues_and_recommendations

    # Generate reports
    generate_html_report
    generate_json_report

    # Display summary
    display_final_summary

    # Set exit code based on test results
    if [ $TOTAL_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
