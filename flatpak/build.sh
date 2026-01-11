#!/bin/bash
set -e

# AgeLapse Flatpak Build Script
# Run this on Linux after building Flutter

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== AgeLapse Flatpak Builder ==="
echo ""

# Check if running on Linux
if [[ "$(uname)" != "Linux" ]]; then
    echo "Error: This script must be run on Linux"
    exit 1
fi

# Check for flatpak-builder
if ! command -v flatpak-builder &> /dev/null; then
    echo "Error: flatpak-builder not found. Install with:"
    echo "  sudo apt install flatpak flatpak-builder"
    exit 1
fi

# Check for Flutter bundle
BUNDLE_PATH="$PROJECT_ROOT/build/linux/x64/release/bundle"
if [[ ! -d "$BUNDLE_PATH" ]]; then
    echo "Error: Flutter bundle not found at $BUNDLE_PATH"
    echo ""
    echo "Build the Flutter app first:"
    echo "  cd $PROJECT_ROOT"
    echo "  flutter build linux --release"
    exit 1
fi

# Copy bundle to flatpak directory
echo "Copying Flutter bundle..."
rm -rf "$SCRIPT_DIR/bundle"
cp -r "$BUNDLE_PATH" "$SCRIPT_DIR/bundle"
echo "  Done."

# Build the Flatpak
echo ""
echo "Building Flatpak..."
cd "$SCRIPT_DIR"
flatpak-builder --force-clean --ccache build-dir com.hugocornellier.agelapse.yaml

echo ""
echo "=== Build Complete ==="
echo ""
echo "To test locally:"
echo "  flatpak-builder --run build-dir com.hugocornellier.agelapse.yaml agelapse"
echo ""
echo "To install locally:"
echo "  flatpak-builder --user --install --force-clean build-dir com.hugocornellier.agelapse.yaml"
echo "  flatpak run com.hugocornellier.agelapse"
echo ""
echo "To create distributable .flatpak file:"
echo "  flatpak-builder --repo=repo --force-clean build-dir com.hugocornellier.agelapse.yaml"
echo "  flatpak build-bundle repo agelapse.flatpak com.hugocornellier.agelapse"
