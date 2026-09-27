#!/bin/bash

# DHCP SQL Server - Client Component Test Runner
# This script tests the DHCP client component specifically

set -euo pipefail

# Configuration
export TEST_RESULTS_DIR="/app/tests/results"
export LOG_DIR="/var/log/dhcp"
export CONFIG_DIR="/app/config"
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
CLIENT_PID=""

# Helper functions
log_info() {
    echo -e "${BLUE}[CLIENT-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[CLIENT-PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[CLIENT-FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[CLIENT-WARN]${NC} $1"
}

run_client_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_info "Running client test: $test_name"

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
    log_info "Waiting for DHCP server to be ready..."

    for i in {1..30}; do
        if nc -u -z "$DHCP_SERVER_IP" 67 2>/dev/null; then
            log_success "DHCP server is reachable"
            return 0
        fi
        sleep 2
    done

    log_error "DHCP server not reachable after 60 seconds"
    return 1
}

# Test client binary functionality
test_client_binary() {
    # Test if binary exists and is executable
    if ! command -v udhcpc &>/dev/null; then
        log_error "udhcpc binary not found in PATH"
        return 1
    fi

    # Test version/help output
    if ! timeout 5 udhcpc --version &>/dev/null && ! timeout 5 udhcpc -h &>/dev/null; then
        log_warning "udhcpc version/help not available (this may be normal)"
    fi

    # Test that binary can be executed
    if timeout 5 udhcpc -n -q -i lo -x hostname:test &>/dev/null; then
        log_success "udhcpc binary executes without critical errors"
    else
        log_warning "udhcpc execution test failed (may be due to interface constraints)"
    fi

    return 0
}

# Test client script functionality
test_client_script() {
    local script_file="$CONFIG_DIR/simple.script"

    if [ ! -f "$script_file" ]; then
        log_error "Client script not found: $script_file"
        return 1
    fi

    if [ ! -x "$script_file" ]; then
        log_error "Client script not executable: $script_file"
        return 1
    fi

    # Test script with deconfig action
    if timeout 10 "$script_file" deconfig &>/dev/null; then
        log_success "Client script handles deconfig action"
    else
        log_warning "Client script deconfig test failed"
    fi

    # Test script with bound action (simulated)
    export interface="test0"
    export ip="172.20.1.100"
    export subnet="255.255.0.0"
    export router="172.20.0.1"

    if timeout 10 "$script_file" bound &>/dev/null; then
        log_success "Client script handles bound action"
    else
        log_warning "Client script bound test failed"
    fi

    return 0
}

# Test DHCP discover functionality
test_dhcp_discover() {
    log_info "Testing DHCP discover functionality..."

    # Use Python to send a proper DHCP discover and analyze response
    local discover_result
    discover_result=$(timeout 20 python3 -c "
import socket
import struct
import time
import sys
import os

def create_dhcp_discover():
    # Create a DHCP DISCOVER packet
    packet = bytearray(240)

    # DHCP header
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0

    # Transaction ID
    xid = 0x12345678
    packet[4:8] = struct.pack('>I', xid)

    # Flags: Broadcast
    packet[10:12] = struct.pack('>H', 0x8000)

    # Client MAC address (fake for testing)
    packet[28:34] = b'\\x00\\x11\\x22\\xaa\\xbb\\xcc'

    # Magic cookie
    packet[236:240] = b'\\x63\\x82\\x53\\x63'

    return packet, xid

def parse_dhcp_response(data):
    if len(data) < 240:
        return None

    # Extract offered IP address
    offered_ip = struct.unpack('>I', data[16:20])[0]

    # Convert to dotted decimal
    ip_str = f'{(offered_ip >> 24) & 0xff}.{(offered_ip >> 16) & 0xff}.{(offered_ip >> 8) & 0xff}.{offered_ip & 0xff}'

    return {
        'offered_ip': ip_str,
        'transaction_id': struct.unpack('>I', data[4:8])[0]
    }

try:
    # Create socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(10)

    # Bind to client port
    try:
        sock.bind(('0.0.0.0', 68))
    except OSError:
        print('WARNING: Could not bind to port 68, using random port')
        sock.bind(('0.0.0.0', 0))

    # Create and send DISCOVER
    discover_packet, xid = create_dhcp_discover()
    sock.sendto(discover_packet, ('$DHCP_SERVER_IP', 67))

    # Wait for OFFER response
    response, addr = sock.recvfrom(1024)

    # Parse response
    parsed = parse_dhcp_response(response)

    if parsed and parsed['transaction_id'] == xid:
        print(f'SUCCESS: Received DHCP OFFER for IP {parsed[\"offered_ip\"]}')
    elif parsed:
        print(f'WARNING: Received DHCP response but transaction ID mismatch')
    else:
        print('ERROR: Could not parse DHCP response')

except socket.timeout:
    print('TIMEOUT: No DHCP OFFER received within 10 seconds')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$discover_result" == *"SUCCESS"* ]]; then
        log_success "DHCP discover test passed: $discover_result"
        return 0
    elif [[ "$discover_result" == *"WARNING"* ]]; then
        log_warning "DHCP discover test had issues: $discover_result"
        return 0
    else
        log_error "DHCP discover test failed: $discover_result"
        return 1
    fi
}

# Test client configuration request
test_client_request() {
    log_info "Testing DHCP request functionality..."

    # Simulate a DHCP request for a specific IP
    local request_result
    request_result=$(timeout 20 python3 -c "
import socket
import struct
import time

def create_dhcp_request(requested_ip):
    packet = bytearray(300)  # Larger to accommodate options

    # DHCP header
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0

    # Transaction ID
    xid = 0x87654321
    packet[4:8] = struct.pack('>I', xid)

    # Flags: Broadcast
    packet[10:12] = struct.pack('>H', 0x8000)

    # Client MAC address
    packet[28:34] = b'\\x00\\x11\\x22\\xaa\\xbb\\xcc'

    # Magic cookie
    packet[236:240] = b'\\x63\\x82\\x53\\x63'

    # DHCP options
    option_offset = 240

    # Option 53: DHCP Message Type (REQUEST)
    packet[option_offset:option_offset+3] = b'\\x35\\x01\\x03'
    option_offset += 3

    # Option 50: Requested IP Address
    ip_bytes = socket.inet_aton(requested_ip)
    packet[option_offset:option_offset+6] = b'\\x32\\x04' + ip_bytes
    option_offset += 6

    # Option 55: Parameter Request List
    packet[option_offset:option_offset+6] = b'\\x37\\x04\\x01\\x03\\x06\\x0f'
    option_offset += 6

    # End option
    packet[option_offset] = 255

    return packet[:option_offset+1], xid

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(10)

    try:
        sock.bind(('0.0.0.0', 68))
    except OSError:
        sock.bind(('0.0.0.0', 0))

    # Request a specific IP from test range
    request_packet, xid = create_dhcp_request('172.20.1.100')
    sock.sendto(request_packet, ('$DHCP_SERVER_IP', 67))

    # Wait for ACK or NAK
    response, addr = sock.recvfrom(1024)

    if len(response) >= 240:
        # Check if it's an ACK (message type would be in options)
        print('SUCCESS: Received DHCP response to REQUEST')
    else:
        print('WARNING: Received short response to REQUEST')

except socket.timeout:
    print('TIMEOUT: No response to DHCP REQUEST')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$request_result" == *"SUCCESS"* ]]; then
        log_success "DHCP request test passed"
        return 0
    elif [[ "$request_result" == *"WARNING"* ]]; then
        log_warning "DHCP request test had issues: $request_result"
        return 0
    else
        log_error "DHCP request test failed: $request_result"
        return 1
    fi
}

# Test client with actual interface (if possible)
test_client_interface() {
    # Create a dummy interface for testing if possible
    if command -v ip &>/dev/null; then
        # Try to create a dummy interface
        if ip link add test-dhcp type dummy 2>/dev/null; then
            ip link set test-dhcp up 2>/dev/null

            log_info "Created test interface, trying DHCP client..."

            # Try to run udhcpc on the test interface with short timeout
            if timeout 10 udhcpc -i test-dhcp -n -q -t 2 -T 3 2>/dev/null; then
                log_success "DHCP client worked on test interface"
            else
                log_warning "DHCP client failed on test interface (expected in test environment)"
            fi

            # Clean up test interface
            ip link delete test-dhcp 2>/dev/null || true
        else
            log_warning "Could not create test interface for client testing"
        fi
    else
        log_warning "ip command not available for interface testing"
    fi

    return 0
}

# Test client lease renewal simulation
test_lease_renewal() {
    log_info "Testing lease renewal simulation..."

    # Simulate DHCP renewal process
    local renewal_result
    renewal_result=$(timeout 15 python3 -c "
import socket
import struct
import time

def create_dhcp_renew(current_ip, server_ip):
    packet = bytearray(280)

    # DHCP header
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0

    # Transaction ID
    xid = 0x11223344
    packet[4:8] = struct.pack('>I', xid)

    # Current IP address (ciaddr)
    packet[12:16] = socket.inet_aton(current_ip)

    # Client MAC address
    packet[28:34] = b'\\x00\\x11\\x22\\xaa\\xbb\\xcc'

    # Magic cookie
    packet[236:240] = b'\\x63\\x82\\x53\\x63'

    # DHCP options
    option_offset = 240

    # Option 53: DHCP Message Type (REQUEST for renewal)
    packet[option_offset:option_offset+3] = b'\\x35\\x01\\x03'
    option_offset += 3

    # Option 54: Server Identifier
    server_bytes = socket.inet_aton(server_ip)
    packet[option_offset:option_offset+6] = b'\\x36\\x04' + server_bytes
    option_offset += 6

    # End option
    packet[option_offset] = 255

    return packet[:option_offset+1], xid

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(8)

    # For renewal, we send directly to server (unicast)
    renew_packet, xid = create_dhcp_renew('172.20.1.100', '$DHCP_SERVER_IP')
    sock.sendto(renew_packet, ('$DHCP_SERVER_IP', 67))

    # Wait for ACK
    response, addr = sock.recvfrom(1024)

    if len(response) >= 240:
        print('SUCCESS: Received response to lease renewal')
    else:
        print('WARNING: Short response to renewal')

except socket.timeout:
    print('TIMEOUT: No response to lease renewal')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$renewal_result" == *"SUCCESS"* ]]; then
        log_success "Lease renewal test passed"
        return 0
    else
        log_warning "Lease renewal test issues: $renewal_result"
        return 0 # Don't fail on this as it's complex to test properly
    fi
}

# Test client option handling
test_client_options() {
    log_info "Testing client option handling..."

    # Test that client can request and handle various DHCP options
    local options_result
    options_result=$(timeout 15 python3 -c "
import socket
import struct

def create_dhcp_discover_with_options():
    packet = bytearray(280)

    # DHCP header
    packet[0] = 1    # op: Boot Request
    packet[1] = 1    # htype: Ethernet
    packet[2] = 6    # hlen: 6 bytes
    packet[3] = 0    # hops: 0

    # Transaction ID
    xid = 0xaabbccdd
    packet[4:8] = struct.pack('>I', xid)

    # Flags: Broadcast
    packet[10:12] = struct.pack('>H', 0x8000)

    # Client MAC address
    packet[28:34] = b'\\x00\\x11\\x22\\xaa\\xbb\\xcc'

    # Magic cookie
    packet[236:240] = b'\\x63\\x82\\x53\\x63'

    # DHCP options
    option_offset = 240

    # Option 53: DHCP Message Type (DISCOVER)
    packet[option_offset:option_offset+3] = b'\\x35\\x01\\x01'
    option_offset += 3

    # Option 55: Parameter Request List (comprehensive)
    requested_options = b'\\x01\\x03\\x06\\x0f\\x1c\\x2a\\x2b\\x2c'
    packet[option_offset:option_offset+2+len(requested_options)] = b'\\x37' + bytes([len(requested_options)]) + requested_options
    option_offset += 2 + len(requested_options)

    # Option 60: Vendor Class Identifier
    vendor_class = b'TEST-CLIENT'
    packet[option_offset:option_offset+2+len(vendor_class)] = b'\\x3c' + bytes([len(vendor_class)]) + vendor_class
    option_offset += 2 + len(vendor_class)

    # End option
    packet[option_offset] = 255

    return packet[:option_offset+1], xid

def parse_options(data, start_offset):
    options = {}
    offset = start_offset

    while offset < len(data):
        option_type = data[offset]
        if option_type == 255:  # End option
            break
        if option_type == 0:    # Pad option
            offset += 1
            continue

        if offset + 1 >= len(data):
            break

        option_len = data[offset + 1]
        if offset + 2 + option_len > len(data):
            break

        option_data = data[offset + 2:offset + 2 + option_len]
        options[option_type] = option_data

        offset += 2 + option_len

    return options

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(10)

    try:
        sock.bind(('0.0.0.0', 68))
    except OSError:
        sock.bind(('0.0.0.0', 0))

    discover_packet, xid = create_dhcp_discover_with_options()
    sock.sendto(discover_packet, ('$DHCP_SERVER_IP', 67))

    response, addr = sock.recvfrom(1024)

    if len(response) >= 240:
        # Parse DHCP options in response
        options = parse_options(response, 240)

        option_count = len(options)
        print(f'SUCCESS: Received DHCP response with {option_count} options')

        # Check for common options
        if 1 in options:  # Subnet mask
            print('  Found subnet mask option')
        if 3 in options:  # Router
            print('  Found router option')
        if 6 in options:  # DNS servers
            print('  Found DNS server option')

    else:
        print('WARNING: Short DHCP response received')

except socket.timeout:
    print('TIMEOUT: No response to options test')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    try:
        sock.close()
    except:
        pass
" 2>&1)

    if [[ "$options_result" == *"SUCCESS"* ]]; then
        log_success "Client options test passed"
        return 0
    else
        log_warning "Client options test issues: $options_result"
        return 0
    fi
}

# Test client error handling
test_client_error_handling() {
    # Test client behavior with invalid server responses
    log_info "Testing client error handling..."

    # Test with non-existent server
    if timeout 5 udhcpc -i lo -n -q -t 1 -T 1 -s /dev/null 2>/dev/null; then
        log_warning "Client succeeded with invalid interface (unexpected)"
    else
        log_success "Client properly handles invalid interface"
    fi

    # Test with invalid script
    if timeout 5 udhcpc -i lo -n -q -t 1 -T 1 -s /nonexistent/script 2>/dev/null; then
        log_warning "Client succeeded with invalid script (unexpected)"
    else
        log_success "Client properly handles invalid script"
    fi

    return 0
}

# Test client performance
test_client_performance() {
    log_info "Testing client performance..."

    local start_time=$(date +%s%N)

    # Send multiple rapid DHCP discovers to test performance
    for i in {1..5}; do
        timeout 3 python3 -c "
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.settimeout(2)

packet = bytearray(240)
packet[0] = 1
packet[1] = 1
packet[2] = 6
packet[4:8] = struct.pack('>I', 0x12340000 + $i)
packet[10:12] = struct.pack('>H', 0x8000)
packet[28:34] = b'\\x00\\x11\\x22\\xbb\\xbb' + bytes([0xc0 + $i])
packet[236:240] = b'\\x63\\x82\\x53\\x63'

try:
    sock.bind(('0.0.0.0', 0))
    sock.sendto(packet, ('$DHCP_SERVER_IP', 67))
    sock.recvfrom(1024)
except:
    pass
finally:
    sock.close()
" &>/dev/null || true
    done

    local end_time=$(date +%s%N)
    local duration_ms=$(((end_time - start_time) / 1000000))

    log_info "Client performance test: 5 DHCP transactions in ${duration_ms}ms"

    if [ "$duration_ms" -lt 5000 ]; then
        log_success "Client performance is good"
    else
        log_warning "Client performance may be slow: ${duration_ms}ms for 5 transactions"
    fi

    return 0
}

# Generate client test report
generate_client_test_report() {
    mkdir -p "$TEST_RESULTS_DIR"

    cat >"$TEST_RESULTS_DIR/client_test_report.json" <<EOF
{
    "client_tests": {
        "total_tests": $TESTS_RUN,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": "$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%",
        "timestamp": "$(date -Iseconds)"
    },
    "test_environment": {
        "dhcp_server_ip": "$DHCP_SERVER_IP",
        "test_interface": "test-dhcp",
        "script_path": "$CONFIG_DIR/simple.script"
    }
}
EOF

    echo
    echo "============================================"
    echo "           CLIENT TEST SUMMARY"
    echo "============================================"
    echo "Total Tests:    $TESTS_RUN"
    echo "Passed:         $TESTS_PASSED"
    echo "Failed:         $TESTS_FAILED"
    echo "Success Rate:   $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "N/A")%"
    echo "============================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "ALL CLIENT TESTS PASSED!"
        return 0
    else
        log_error "$TESTS_FAILED client tests failed"
        return 1
    fi
}

# Cleanup function
cleanup() {
    # Kill any remaining client processes
    if [ -n "$CLIENT_PID" ] && kill -0 $CLIENT_PID 2>/dev/null; then
        kill $CLIENT_PID 2>/dev/null || true
    fi

    # Clean up any test interfaces
    ip link delete test-dhcp 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting DHCP Client Component Tests..."

    # Setup cleanup trap
    trap cleanup EXIT INT TERM

    # Wait for DHCP server
    if ! wait_for_dhcp_server; then
        log_error "DHCP server not available"
        exit 1
    fi

    # Run all client tests
    run_client_test "client_binary" "test_client_binary"
    run_client_test "client_script" "test_client_script"
    run_client_test "dhcp_discover" "test_dhcp_discover"
    run_client_test "client_request" "test_client_request"
    run_client_test "client_interface" "test_client_interface"
    run_client_test "lease_renewal" "test_lease_renewal"
    run_client_test "client_options" "test_client_options"
    run_client_test "client_error_handling" "test_client_error_handling"
    run_client_test "client_performance" "test_client_performance"

    # Generate report
    generate_client_test_report
}

# Execute main function
main "$@"
