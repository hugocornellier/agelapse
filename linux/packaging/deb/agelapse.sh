#!/bin/bash
# AgeLapse wrapper script for Debian/Ubuntu packages
# Sets up library paths and launches the application

INSTALL_DIR="/opt/agelapse"

# Add bundled libraries to library path (takes priority)
if [ -d "$INSTALL_DIR/lib" ]; then
    export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

# Add common system library paths as fallback
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/lib/aarch64-linux-gnu"

# Launch the actual application
exec "$INSTALL_DIR/agelapse" "$@"
