#!/bin/bash
# Pre-removal script for AgeLapse deb package
# Removes the wrapper script

set -e

WRAPPER_PATH="/usr/bin/agelapse"

# Remove the wrapper script if it exists
if [ -f "$WRAPPER_PATH" ]; then
    rm -f "$WRAPPER_PATH"
fi
