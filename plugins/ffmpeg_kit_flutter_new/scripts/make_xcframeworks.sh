#!/bin/bash
#
# Convert the prebuilt fat FFmpegKit iOS *.framework bundles into *.xcframework
# bundles that expose a NATIVE arm64 iOS-simulator slice. This lets the plugin
# be consumed via Swift Package Manager (binaryTarget only accepts .xcframework)
# AND run on Apple Silicon iOS simulators (Xcode 26 / iOS 26+).
#
# Usage: make_xcframeworks.sh <input_frameworks_dir> <output_dir>
#
# The upstream fat frameworks pack three slices into a single Mach-O:
#   x86_64  -> iOS simulator (LC_BUILD_VERSION platform IOSSIMULATOR / 7)
#   arm64   -> iOS device    (LC_BUILD_VERSION platform IOS / 2)
#   arm64e  -> iOS device    (LC_BUILD_VERSION platform IOS / 2)
#
# A single fat framework cannot hold both a device-arm64 and a simulator-arm64
# slice (identical CPU type), which is why arm64 historically had to be excluded
# for the simulator. We split each framework into two xcframework slices:
#   ios-arm64                   (device, thinned arm64, platform untouched)
#   ios-arm64_x86_64-simulator  (simulator: x86_64 + arm64 retagged via vtool)
#
# The arm64 simulator slice is produced by retagging the device arm64 slice's
# LC_BUILD_VERSION from iOS (2) to iOS-Simulator (7). FFmpeg/FFmpegKit is plain
# C / Objective-C with no platform-conditional linkage, so the machine code is
# identical and the retagged slice runs natively on Apple Silicon simulators.
# (Same technique shipped by upstream ffmpeg_kit_flutter_new >= 4.3.x.)
# Verify with `lipo -info` and `vtool -arch arm64 -show-build`.
set -euo pipefail

SRC_DIR="${1:?input frameworks dir required}"
OUT_DIR="${2:?output dir required}"

LIBS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

mkdir -p "$OUT_DIR"

# Trim each upstream framework bundle down to what the plugin actually ships:
# the binary, its Info.plist and (for the umbrella ffmpegkit framework only) the
# public Headers + module map. The per-library license texts are redundant with
# the plugin-root LICENSE/LICENSE.GPLv3 and the libav* headers are unused (the
# plugin imports only the ffmpegkit module), so they are dropped.
prune_bundle() {
  local fw_dir="$1" lib="$2"
  rm -rf "$fw_dir/_CodeSignature" "$fw_dir/SOURCE" "$fw_dir/strip-frameworks.sh"
  rm -f "$fw_dir"/LICENSE "$fw_dir"/LICENSE.*
  if [ "$lib" != "ffmpegkit" ]; then
    rm -rf "$fw_dir/Headers" "$fw_dir/Modules"
  fi
}

for lib in "${LIBS[@]}"; do
  src="$SRC_DIR/$lib.framework"
  out="$OUT_DIR/$lib.xcframework"
  [ -d "$src" ] || { echo "error: missing $src" >&2; exit 1; }

  bin="$src/$lib"
  archs="$(lipo -archs "$bin")"

  # Mirror the device deployment target / sdk onto the retagged simulator slice.
  minos="$(otool -l -arch arm64 "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
  sdk="$(otool -l -arch arm64 "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/sdk/{print $2; exit}')"
  [ -n "$minos" ] || minos="14.0"
  [ -n "$sdk" ] || sdk="$minos"

  tmp="$(mktemp -d)"
  mkdir -p "$tmp/device" "$tmp/sim"
  cp -R "$src" "$tmp/device/$lib.framework"
  cp -R "$src" "$tmp/sim/$lib.framework"
  prune_bundle "$tmp/device/$lib.framework" "$lib"
  prune_bundle "$tmp/sim/$lib.framework" "$lib"

  # --- Device slice: arm64 (platform iOS, untouched) ---
  lipo "$bin" -thin arm64 -output "$tmp/device/$lib.framework/$lib"

  # The upstream fat frameworks list both platforms in CFBundleSupportedPlatforms,
  # which App Store Connect rejects (ITMS error 91177). Each slice must declare
  # exactly the one platform it targets.
  plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' \
    "$tmp/device/$lib.framework/Info.plist"
  plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' \
    "$tmp/sim/$lib.framework/Info.plist"

  # --- Simulator slice: x86_64 + arm64 retagged iOS (2) -> iOS-Simulator (7) ---
  sim_args=()
  if echo "$archs" | tr ' ' '\n' | grep -qx x86_64; then
    lipo "$bin" -thin x86_64 -output "$tmp/x86_64"
    sim_args+=("$tmp/x86_64")
  fi
  lipo "$bin" -thin arm64 -output "$tmp/arm64-dev"
  vtool -arch arm64 -set-build-version 7 "$minos" "$sdk" -replace \
    -output "$tmp/arm64-sim" "$tmp/arm64-dev"
  sim_args+=("$tmp/arm64-sim")
  lipo -create "${sim_args[@]}" -output "$tmp/sim/$lib.framework/$lib"

  rm -rf "$out"
  xcodebuild -create-xcframework \
    -framework "$tmp/device/$lib.framework" \
    -framework "$tmp/sim/$lib.framework" \
    -output "$out"
  rm -rf "$tmp"

  # bitcode_strip/vtool invalidate the embedded signatures, so ad-hoc sign the
  # final bundles (Xcode re-signs with the real identity at embed time).
  for fw in "$out"/*/"$lib.framework"; do
    codesign --force --sign - "$fw"
  done
  echo "created $out"
done
