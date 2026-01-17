#!/bin/bash
# Post-installation script for AgeLapse deb package
# Creates wrapper script with proper library paths

set -e

INSTALL_DIR="/opt/agelapse"
WRAPPER_PATH="/usr/bin/agelapse"

# Create the wrapper script
cat > "$WRAPPER_PATH" << 'EOF'
#!/bin/bash
# AgeLapse wrapper script
# Sets up library paths and launches the application

INSTALL_DIR="/opt/agelapse"

# Add bundled libraries to library path (takes priority)
if [ -d "$INSTALL_DIR/lib" ]; then
    export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

# Launch the actual application
exec "$INSTALL_DIR/agelapse" "$@"
EOF

# Make the wrapper executable
chmod 755 "$WRAPPER_PATH"

echo "AgeLapse installed successfully. Run 'agelapse' to start."
