#!/usr/bin/env bash
# Builds integration_test/android_bulk_import_test.dart as an Android
# instrumentation test and runs it on a Firebase Test Lab device.
# See tool/testlab/README.md.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  tool/testlab/bulk_import.sh build CONFIG
  tool/testlab/bulk_import.sh run CONFIG MODEL VERSION ZIP

CONFIG  compile: date stamps on, and the run must end with every photo
                 done and a video compiled (use a small zip).
        bulk:    stabilize as far as 40 minutes allow (use a large zip).
        headless: like bulk, but without the app's UI: the test drives the
                 stabilization service directly, to tell UI memory from
                 pipeline memory.
        probe:   android_memory_probe_test.dart instead: the pipeline
                 layer by layer on distinct photos, with a forced GC and
                 Dart memory figures before each snapshot, to find which
                 layer holds memory (a zip of 30 or more photos will do).
MODEL   a Test Lab model id, VERSION its Android API level: for example
        akita 35 (Pixel 8a, Android 15) or MediumPhone.arm 35 (virtual).
EXTRA_DEFINES  (environment) more Dart defines for the build, for example
        EXTRA_DEFINES="PROBE_ROUNDS=5 PROBE_SERVICE_ROUNDS=60".
ZIP     a zip made by make_bulk_zip.py, as a local path or gs:// URL.
EOF
  exit 2
}

root="$(git rev-parse --show-toplevel)"

target_for() {
  case "$1" in
    probe) echo "$root/integration_test/android_memory_probe_test.dart" ;;
    *) echo "$root/integration_test/android_bulk_import_test.dart" ;;
  esac
}
project="${FIREBASE_PROJECT_ID:-flutter-litert}"
bucket="${TEST_LAB_BUCKET:-test-lab-7yqvc8ruj90y2-k9u7wfunxj2sa}"

defines_for() {
  case "$1" in
    compile) echo "BULK_DATE_STAMPS=true BULK_EXPECT_VIDEO=true BULK_BUDGET_MINUTES=40" ;;
    bulk) echo "BULK_BUDGET_MINUTES=40" ;;
    headless) echo "BULK_HEADLESS=true BULK_BUDGET_MINUTES=40" ;;
    probe) echo "PROBE_ROUNDS=10" ;;
    *) usage ;;
  esac
}

apks() { echo "$root/build/testlab/$1"; }

build() {
  local config="$1" encoded="" define target
  target="$(target_for "$config")"
  for define in $(defines_for "$config") ${EXTRA_DEFINES:-}; do
    encoded="${encoded:+$encoded,}$(printf '%s' "$define" | base64)"
  done
  cd "$root"
  flutter build apk --config-only --debug --target "$target" \
    --target-platform android-arm64
  (
    cd android
    ./gradlew app:assembleAndroidTest -Pagelapse.testLabAbi=arm64-v8a
    ./gradlew app:assembleDebug -Ptarget="$target" \
      -Ptarget-platform=android-arm64 -Pagelapse.testLabAbi=arm64-v8a \
      -Pdart-defines="$encoded"
  )
  mkdir -p "$(apks "$config")"
  cp build/app/outputs/apk/debug/app-debug.apk "$(apks "$config")/app.apk"
  cp build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
    "$(apks "$config")/test.apk"
  echo "Built $(apks "$config")"
}

run() {
  local config="$1" model="$2" version="$3" zip="$4" status=0
  defines_for "$config" > /dev/null
  local dir
  dir="agelapse-bulk-$config-$model-$version-$(date +%Y%m%d-%H%M%S)"
  gcloud firebase test android run --project "$project" \
    --type instrumentation \
    --app "$(apks "$config")/app.apk" --test "$(apks "$config")/test.apk" \
    --device "model=$model,version=$version,locale=en,orientation=portrait" \
    --other-files "/sdcard/agelapse_bulk_import.zip=$zip" \
    --timeout 45m --results-history-name agelapse-bulk-import \
    --results-bucket "$bucket" --results-dir "$dir" || status=$?

  # The test's progress lines, and any crash, are in the device's logcat.
  local out="$root/build/testlab/results/$dir"
  mkdir -p "$out"
  gcloud storage cp "gs://$bucket/$dir/$model-$version-en-portrait/logcat" \
    "$out/logcat" --project "$project" || true
  echo "Logcat: $out/logcat"
  grep -o 'AGELAPSE_BULK .*' "$out/logcat" | tail -n 30 || true
  return "$status"
}

case "${1:-}" in
  build) [[ $# -eq 2 ]] || usage; build "$2" ;;
  run) [[ $# -eq 5 ]] || usage; run "$2" "$3" "$4" "$5" ;;
  *) usage ;;
esac
