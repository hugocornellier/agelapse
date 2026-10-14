#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="build/test-results/android"
mkdir -p "$RESULTS_DIR"

# Keep the device log for the whole run. When the app dies mid-suite (seen
# three times so far, each time during a heavy encode in mobile_video),
# flutter test only reports "did not complete"; the crash, or the low-memory
# kill, is in logcat. The file is uploaded with the test logs on failure.
adb logcat -c || true
adb logcat -v threadtime -b all > "$RESULTS_DIR/logcat.txt" 2>&1 &
LOGCAT_PID=$!
stop_logcat() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
}
trap stop_logcat EXIT

# A suite that hangs must fail here, with logcat attached, instead of eating
# the job's whole 90 minute budget. Seen 2026-10-14 on the stable lane: the
# APK installed and the app never came up, 73 minutes of silence until the
# job timeout. Both suites together take about 30 minutes on the emulator.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-40m}"

status=0
run_suite() {
  local suite="$1"
  local log="$RESULTS_DIR/${suite}.log"
  set +e
  timeout --foreground -k 60 "$SUITE_TIMEOUT" \
    flutter test "integration_test/${suite}.dart" \
    -d emulator-5554 --reporter expanded 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "Android integration suite passed: $suite"
  elif [ "$rc" -eq 124 ]; then
    status=1
    echo "::error::Android integration suite timed out after $SUITE_TIMEOUT: $suite"
  else
    status=1
    echo "::error::Android integration suite failed: $suite"
  fi
}

run_suite mobile_fast
run_suite mobile_video
exit "$status"
