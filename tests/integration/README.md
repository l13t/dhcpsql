# DHCP SQL Server Integration Tests

This directory contains comprehensive integration tests for the DHCP SQL Server project. The test suite validates the complete functionality of the DHCP server with MySQL backend support.

## 🎯 Test Overview

The integration test suite covers:

- **Database Operations**: MySQL connectivity, schema validation, CRUD operations
- **Server Functionality**: DHCP packet handling, lease management, configuration parsing
- **Client Operations**: DHCP discovery, requests, renewals, option handling
- **Integration Testing**: End-to-end DHCP workflows
- **Load Testing**: Performance under concurrent client load
- **Error Handling**: Edge cases and failure scenarios

## 📁 Test Structure

```
tests/integration/
├── README.md                          # This file
├── run-all-tests.sh                   # Master test execution script
├── run-integration-tests.sh           # Core integration tests
├── run-database-tests.sh              # Database-specific tests
├── run-server-tests.sh                # DHCP server tests
├── run-client-tests.sh                # DHCP client tests
├── run-load-tests.sh                  # Performance/load tests
├── generate-test-report.sh            # Test report generator
├── test-data.sql                      # Test database data
└── configs/
    └── udhcpd-test.conf               # Test DHCP server configuration
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Python 3 with required modules (socket, struct, threading)
- MySQL client tools
- Network tools (nc, netstat, ip)

### Running All Tests

```bash
# Run the complete test suite
cd tests/integration
./run-all-tests.sh

# Quick test run (skip load tests)
./run-all-tests.sh --quick

# Parallel execution with load testing
./run-all-tests.sh --parallel --load-tests

# Include network simulation tests
./run-all-tests.sh --parallel --load-tests --network-tests
```

### Running Individual Test Suites

```bash
# Database tests only
./run-database-tests.sh

# Server functionality tests
./run-server-tests.sh

# Client tests
./run-client-tests.sh

# Load testing
./run-load-tests.sh

# Generate reports only
./generate-test-report.sh
```

### Using Docker Compose

```bash
# Run complete integration test suite
docker-compose -f docker-compose.integration-tests.yml up

# Run specific test services
docker-compose -f docker-compose.integration-tests.yml up database-tests
docker-compose -f docker-compose.integration-tests.yml up integration-tests

# Run load tests
docker-compose -f docker-compose.integration-tests.yml --profile load-testing up

# Run network tests
docker-compose -f docker-compose.integration-tests.yml --profile network-testing up

# Generate reports
docker-compose -f docker-compose.integration-tests.yml --profile reporting up
```

## 🧪 Test Categories

### 1. Database Integration Tests (`run-database-tests.sh`)

**Purpose**: Validate MySQL database operations and schema integrity

**Tests Include**:
- Database connection and authentication
- Schema validation (tables, columns, constraints)
- CRUD operations on static leases and options
- IP address function testing (INET_ATON/INET_NTOA)
- Data integrity and constraint validation
- Transaction handling (commit/rollback)
- Stored procedure execution
- Performance under database load

**Expected Results**:
- All database tables accessible
- Data operations complete successfully
- Performance within acceptable limits (<10s for 200 queries)

### 2. Server Component Tests (`run-server-tests.sh`)

**Purpose**: Validate DHCP server functionality and configuration

**Tests Include**:
- Server binary validation and execution
- Configuration file parsing
- Network binding (UDP port 67)
- Database connectivity from server
- DHCP packet handling (DISCOVER/OFFER)
- Lease file operations
- Static lease functionality
- Server logging and monitoring
- Resource usage validation
- Graceful shutdown testing

**Expected Results**:
- Server starts and binds to DHCP port
- Responds to DHCP DISCOVER packets
- Database integration working
- Memory usage reasonable (<100MB)
- Clean shutdown process

### 3. Client Component Tests (`run-client-tests.sh`)

**Purpose**: Validate DHCP client functionality

**Tests Include**:
- Client binary validation
- Client script execution
- DHCP DISCOVER packet generation
- DHCP REQUEST handling
- Lease renewal simulation
- DHCP option processing
- Error handling and edge cases
- Performance testing

**Expected Results**:
- Client generates valid DHCP packets
- Server responds appropriately
- Options processed correctly
- Error conditions handled gracefully

### 4. Integration Tests (`run-integration-tests.sh`)

**Purpose**: End-to-end integration validation

**Tests Include**:
- Complete DHCP workflow testing
- Database and server integration
- Configuration validation
- Lease assignment and tracking
- Option retrieval and application
- Error handling across components
- Performance validation

**Expected Results**:
- Complete DHCP lease process works
- Database and server communicate properly
- All components work together seamlessly

### 5. Load Testing (`run-load-tests.sh`)

**Purpose**: Performance validation under load

**Tests Include**:
- Baseline performance measurement
- Concurrent client simulation (configurable count)
- Database performance under load
- Resource monitoring during stress
- Rapid request handling
- Throughput and latency measurement

**Configuration**:
- `LOAD_TEST_CLIENTS`: Number of concurrent clients (default: 50)
- `LOAD_TEST_DURATION`: Test duration in seconds (default: 60)

**Expected Results**:
- Success rate ≥80% under load
- Average response time <1000ms
- System remains stable under stress

## 📊 Test Reports

The test suite generates comprehensive reports:

### Report Types

1. **HTML Report** (`test_report.html`): Visual dashboard with metrics and status
2. **JSON Report** (`consolidated_report.json`): Machine-readable results for automation
3. **Text Reports**: Detailed analysis in human-readable format
   - `test_summary.txt`: Overall test results
   - `system_info.txt`: Environment information
   - `performance_report.txt`: Performance metrics
   - `log_analysis.txt`: Log file analysis
   - `issues_and_recommendations.txt`: Issues found and recommendations

### Metrics Tracked

- **Test Execution**: Total tests, passed, failed, success rate
- **Performance**: Response times, throughput, resource usage
- **Reliability**: Error rates, warning counts, stability metrics
- **Coverage**: Feature coverage, edge case validation

## ⚙️ Configuration

### Environment Variables

```bash
# Database configuration
MYSQL_HOST=mysql-test              # MySQL server hostname
MYSQL_USER=dhcp_test              # MySQL username
MYSQL_PASSWORD=dhcp_test          # MySQL password
MYSQL_DATABASE=dhcp_test          # MySQL database name

# DHCP server configuration
DHCP_SERVER_IP=172.20.0.10        # DHCP server IP address

# Test execution options
PARALLEL_EXECUTION=false          # Enable parallel test execution
INCLUDE_LOAD_TESTS=true          # Include load testing
INCLUDE_NETWORK_TESTS=false      # Include network simulation tests
GENERATE_REPORTS=true            # Generate test reports
CLEANUP_AFTER_TESTS=true         # Clean up after test completion

# Load testing configuration
LOAD_TEST_CLIENTS=50             # Number of concurrent clients
LOAD_TEST_DURATION=60            # Test duration in seconds
```

### Test Network Configuration

The tests use a dedicated test network:
- **Network**: 172.20.0.0/16
- **DHCP Server**: 172.20.0.10
- **MySQL Server**: 172.20.0.11
- **Test Range**: 172.20.1.10 - 172.20.1.99
- **Static Leases**: 172.20.1.100+

## 🐛 Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```bash
   # Check MySQL service status
   docker-compose -f docker-compose.integration-tests.yml ps mysql-test
   
   # Check database logs
   docker-compose -f docker-compose.integration-tests.yml logs mysql-test
   ```

2. **DHCP Server Not Responding**
   ```bash
   # Check server status
   docker-compose -f docker-compose.integration-tests.yml ps dhcp-server-test
   
   # Check server logs
   docker-compose -f docker-compose.integration-tests.yml logs dhcp-server-test
   ```

3. **Permission Errors**
   ```bash
   # Make scripts executable
   chmod +x tests/integration/*.sh
   
   # Check Docker permissions
   sudo usermod -aG docker $USER
   ```

4. **Network Issues**
   ```bash
   # Check network connectivity
   docker network ls
   docker network inspect dhcp-test-network
   ```

### Debug Mode

Enable verbose logging:
```bash
# Enable debug output
./run-all-tests.sh --verbose

# Check individual test logs
ls -la tests/results/
cat tests/results/database_test_report.json
```

### Performance Issues

If tests are slow:
```bash
# Run quick tests only
./run-all-tests.sh --quick

# Skip load tests
INCLUDE_LOAD_TESTS=false ./run-all-tests.sh

# Reduce load test parameters
LOAD_TEST_CLIENTS=10 LOAD_TEST_DURATION=30 ./run-load-tests.sh
```

## 📋 Test Validation Criteria

### Passing Criteria

- **Database Tests**: All CRUD operations succeed, schema valid, performance acceptable
- **Server Tests**: Binds to port, responds to packets, database integration works
- **Client Tests**: Generates valid packets, processes responses correctly
- **Integration Tests**: Complete DHCP workflow functions end-to-end
- **Load Tests**: ≥80% success rate, reasonable response times

### Warning Conditions

- Memory usage >100MB for server
- Average response time >500ms
- Database query time >5s for standard operations
- Error/warning messages in logs

### Failure Conditions

- Cannot connect to database or DHCP server
- Server doesn't respond to DHCP packets
- Database schema corruption or missing tables
- Success rate <80% in load tests
- Critical errors in application logs

## 🔄 Continuous Integration

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
name: DHCP Integration Tests
on: [push, pull_request]
jobs:
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Integration Tests
        run: |
          cd tests/integration
          ./run-all-tests.sh --parallel
      - name: Upload Test Reports
        uses: actions/upload-artifact@v2
        with:
          name: test-reports
          path: tests/results/
```

### Docker Integration

The test suite is designed to run in containerized environments:
```bash
# Build test image
docker build -f docker/Dockerfile.test -t dhcp-tests .

# Run tests in container
docker run --rm -v $(pwd)/tests/results:/app/results dhcp-tests
```

## 📚 Additional Resources

- **Project Documentation**: `../docs/`
- **Configuration Examples**: `../config/`
- **Build Instructions**: `../README.md`
- **Docker Setup**: `../DOCKER_SETUP.md`

## 🤝 Contributing

When adding new tests:

1. Follow the existing naming convention (`test_feature_name`)
2. Include proper error handling and cleanup
3. Update this README with new test descriptions
4. Add appropriate timeout values
5. Include performance expectations
6. Document any new environment variables

## 📄 License

This test suite is part of the DHCP SQL Server project and follows the same licensing terms.

---

**Last Updated**: December 2024  
**Test Suite Version**: 1.0  
**Compatible with**: DHCP SQL Server v0.9.9+