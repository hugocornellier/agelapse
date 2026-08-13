#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="build/test-results/android"
mkdir -p "$RESULTS_DIR"

status=0
run_suite() {
  local suite="$1"
  local log="$RESULTS_DIR/${suite}.log"
  if flutter test "integration_test/${suite}.dart" \
    -d emulator-5554 --reporter expanded 2>&1 | tee "$log"; then
    echo "Android integration suite passed: $suite"
  else
    status=1
    echo "::error::Android integration suite failed: $suite"
  fi
}

run_suite mobile_fast
run_suite mobile_video
exit "$status"
