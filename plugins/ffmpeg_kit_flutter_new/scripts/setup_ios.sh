#!/bin/bash
set -euo pipefail

# Download the upstream iOS fat frameworks and convert them into the
# .xcframeworks consumed by both the podspec and Package.swift.
# Run from the iOS pod root (the directory containing the podspec).
IOS_URL="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/8.0.0-full-gpl/ffmpeg-kit-ios-full-gpl-8.0.0.zip"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="ffmpeg_kit_flutter_new/Frameworks"
STAGING="$(mktemp -d)"

curl -L "$IOS_URL" -o "$STAGING/frameworks.zip"
unzip -o "$STAGING/frameworks.zip" -d "$STAGING/Frameworks"

# Delete bitcode from all frameworks before converting.
for lib in ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale; do
  xcrun bitcode_strip -r "$STAGING/Frameworks/$lib.framework/$lib" -o "$STAGING/Frameworks/$lib.framework/$lib"
done

# Generate ffmpeg_kit_flutter_new/Frameworks/*.xcframework (device + simulator slices).
"$SCRIPT_DIR/make_xcframeworks.sh" "$STAGING/Frameworks" "$OUT_DIR"

rm -rf "$STAGING"
