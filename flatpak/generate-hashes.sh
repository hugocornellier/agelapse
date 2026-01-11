#!/bin/bash
# Generate SHA256 hashes for Flathub manifest
# Run this after creating all the release artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== SHA256 Hashes for Flathub Manifest ==="
echo ""
echo "Copy these values into com.hugocornellier.agelapse.flathub.yaml"
echo ""

# Check for bundle tarball
if [ -f "$SCRIPT_DIR/agelapse-linux-bundle.tar.gz" ]; then
    echo "agelapse-linux-bundle.tar.gz:"
    sha256sum "$SCRIPT_DIR/agelapse-linux-bundle.tar.gz" | cut -d' ' -f1
    echo ""
else
    echo "agelapse-linux-bundle.tar.gz: NOT FOUND"
    echo "  Create with: cd build/linux/x64/release && tar -czvf agelapse-linux-bundle.tar.gz bundle/"
    echo ""
fi

echo "agelapse.sh:"
sha256sum "$SCRIPT_DIR/agelapse.sh" | cut -d' ' -f1
echo ""

echo "com.hugocornellier.agelapse.desktop:"
sha256sum "$SCRIPT_DIR/com.hugocornellier.agelapse.desktop" | cut -d' ' -f1
echo ""

echo "com.hugocornellier.agelapse.metainfo.xml:"
sha256sum "$SCRIPT_DIR/com.hugocornellier.agelapse.metainfo.xml" | cut -d' ' -f1
echo ""

echo "icons/256x256/agelapse.png:"
sha256sum "$SCRIPT_DIR/icons/256x256/agelapse.png" | cut -d' ' -f1
echo ""

echo "icons/128x128/agelapse.png:"
sha256sum "$SCRIPT_DIR/icons/128x128/agelapse.png" | cut -d' ' -f1
echo ""

echo "icons/64x64/agelapse.png:"
sha256sum "$SCRIPT_DIR/icons/64x64/agelapse.png" | cut -d' ' -f1
echo ""

echo "LICENSE:"
sha256sum "$SCRIPT_DIR/../LICENSE" | cut -d' ' -f1
echo ""

echo "=== Done ==="
