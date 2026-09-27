# DHCP SQL Server Integration Tests Makefile
# Provides convenient targets for running various test suites

.PHONY: all test quick load database server client integration reports clean help
.DEFAULT_GOAL := help

# Configuration
TEST_DIR := $(shell pwd)
RESULTS_DIR := $(TEST_DIR)/results
DOCKER_COMPOSE := docker-compose -f ../../docker-compose.integration-tests.yml

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m # No Color

# Default test configuration
LOAD_TEST_CLIENTS ?= 50
LOAD_TEST_DURATION ?= 60
PARALLEL_EXECUTION ?= false

help: ## Show this help message
	@echo "$(BLUE)DHCP SQL Server Integration Test Suite$(NC)"
	@echo "======================================"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Environment Variables:$(NC)"
	@echo "  LOAD_TEST_CLIENTS    Number of concurrent clients for load testing (default: 50)"
	@echo "  LOAD_TEST_DURATION   Load test duration in seconds (default: 60)"
	@echo "  PARALLEL_EXECUTION   Enable parallel test execution (default: false)"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make test                    # Run all tests"
	@echo "  make quick                   # Quick test run"
	@echo "  make load LOAD_TEST_CLIENTS=100  # Load test with 100 clients"
	@echo "  make parallel                # Run tests in parallel"

all: test ## Alias for 'test' target

test: setup ## Run complete integration test suite
	@echo "$(BLUE)Running complete DHCP integration test suite...$(NC)"
	@LOAD_TEST_CLIENTS=$(LOAD_TEST_CLIENTS) \
	 LOAD_TEST_DURATION=$(LOAD_TEST_DURATION) \
	 PARALLEL_EXECUTION=$(PARALLEL_EXECUTION) \
	 ./run-all-tests.sh
	@echo "$(GREEN)Integration tests completed!$(NC)"

quick: setup ## Run quick test suite (skip load tests)
	@echo "$(BLUE)Running quick integration tests...$(NC)"
	@./run-all-tests.sh --quick
	@echo "$(GREEN)Quick tests completed!$(NC)"

parallel: setup ## Run tests in parallel with load testing
	@echo "$(BLUE)Running parallel integration tests...$(NC)"
	@PARALLEL_EXECUTION=true \
	 INCLUDE_LOAD_TESTS=true \
	 LOAD_TEST_CLIENTS=$(LOAD_TEST_CLIENTS) \
	 LOAD_TEST_DURATION=$(LOAD_TEST_DURATION) \
	 ./run-all-tests.sh --parallel --load-tests
	@echo "$(GREEN)Parallel tests completed!$(NC)"

database: setup ## Run database integration tests only
	@echo "$(BLUE)Running database tests...$(NC)"
	@./run-database-tests.sh
	@echo "$(GREEN)Database tests completed!$(NC)"

server: setup ## Run DHCP server tests only
	@echo "$(BLUE)Running server tests...$(NC)"
	@./run-server-tests.sh
	@echo "$(GREEN)Server tests completed!$(NC)"

client: setup ## Run DHCP client tests only
	@echo "$(BLUE)Running client tests...$(NC)"
	@./run-client-tests.sh
	@echo "$(GREEN)Client tests completed!$(NC)"

integration: setup ## Run core integration tests only
	@echo "$(BLUE)Running integration tests...$(NC)"
	@./run-integration-tests.sh
	@echo "$(GREEN)Integration tests completed!$(NC)"

load: setup ## Run load/performance tests only
	@echo "$(BLUE)Running load tests ($(LOAD_TEST_CLIENTS) clients, $(LOAD_TEST_DURATION)s)...$(NC)"
	@LOAD_TEST_CLIENTS=$(LOAD_TEST_CLIENTS) \
	 LOAD_TEST_DURATION=$(LOAD_TEST_DURATION) \
	 ./run-load-tests.sh
	@echo "$(GREEN)Load tests completed!$(NC)"

reports: ## Generate test reports from existing results
	@echo "$(BLUE)Generating test reports...$(NC)"
	@./generate-test-report.sh
	@echo "$(GREEN)Test reports generated!$(NC)"

# Docker Compose targets
docker-test: ## Run tests using Docker Compose
	@echo "$(BLUE)Running tests with Docker Compose...$(NC)"
	@$(DOCKER_COMPOSE) up --build --abort-on-container-exit
	@echo "$(GREEN)Docker tests completed!$(NC)"

docker-quick: ## Run quick tests using Docker Compose
	@echo "$(BLUE)Running quick tests with Docker Compose...$(NC)"
	@$(DOCKER_COMPOSE) up integration-tests database-tests
	@echo "$(GREEN)Docker quick tests completed!$(NC)"

docker-load: ## Run load tests using Docker Compose
	@echo "$(BLUE)Running load tests with Docker Compose...$(NC)"
	@$(DOCKER_COMPOSE) --profile load-testing up
	@echo "$(GREEN)Docker load tests completed!$(NC)"

docker-network: ## Run network tests using Docker Compose
	@echo "$(BLUE)Running network tests with Docker Compose...$(NC)"
	@$(DOCKER_COMPOSE) --profile network-testing up
	@echo "$(GREEN)Docker network tests completed!$(NC)"

docker-reports: ## Generate reports using Docker Compose
	@echo "$(BLUE)Generating reports with Docker Compose...$(NC)"
	@$(DOCKER_COMPOSE) --profile reporting up
	@echo "$(GREEN)Docker reports completed!$(NC)"

# Utility targets
setup: ## Setup test environment and check prerequisites
	@echo "$(BLUE)Setting up test environment...$(NC)"
	@mkdir -p $(RESULTS_DIR)
	@chmod +x *.sh 2>/dev/null || true
	@echo "$(GREEN)Test environment ready$(NC)"

check: ## Check test prerequisites
	@echo "$(BLUE)Checking test prerequisites...$(NC)"
	@command -v mysql >/dev/null 2>&1 || { echo "$(RED)mysql client not found$(NC)"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(RED)python3 not found$(NC)"; exit 1; }
	@command -v nc >/dev/null 2>&1 || { echo "$(RED)netcat not found$(NC)"; exit 1; }
	@python3 -c "import socket, struct, threading" 2>/dev/null || { echo "$(RED)Required Python modules missing$(NC)"; exit 1; }
	@echo "$(GREEN)All prerequisites satisfied$(NC)"

status: ## Show current test status and results
	@echo "$(BLUE)Test Status Summary$(NC)"
	@echo "==================="
	@if [ -d "$(RESULTS_DIR)" ]; then \
		echo "Results directory: $(RESULTS_DIR)"; \
		echo "Available reports:"; \
		ls -la $(RESULTS_DIR)/*.json $(RESULTS_DIR)/*.html $(RESULTS_DIR)/*.txt 2>/dev/null || echo "  No reports found"; \
	else \
		echo "No results directory found - tests haven't been run yet"; \
	fi

logs: ## Show recent test logs
	@echo "$(BLUE)Recent Test Logs$(NC)"
	@echo "================"
	@if [ -f "$(RESULTS_DIR)/test_execution.log" ]; then \
		echo "Last execution log:"; \
		tail -20 "$(RESULTS_DIR)/test_execution.log"; \
	else \
		echo "No execution log found"; \
	fi

clean: ## Clean up test results and temporary files
	@echo "$(BLUE)Cleaning up test environment...$(NC)"
	@rm -rf $(RESULTS_DIR)
	@rm -f *.tmp *.log 2>/dev/null || true
	@docker system prune -f --filter "label=project=dhcp-tests" 2>/dev/null || true
	@echo "$(GREEN)Cleanup completed$(NC)"

clean-docker: ## Clean up Docker containers and images
	@echo "$(BLUE)Cleaning up Docker resources...$(NC)"
	@$(DOCKER_COMPOSE) down -v --remove-orphans 2>/dev/null || true
	@docker image prune -f --filter "label=project=dhcp-tests" 2>/dev/null || true
	@echo "$(GREEN)Docker cleanup completed$(NC)"

# Development targets
dev-setup: check setup ## Setup development environment for tests
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@pip3 install --user pytest pymysql scapy psutil 2>/dev/null || echo "$(YELLOW)Some Python packages may not be available$(NC)"
	@echo "$(GREEN)Development setup completed$(NC)"

validate: check ## Validate test scripts and configuration
	@echo "$(BLUE)Validating test scripts...$(NC)"
	@for script in *.sh; do \
		if [ -f "$$script" ]; then \
			echo "Checking $$script..."; \
			bash -n "$$script" || { echo "$(RED)Syntax error in $$script$(NC)"; exit 1; }; \
		fi; \
	done
	@echo "$(GREEN)All test scripts are valid$(NC)"

# Performance testing targets
stress: setup ## Run extended stress testing
	@echo "$(BLUE)Running stress tests...$(NC)"
	@LOAD_TEST_CLIENTS=100 \
	 LOAD_TEST_DURATION=300 \
	 ./run-load-tests.sh
	@echo "$(GREEN)Stress tests completed!$(NC)"

benchmark: setup ## Run performance benchmarks
	@echo "$(BLUE)Running performance benchmarks...$(NC)"
	@for clients in 10 25 50 100; do \
		echo "Testing with $$clients clients..."; \
		LOAD_TEST_CLIENTS=$$clients LOAD_TEST_DURATION=60 ./run-load-tests.sh; \
	done
	@echo "$(GREEN)Benchmarks completed!$(NC)"

# CI/CD targets
ci: check quick reports ## CI-friendly test run (quick tests + reports)
	@echo "$(GREEN)CI test run completed$(NC)"

ci-full: check test reports ## Full CI test run
	@echo "$(GREEN)Full CI test run completed$(NC)"

# Information targets
info: ## Display test suite information
	@echo "$(BLUE)DHCP SQL Server Integration Test Suite$(NC)"
	@echo "======================================"
	@echo "Version: 1.0"
	@echo "Test Directory: $(TEST_DIR)"
	@echo "Results Directory: $(RESULTS_DIR)"
	@echo ""
	@echo "Test Scripts:"
	@ls -1 *.sh 2>/dev/null | sed 's/^/  /'
	@echo ""
	@echo "Configuration Files:"
	@ls -1 configs/ 2>/dev/null | sed 's/^/  /' || echo "  No config files found"

version: ## Show version information
	@echo "DHCP SQL Server Integration Test Suite v1.0"
	@echo "Compatible with DHCP SQL Server v0.9.9+"
	@echo "Last Updated: December 2024"
