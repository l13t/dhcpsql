#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/integration/run-simple-tests.sh"
log_success "setup"
[[ $TESTS_PASSED == 0 ]]
run_test "success" "true"
if run_test "failure" "false"; then exit 1; fi
run_test "next test" "true"
[[ $TESTS_RUN == 3 && $TESTS_PASSED == 2 && $TESTS_FAILED == 1 ]]
