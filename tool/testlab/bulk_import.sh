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
MODEL   a Test Lab model id, VERSION its Android API level: for example
        akita 35 (Pixel 8a, Android 15) or MediumPhone.arm 35 (virtual).
ZIP     a zip made by make_bulk_zip.py, as a local path or gs:// URL.
EOF
  exit 2
}

root="$(git rev-parse --show-toplevel)"
target="$root/integration_test/android_bulk_import_test.dart"
project="${FIREBASE_PROJECT_ID:-flutter-litert}"
bucket="${TEST_LAB_BUCKET:-test-lab-7yqvc8ruj90y2-k9u7wfunxj2sa}"

defines_for() {
  case "$1" in
    compile) echo "BULK_DATE_STAMPS=true BULK_EXPECT_VIDEO=true BULK_BUDGET_MINUTES=40" ;;
    bulk) echo "BULK_BUDGET_MINUTES=40" ;;
    *) usage ;;
  esac
}

apks() { echo "$root/build/testlab/$1"; }

build() {
  local config="$1" encoded="" define
  for define in $(defines_for "$config"); do
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
