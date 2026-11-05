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
RUN_PID=""
TAIL_PID=""
stop_background() {
  kill "$LOGCAT_PID" ${RUN_PID:+"$RUN_PID"} ${TAIL_PID:+"$TAIL_PID"} 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
}
trap stop_background EXIT

# A suite that hangs must fail here, with logcat attached, instead of eating
# the job's whole 90 minute budget. Seen 2026-10-14 on the stable lane: the
# APK installed and the app never came up, 73 minutes of silence until the
# job timeout. Both suites together take about 30 minutes on the emulator.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-40m}"

# That hang has hit six times since August, 40 to 90 minutes each: after the
# install line, zero Dart output, with the app alive, its VM service listening
# and no crash in logcat. A healthy suite prints its first test line 3.7 s
# after the install. Suites themselves run 15+ minutes, so only startup gets
# this short limit. firebase/flutterfire retries the same hang in the same
# booted emulator and recovered 12 of 12.
START_LIMIT_SECONDS="${START_LIMIT_SECONDS:-300}"

# "00:00 +0: loading ..." comes before the install, so it does not count. Not
# grep -q at the end: it can SIGPIPE the first grep, which pipefail reads as no
# match.
test_started() {
  grep -aE '[0-9]+:[0-9]{2} \+[0-9]+' "$1" | grep -v ': loading ' > /dev/null
}

# Sets rc. Output goes to a file, not a pipe into tee, so a stray child holding
# the pipe cannot block us.
run_attempt() {
  local suite="$1" log="$2" installed_at="" killed=0
  : > "$log"
  timeout --foreground -k 60 "$SUITE_TIMEOUT" \
    flutter test "integration_test/${suite}.dart" \
    -d emulator-5554 --reporter expanded > "$log" 2>&1 &
  RUN_PID=$!
  tail -n +1 -f --pid="$RUN_PID" "$log" &
  TAIL_PID=$!
  while [ "$killed" -eq 0 ] && kill -0 "$RUN_PID" 2>/dev/null && ! test_started "$log"; do
    if [ -z "$installed_at" ] && grep -aq 'Installing build' "$log"; then
      installed_at=$SECONDS
    fi
    if [ -n "$installed_at" ] && [ $((SECONDS - installed_at)) -ge "$START_LIMIT_SECONDS" ]; then
      killed=1
      kill -TERM "$RUN_PID" 2>/dev/null || true
    else
      sleep 5
    fi
  done
  rc=0
  wait "$RUN_PID" || rc=$?
  wait "$TAIL_PID" || true
  RUN_PID=""
  TAIL_PID=""
  # Flutter may handle TERM and exit 0. A run we killed never counts as a pass.
  if [ "$killed" -eq 1 ] && [ "$rc" -eq 0 ]; then rc=143; fi
}

# Installed, then no test ever started: killed by the watchdog, or flutter gave
# up by itself (flutterfire also saw "Error connecting to the service protocol"
# fail this way). Test failures, an app death mid-suite and build failures are
# real results and must never match this.
launch_failed() {
  [ "$rc" -ne 0 ] && grep -aq 'Installing build' "$1" && ! test_started "$1"
}

status=0
run_suite() {
  local suite="$1"
  local log="$RESULTS_DIR/${suite}.log"
  run_attempt "$suite" "$log"
  if launch_failed "$log"; then
    echo "::warning::Android integration suite $suite started no test within ${START_LIMIT_SECONDS}s of installing, or failed before any test ran. Retrying once in the same emulator."
    timeout 30 adb -s emulator-5554 shell am force-stop com.hugocornellier.agelapse || true
    mv "$log" "$RESULTS_DIR/${suite}.attempt1.log"
    # Tells the workflow to keep this run's logcat even when the job ends green.
    : > "$RESULTS_DIR/launch-retried"
    run_attempt "$suite" "$log"
  fi
  if [ "$rc" -eq 0 ]; then
    echo "Android integration suite passed: $suite"
  elif launch_failed "$log"; then
    status=1
    echo "::error::Android integration suite failed to launch on both attempts: $suite"
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
