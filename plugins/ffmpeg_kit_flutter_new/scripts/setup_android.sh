#!/bin/bash

# Download Android AAR
ANDROID_URL="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/7.0/ffmpeg-kit-full-gpl-7.0.aar"
mkdir -p libs
curl -L $ANDROID_URL -o libs/com.arthenica.ffmpegkit-flutter-7.0.aar