#!/bin/bash
#
# Convert the prebuilt fat FFmpegKit iOS *.framework bundles into *.xcframework
# bundles so the plugin can be consumed via Swift Package Manager, whose
# binaryTarget only accepts .xcframework (not a fat .framework).
#
# Usage: make_xcframeworks.sh <input_frameworks_dir> <output_dir>
#
# The fat frameworks ship arm64 (device, Mach-O platform iOS) plus x86_64
# (simulator, Mach-O platform iOS-Simulator). They are thinned into a device
# slice (ios-arm64) and a simulator slice (ios-x86_64-simulator). There is no
# arm64 simulator slice upstream, so the iOS Simulator on Apple Silicon is
# unsupported (same as the fat framework was under CocoaPods).
set -euo pipefail

SRC_DIR="${1:?input frameworks dir required}"
OUT_DIR="${2:?output dir required}"

LIBS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

mkdir -p "$OUT_DIR"

for lib in "${LIBS[@]}"; do
  src="$SRC_DIR/$lib.framework"
  out="$OUT_DIR/$lib.xcframework"
  if [ ! -d "$src" ]; then
    echo "error: missing $src" >&2
    exit 1
  fi
  rm -rf "$out"
  tmp="$(mktemp -d)"
  # Keep the bundle named "<lib>.framework" in each slice: xcodebuild derives
  # the expected binary name from the framework directory name.
  mkdir -p "$tmp/device" "$tmp/sim"
  cp -R "$src" "$tmp/device/$lib.framework"
  cp -R "$src" "$tmp/sim/$lib.framework"
  lipo "$src/$lib" -thin arm64  -output "$tmp/device/$lib.framework/$lib"
  lipo "$src/$lib" -thin x86_64 -output "$tmp/sim/$lib.framework/$lib"
  rm -rf "$tmp/device/$lib.framework/_CodeSignature" "$tmp/sim/$lib.framework/_CodeSignature"
  xcodebuild -create-xcframework \
    -framework "$tmp/device/$lib.framework" \
    -framework "$tmp/sim/$lib.framework" \
    -output "$out"
  rm -rf "$tmp"
  echo "created $out"
done
