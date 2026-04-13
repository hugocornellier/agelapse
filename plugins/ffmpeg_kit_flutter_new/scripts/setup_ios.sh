#!/bin/bash

# Download and unzip iOS framework
IOS_URL="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/8.0.0-full-gpl/ffmpeg-kit-ios-full-gpl-8.0.0.zip"
mkdir -p Frameworks
curl -L $IOS_URL -o frameworks.zip
unzip -o frameworks.zip -d Frameworks
rm frameworks.zip

# Delete bitcode from all frameworks
xcrun bitcode_strip -r Frameworks/ffmpegkit.framework/ffmpegkit -o Frameworks/ffmpegkit.framework/ffmpegkit
xcrun bitcode_strip -r Frameworks/libavcodec.framework/libavcodec -o Frameworks/libavcodec.framework/libavcodec
xcrun bitcode_strip -r Frameworks/libavdevice.framework/libavdevice -o Frameworks/libavdevice.framework/libavdevice
xcrun bitcode_strip -r Frameworks/libavfilter.framework/libavfilter -o Frameworks/libavfilter.framework/libavfilter
xcrun bitcode_strip -r Frameworks/libavformat.framework/libavformat -o Frameworks/libavformat.framework/libavformat
xcrun bitcode_strip -r Frameworks/libavutil.framework/libavutil -o Frameworks/libavutil.framework/libavutil
xcrun bitcode_strip -r Frameworks/libswresample.framework/libswresample -o Frameworks/libswresample.framework/libswresample
xcrun bitcode_strip -r Frameworks/libswscale.framework/libswscale -o Frameworks/libswscale.framework/libswscale