#!/bin/bash
# AgeLapse Flatpak wrapper script
# Sets up environment for FFmpeg extension and launches the app

# Add FFmpeg extension to PATH (mounted at /app/lib/ffmpeg by Flatpak)
if [ -d "/app/lib/ffmpeg/bin" ]; then
    export PATH="/app/lib/ffmpeg/bin:$PATH"
fi

# Add FFmpeg libraries to library path
if [ -d "/app/lib/ffmpeg/lib" ]; then
    export LD_LIBRARY_PATH="/app/lib/ffmpeg/lib:${LD_LIBRARY_PATH:-}"
fi

# Launch the actual application
exec /app/agelapse "$@"
