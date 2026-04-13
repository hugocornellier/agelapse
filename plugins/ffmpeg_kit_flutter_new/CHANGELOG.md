## 4.1.0

* Fixed the FFmpeg 8.0 compatibility issue across all platforms. The problem was that `all_channel_counts` was being set AFTER the filter was created, but FFmpeg 8.0 requires it to be set DURING filter creation.

## 4.0.0

* FFmpeg `v8.0.0` with [all the sweet perks](https://ffmpeg.org/index.html#news)

## 3.2.0

* Upgraded `freetype` from **2.13.0** to **2.13.3**
* Upgraded `harfbuzz` from **8.0.1** to **11.3.3**
* Upgraded `fontconfig` from **2.16.2** to 2.17.1
* Added support for `harfbuzz` library in order to support `drawtext` filter
* Fixed missing `libunibreak` for `libass.sh`

## 3.1.0

* Updated README.md with new package links
* Uploaded new binary with Kotlin 1.8.22
* Downgraded required Kotlin version in `example` project to 1.8.22
* Formatted code

## 3.0.2

* Updated README.md with new package links

## 3.0.1

* Updated README.md with link to Minimal-GPL

## 3.0.0

* FFmpeg `v7.1.1`
* Multiple upgrade of internal libraries:
    - `Nettle` - from `3.8.2` to `3.10.2`
    - `SDL` from `2.0.0` to `3.2.16`
    - `Libxml2` from `2.11.4` to `2.14.0`
    - `SRT` from `1.5.2` to `1.5.4`
    - `Leptonica` from `1.83.1` to `1.85.0`
    - `GnuTLS` from `3.7.9` to `3.8.9`
* Cleaned up iOS and Macos .podspec code
* Bumped Kotlin version to 2.2.0
* Fixed iOS and MacOS dowload scripts and added Videotoolbox support
* New Android Full-GPL Maven Central dependency
* Got rid of obsolete `ffmpeg_kit_flutter_android` package
* Updated `example` project with Hardware, Software and Videotoolbox encoding commands

## 2.0.0

* Uploaded updated Android .aar, compatible with Google 16 KB requirement
* Updated `setup_ios.sh` script
* Removed resource shrinking for Android
* Updated `setup_ios.sh` script
* Updated `setup_android.sh` script to include latest FFmpeg 7.0 kit
* Upgraded `ffmpeg_kit_flutter_android` to 1.7.0
* Merged @nischhalcodetrade fix for .aar post processing

## 1.6.1

* Removed manual packaging of prebuilt dependencies for Android
* Cleaned up unnecessary logs

## 1.6.0

* Added new seamless Android .aar support

## 1.5.0

* Added MacOS support by directly downloading and unpacking frameworks

## 1.4.1

* Updated README.md

## 1.4.0

* Added build.bat jni
* Updated Gradle script in order to be able to download and unpack .aar on Windows.

## 1.3.0

* Moved from FFmpeg `http` to `full_gpl` for Android
* Added downloading and unpacking of 6.0.2 `full-gpl` .aar

## 1.2.1

* Added displaying of Android platform to pub.dev
* Fixed static analysis issues

## 1.2.0

* New example project
* Resurrected Android by creating new `ffmpeg_kit_flutter_android` library with `com.arthenica:ffmpeg-kit-https:6.0-2.LTS` implementation
* iOS deployment target is increased to 14.0
* Upgraded plugin_platform_interface version

## 1.1.0

* Moved from `https` to `full-gpl` binding for MacOS
* Upgraded Flutter and Dart versions

## 1.0.0

* Initial release
* Fixed Android and MacOS bindings
* Upgraded FFmpegKitFlutterPlugin.java to work with Flutter 3.29