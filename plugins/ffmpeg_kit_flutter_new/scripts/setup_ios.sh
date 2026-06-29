#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# FULL-UPSTREAM fallback fetch. This is NOT how the committed binaries are made.
#
# The Frameworks/*.xcframework vendored in this plugin are a CUSTOM MINIMAL
# FFmpeg build (~13 MB total: only the encoders/decoders/muxers/filters
# AgeLapse uses -- h264/hevc_videotoolbox, prores_ks, png, mp4/mov, concat/
# image2, a handful of filters; see the configure string embedded in each
# binary). This script instead downloads the FULL-GPL upstream (~115 MB of fat
# frameworks) and exists only as a fallback to produce a working (but much
# larger) plugin if the vendored Frameworks dir is ever missing. Do NOT run it
# expecting to reproduce the minimal vendored binaries.
#
# make_xcframeworks.sh (called below) splits each fat framework into a device
# slice (ios-arm64) plus a real arm64+x86_64 simulator slice
# (ios-arm64_x86_64-simulator), so either path supports Apple Silicon
# simulators. Run from the iOS pod root (the directory containing the podspec).
# ---------------------------------------------------------------------------
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
