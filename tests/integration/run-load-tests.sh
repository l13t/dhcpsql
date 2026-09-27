#!/bin/bash

# DHCP SQL Server - Load Testing Script
# This script performs load testing on the DHCP server to validate performance under stress

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
export LOG_DIR="/var/log/dhcp"
export DHCP_SERVER_IP="${DHCP_SERVER_IP:-172.20.0.10}"
export LOAD_TEST_CLIENTS="${LOAD_TEST_CLIENTS:-50}"
export LOAD_TEST_DURATION="${LOAD_TEST_DURATION:-60}"
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

# Test counters and metrics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_REQUESTS=0
SUCCESSFUL_RESPONSES=0
FAILED_REQUESTS=0
MIN_RESPONSE_TIME=999999
MAX_RESPONSE_TIME=0
TOTAL_RESPONSE_TIME=0

# Helper functions
log_info() {
    echo -e "${BLUE}[LOAD-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[LOAD-PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[LOAD-FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[LOAD-WARN]${NC} $1"
}

# MySQL helper function
mysql_query() {
    mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -sN "$@"
}

run_load_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_info "Running load test: $test_name"

    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Wait for DHCP server to be ready
wait_for_dhcp_server() {
    log_info "Waiting for DHCP server to be ready for load testing..."

    for i in {1..30}; do
        if nc -u -z "$DHCP_SERVER_IP" 67 2>/dev/null; then
            log_success "DHCP server is reachable"
            return 0
        fi
        sleep 2
    done

    log_error "DHCP server not reachable"
    return 1
}

# Baseline performance test
test_baseline_performance() {
    log_info "Establishing baseline performance metrics..."

    local start_time=$(date +%s%N)

    # Send a single DHCP discover to measure baseline
    local baseline_result
    baseline_result=$(timeout 10 python3 -c "
import socket
import struct
import time

def create_dhcp_discover():
    packet = bytearray(240)
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0
    packet[4:8] = struct.pack('>I', 0x12345678)  # Transaction ID
    packet[10:12] = struct.pack('>H', 0x8000)    # Flags: Broadcast
    packet[28:34] = b'\\x00\\x11\\x22\\xaa\\xbb\\xcc'  # MAC address
    packet[236:240] = b'\\x63\\x82\\x53\\x63'    # Magic cookie
    return packet

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(5)

    try:
        sock.bind(('0.0.0.0', 68))
    except OSError:
        sock.bind(('0.0.0.0', 0))

    start = time.time()
    discover_packet = create_dhcp_discover()
    sock.sendto(discover_packet, ('$DHCP_SERVER_IP', 67))
    response, addr = sock.recvfrom(1024)
    end = time.time()

    response_time_ms = (end - start) * 1000
    print(f'SUCCESS: Baseline response time: {response_time_ms:.2f}ms')

except socket.timeout:
    print('TIMEOUT: No response for baseline test')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$baseline_result" == *"SUCCESS"* ]]; then
        log_success "Baseline performance established: $baseline_result"
        return 0
    else
        log_error "Failed to establish baseline: $baseline_result"
        return 1
    fi
}

# Concurrent client simulation
test_concurrent_clients() {
    log_info "Testing concurrent DHCP clients (${LOAD_TEST_CLIENTS} clients)..."

    # Create a Python script for concurrent client simulation
    cat >/tmp/dhcp_load_test.py <<'EOF'
#!/usr/bin/env python3
import socket
import struct
import time
import threading
import sys
import random
from concurrent.futures import ThreadPoolExecutor, as_completed

class DHCPLoadTester:
    def __init__(self, server_ip, num_clients):
        self.server_ip = server_ip
        self.num_clients = num_clients
        self.results = []
        self.lock = threading.Lock()

    def create_dhcp_discover(self, client_id):
        packet = bytearray(240)
        packet[0] = 1    # op: Boot Request
        packet[1] = 1    # htype: Ethernet
        packet[2] = 6    # hlen: 6 bytes
        packet[3] = 0    # hops: 0

        # Unique transaction ID per client
        xid = 0x10000000 + client_id
        packet[4:8] = struct.pack('>I', xid)

        packet[10:12] = struct.pack('>H', 0x8000)    # Flags: Broadcast

        # Unique MAC address per client
        mac_base = b'\x00\x11\x22'
        mac_suffix = struct.pack('>I', client_id)[1:]  # Use last 3 bytes
        packet[28:34] = mac_base + mac_suffix

        packet[236:240] = b'\x63\x82\x53\x63'    # Magic cookie
        return packet, xid

    def dhcp_client_test(self, client_id):
        result = {
            'client_id': client_id,
            'success': False,
            'response_time': 0,
            'error': None
        }

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.settimeout(10)

            # Use different ports for different clients
            try:
                sock.bind(('0.0.0.0', 0))  # Let OS assign port
            except OSError as e:
                result['error'] = f'Bind failed: {e}'
                return result

            discover_packet, xid = self.create_dhcp_discover(client_id)

            start_time = time.time()
            sock.sendto(discover_packet, (self.server_ip, 67))

            response, addr = sock.recvfrom(1024)
            end_time = time.time()

            # Verify it's a valid response
            if len(response) >= 240:
                response_xid = struct.unpack('>I', response[4:8])[0]
                if response_xid == xid:
                    result['success'] = True
                    result['response_time'] = (end_time - start_time) * 1000
                else:
                    result['error'] = 'Transaction ID mismatch'
            else:
                result['error'] = f'Short response: {len(response)} bytes'

        except socket.timeout:
            result['error'] = 'Timeout'
        except Exception as e:
            result['error'] = str(e)
        finally:
            try:
                sock.close()
            except:
                pass

        return result

    def run_load_test(self, duration_seconds):
        print(f"Starting load test: {self.num_clients} concurrent clients for {duration_seconds} seconds")

        end_time = time.time() + duration_seconds
        round_count = 0

        while time.time() < end_time:
            round_count += 1
            print(f"Round {round_count}: Testing {self.num_clients} concurrent clients...")

            with ThreadPoolExecutor(max_workers=self.num_clients) as executor:
                # Submit all client tasks
                future_to_client = {
                    executor.submit(self.dhcp_client_test, client_id): client_id
                    for client_id in range(self.num_clients)
                }

                # Collect results
                round_results = []
                for future in as_completed(future_to_client, timeout=30):
                    try:
                        result = future.result()
                        round_results.append(result)
                    except Exception as e:
                        print(f"Client task failed: {e}")

            # Analyze round results
            successful = sum(1 for r in round_results if r['success'])
            failed = len(round_results) - successful

            if successful > 0:
                response_times = [r['response_time'] for r in round_results if r['success']]
                avg_response = sum(response_times) / len(response_times)
                min_response = min(response_times)
                max_response = max(response_times)

                print(f"Round {round_count}: {successful}/{len(round_results)} successful, "
                      f"avg: {avg_response:.2f}ms, min: {min_response:.2f}ms, max: {max_response:.2f}ms")
            else:
                print(f"Round {round_count}: No successful responses")

            with self.lock:
                self.results.extend(round_results)

            # Brief pause between rounds
            time.sleep(1)

        return self.analyze_results()

    def analyze_results(self):
        if not self.results:
            return {
                'total_requests': 0,
                'successful': 0,
                'failed': 0,
                'success_rate': 0,
                'avg_response_time': 0,
                'min_response_time': 0,
                'max_response_time': 0
            }

        successful_results = [r for r in self.results if r['success']]

        total_requests = len(self.results)
        successful = len(successful_results)
        failed = total_requests - successful

        if successful > 0:
            response_times = [r['response_time'] for r in successful_results]
            avg_response_time = sum(response_times) / len(response_times)
            min_response_time = min(response_times)
            max_response_time = max(response_times)
        else:
            avg_response_time = 0
            min_response_time = 0
            max_response_time = 0

        return {
            'total_requests': total_requests,
            'successful': successful,
            'failed': failed,
            'success_rate': (successful / total_requests) * 100 if total_requests > 0 else 0,
            'avg_response_time': avg_response_time,
            'min_response_time': min_response_time,
            'max_response_time': max_response_time,
            'requests_per_second': total_requests / max(1, int(sys.argv[3]))
        }

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: dhcp_load_test.py <server_ip> <num_clients> <duration_seconds>")
        sys.exit(1)

    server_ip = sys.argv[1]
    num_clients = int(sys.argv[2])
    duration = int(sys.argv[3])

    tester = DHCPLoadTester(server_ip, num_clients)
    results = tester.run_load_test(duration)

    print("\n" + "="*50)
    print("LOAD TEST RESULTS")
    print("="*50)
    print(f"Total Requests: {results['total_requests']}")
    print(f"Successful: {results['successful']}")
    print(f"Failed: {results['failed']}")
    print(f"Success Rate: {results['success_rate']:.2f}%")
    print(f"Average Response Time: {results['avg_response_time']:.2f}ms")
    print(f"Min Response Time: {results['min_response_time']:.2f}ms")
    print(f"Max Response Time: {results['max_response_time']:.2f}ms")
    print(f"Requests Per Second: {results['requests_per_second']:.2f}")
    print("="*50)

    # Output results in a format that can be parsed by bash
    print(f"RESULT_SUCCESS_RATE={results['success_rate']}")
    print(f"RESULT_AVG_RESPONSE={results['avg_response_time']}")
    print(f"RESULT_MAX_RESPONSE={results['max_response_time']}")
    print(f"RESULT_REQUESTS_PER_SEC={results['requests_per_second']}")
EOF

    chmod +x /tmp/dhcp_load_test.py

    # Run the load test
    local load_test_output
    load_test_output=$(python3 /tmp/dhcp_load_test.py "$DHCP_SERVER_IP" "$LOAD_TEST_CLIENTS" "$LOAD_TEST_DURATION" 2>&1)

    echo "$load_test_output"

    # Parse results
    local success_rate
    local avg_response
    local max_response
    local requests_per_sec

    success_rate=$(echo "$load_test_output" | grep "RESULT_SUCCESS_RATE=" | cut -d'=' -f2)
    avg_response=$(echo "$load_test_output" | grep "RESULT_AVG_RESPONSE=" | cut -d'=' -f2)
    max_response=$(echo "$load_test_output" | grep "RESULT_MAX_RESPONSE=" | cut -d'=' -f2)
    requests_per_sec=$(echo "$load_test_output" | grep "RESULT_REQUESTS_PER_SEC=" | cut -d'=' -f2)

    # Evaluate results
    local test_passed=true

    if (($(echo "$success_rate < 80" | bc -l))); then
        log_error "Success rate too low: ${success_rate}% (expected ≥80%)"
        test_passed=false
    fi

    if (($(echo "$avg_response > 1000" | bc -l))); then
        log_warning "Average response time high: ${avg_response}ms (expected <1000ms)"
    fi

    if (($(echo "$max_response > 5000" | bc -l))); then
        log_warning "Maximum response time very high: ${max_response}ms"
    fi

    if (($(echo "$requests_per_sec < 10" | bc -l))); then
        log_warning "Low throughput: ${requests_per_sec} req/sec (expected ≥10)"
    fi

    if [ "$test_passed" = true ]; then
        log_success "Concurrent client test passed - Success rate: ${success_rate}%, Avg response: ${avg_response}ms"
        return 0
    else
        return 1
    fi
}

# Database performance under load
test_database_load() {
    log_info "Testing database performance under load..."

    local start_time=$(date +%s)

    # Generate database load
    local db_load_result
    db_load_result=$(timeout 30 bash -c "
        for i in {1..100}; do
            mysql -h'$MYSQL_HOST' -u'$MYSQL_USER' -p'$MYSQL_PASSWORD' '$MYSQL_DATABASE' -e '
                SELECT COUNT(*) FROM staticleases;
                SELECT COUNT(*) FROM options;
                SELECT * FROM staticleases LIMIT 10;
                SELECT o.*, m.name FROM options o LEFT JOIN metaoptions m ON o.code = m.id LIMIT 10;
            ' &>/dev/null &

            # Limit concurrent connections
            if (( i % 10 == 0 )); then
                wait
            fi
        done
        wait
        echo 'Database load test completed'
    " 2>&1)

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ "$db_load_result" == *"completed"* ]]; then
        log_success "Database handled load test in ${duration}s"

        if [ "$duration" -gt 60 ]; then
            log_warning "Database load test took longer than expected: ${duration}s"
        fi

        return 0
    else
        log_error "Database load test failed: $db_load_result"
        return 1
    fi
}

# Memory and resource monitoring
test_resource_monitoring() {
    log_info "Monitoring server resources during load..."

    # Monitor server process if we can find it
    local dhcp_pid
    dhcp_pid=$(pgrep udhcpd | head -1)

    if [ -n "$dhcp_pid" ]; then
        log_info "Found DHCP server process: PID $dhcp_pid"

        # Monitor memory usage over time
        local max_memory=0
        local max_cpu=0

        for i in {1..10}; do
            local memory_kb
            local cpu_percent

            memory_kb=$(ps -o rss= -p "$dhcp_pid" 2>/dev/null || echo "0")
            cpu_percent=$(ps -o %cpu= -p "$dhcp_pid" 2>/dev/null | tr -d ' ' || echo "0")

            if [ "$memory_kb" -gt "$max_memory" ]; then
                max_memory=$memory_kb
            fi

            if (($(echo "$cpu_percent > $max_cpu" | bc -l))); then
                max_cpu=$cpu_percent
            fi

            sleep 2
        done

        local max_memory_mb=$((max_memory / 1024))

        log_info "Peak memory usage: ${max_memory_mb}MB"
        log_info "Peak CPU usage: ${max_cpu}%"

        # Check if resource usage is reasonable
        if [ "$max_memory_mb" -gt 500 ]; then
            log_warning "High memory usage during load: ${max_memory_mb}MB"
        fi

        if (($(echo "$max_cpu > 50" | bc -l))); then
            log_warning "High CPU usage during load: ${max_cpu}%"
        fi
    else
        log_warning "Could not find DHCP server process for monitoring"
    fi

    return 0
}

# Stress test with rapid requests
test_rapid_requests() {
    log_info "Testing server response to rapid requests..."

    # Send requests as fast as possible for a short period
    local rapid_test_result
    rapid_test_result=$(timeout 15 python3 -c "
import socket
import struct
import time
import threading
from concurrent.futures import ThreadPoolExecutor

def rapid_dhcp_request(client_id):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(2)
        sock.bind(('0.0.0.0', 0))

        # Create DHCP discover
        packet = bytearray(240)
        packet[0] = 1
        packet[1] = 1
        packet[2] = 6
        packet[4:8] = struct.pack('>I', 0x20000000 + client_id)
        packet[10:12] = struct.pack('>H', 0x8000)
        packet[28:34] = b'\\x00\\x22\\x33' + struct.pack('>I', client_id)[1:]
        packet[236:240] = b'\\x63\\x82\\x53\\x63'

        sock.sendto(packet, ('$DHCP_SERVER_IP', 67))
        response, addr = sock.recvfrom(1024)

        sock.close()
        return len(response) >= 240

    except Exception:
        return False

# Send 20 rapid requests
start_time = time.time()
with ThreadPoolExecutor(max_workers=20) as executor:
    results = list(executor.map(rapid_dhcp_request, range(20)))
end_time = time.time()

successful = sum(results)
duration = end_time - start_time

print(f'Rapid test: {successful}/20 successful in {duration:.2f}s')
print(f'Rate: {20/duration:.2f} req/sec')

if successful >= 15:  # At least 75% success
    print('SUCCESS: Server handled rapid requests well')
else:
    print('WARNING: Server struggled with rapid requests')
" 2>&1)

    echo "$rapid_test_result"

    if [[ "$rapid_test_result" == *"SUCCESS"* ]]; then
        log_success "Rapid request test passed"
        return 0
    else
        log_warning "Rapid request test showed issues: $rapid_test_result"
        return 0 # Don't fail the overall test for this
    fi
}

# Generate load test report
generate_load_test_report() {
    mkdir -p "$TEST_RESULTS_DIR"

    cat >"$TEST_RESULTS_DIR/load_test_report.json" <<EOF
{
    "load_tests": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%",
        "timestamp": "$(date -Iseconds)"
    },
    "test_configuration": {
        "dhcp_server_ip": "$DHCP_SERVER_IP",
        "concurrent_clients": $LOAD_TEST_CLIENTS,
        "test_duration": $LOAD_TEST_DURATION,
        "mysql_host": "$MYSQL_HOST"
    },
    "performance_metrics": {
        "total_requests": $TOTAL_REQUESTS,
        "successful_responses": $SUCCESSFUL_RESPONSES,
        "failed_requests": $FAILED_REQUESTS,
        "min_response_time_ms": $MIN_RESPONSE_TIME,
        "max_response_time_ms": $MAX_RESPONSE_TIME,
        "avg_response_time_ms": "$(echo "scale=2; $TOTAL_RESPONSE_TIME / $SUCCESSFUL_RESPONSES" | bc 2>/dev/null || echo "0")"
    }
}
EOF

    echo
    echo "============================================"
    echo "           LOAD TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:         $TESTS_RUN"
    echo "Passed:              $TESTS_PASSED"
    echo "Failed:              $TESTS_FAILED"
    echo "Success Rate:        $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%"
    echo "Concurrent Clients:  $LOAD_TEST_CLIENTS"
    echo "Test Duration:       ${LOAD_TEST_DURATION}s"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL LOAD TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED load tests failed"
        return 1
    fi
}

# Cleanup function
cleanup() {
    # Clean up any temporary files
    rm -f /tmp/dhcp_load_test.py

    # Kill any remaining test processes
    pkill -f "dhcp_load_test.py" 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting DHCP Load Tests..."
    log_info "Configuration: ${LOAD_TEST_CLIENTS} clients for ${LOAD_TEST_DURATION}s"

    # Setup cleanup trap
    trap cleanup EXIT INT TERM

    # Wait for DHCP server
    if ! wait_for_dhcp_server; then
        log_error "DHCP server not available for load testing"
        exit 1
    fi

    # Install required tools
    if ! command -v bc &>/dev/null; then
        log_warning "bc calculator not available, some metrics may be unavailable"
    fi

    # Run load tests
    run_load_test "baseline_performance" "test_baseline_performance"
    run_load_test "concurrent_clients" "test_concurrent_clients"
    run_load_test "database_load" "test_database_load"
    run_load_test "resource_monitoring" "test_resource_monitoring"
    run_load_test "rapid_requests" "test_rapid_requests"

    # Generate report
    generate_load_test_report
}

# Execute main function
main "$@"
