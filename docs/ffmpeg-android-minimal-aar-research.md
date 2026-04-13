# FFmpeg Android Minimal AAR — Research Notes

## Summary

Investigation into reducing the Android FFmpegKit AAR from 108MB to ~12MB by building FFmpeg with `--disable-everything` and only enabling the codecs/filters AgeLapse actually uses.

**Status: Implementation complete.** The CI workflow (`build-ffmpeg-android.yml`) now builds FFmpeg 6.1.2 (n6.1.2) from source and compiles the JNI wrapper from the arthenica/ffmpeg-kit v6.0.LTS source — no pre-built wrapper required. The wrapper compiles cleanly against FFmpeg 6 with only minor patches (JNI name rename + SAF disable).

### Approach: FFmpeg 6 + arthenica v6.0.LTS wrapper

The prior blocker was that `libffmpegkit.so` from the Maven AAR was compiled against a patched FFmpeg 8 fork, and porting the wrapper to FFmpeg 8 required ~50+ structural API changes. The solution: build FFmpeg 6 instead, and compile the arthenica v6 wrapper source directly — it targets FFmpeg 6 and requires only two minimal patches:

1. **JNI rename**: `sed 's/arthenica/antonkarpenko/g'` on `ffmpegkit.c` and `ffmpegkit_abidetect.c` — matches the package name in `classes.jar`
2. **SAF disable**: `sed 's| av_set_saf|//av_set_saf|g'` on `ffmpegkit.c` — `av_set_saf_open/close` are FFmpegKit-specific patches not present in vanilla FFmpeg 6

Additional patch to FFmpeg source: `libavutil/log.c` gets `static int av_log_level` → `__thread int av_log_level` for thread-safe concurrent session support.

## What We Built

### CI Workflow (`build-ffmpeg-android.yml` in agelapse repo)

Successfully builds minimal FFmpeg for 3 Android ABIs (arm64-v8a, armeabi-v7a, x86_64):

```
FFmpeg configure flags:
--disable-everything --disable-doc --disable-programs --disable-autodetect
--enable-encoder=libx264 --enable-encoder=libvpx_vp9
--enable-decoder=png --enable-decoder=wrapped_avframe
--enable-muxer=mp4 --enable-muxer=webm --enable-muxer=matroska
--enable-demuxer=concat --enable-demuxer=image2
--enable-filter=split,format,scale,crop,gblur,overlay,colorchannelmixer,color,drawtext
--enable-libx264 --enable-libvpx --enable-libfreetype --enable-libharfbuzz
--enable-protocol=file --enable-indev=lavfi --enable-zlib
--enable-avdevice  # required: NativeLoader.java hard-loads libavdevice.so
```

### Size Results

| Library (arm64-v8a) | Full-GPL | Minimal | Reduction |
|---|---|---|---|
| libavcodec.so | 21.5 MB | 2.6 MB | 88% |
| libavfilter.so | 10.3 MB | 4.0 MB | 61% |
| libavformat.so | 7.9 MB | 393 KB | 95% |
| libavdevice.so | 55 KB | ~20 KB | 64% |
| **Total AAR** | **108 MB** | **~12 MB** | **89%** |
| **APK (arm64+armv7)** | **~512 MB** | **~370 MB** | **~28%** |

## The Former Blocker: `libffmpegkit.so` (now resolved)

### What It Is

`libffmpegkit.so` is the JNI wrapper that bridges Java/Kotlin (FFmpegKit Flutter plugin) to FFmpeg's C API. It contains:
- JNI method implementations (`Java_com_antonkarpenko_ffmpegkit_*`)
- Vendored `fftools` source code (FFmpeg's command-line tool logic)
- SAF (Storage Access Framework) integration for Android

### Why the Pre-Built Wrapper Couldn't Be Reused

The pre-built `libffmpegkit.so` in the Maven AAR (`com.antonkarpenko:ffmpeg-kit-full-gpl:2.1.0`) was compiled against a **patched FFmpeg 8 fork** (patches not public). Pairing it with our minimal `.so` files failed because the wrapper's vendored `fftools` code references internal FFmpeg symbols removed by `--disable-everything`.

### Why We Can't Port the Wrapper to FFmpeg 8

The upstream `arthenica/ffmpeg-kit` wrapper source targets **FFmpeg 6.x LTS**. Compiling it against FFmpeg 8.x (n8.0.1) requires porting ~50+ API changes across AVFrame members, AVStream side data API, fftools architecture refactor, and HDR Vivid struct changes. Estimated 3-5 days effort.

### Resolution: Build FFmpeg 6 + compile wrapper from source

Instead of porting the wrapper forward, we build **FFmpeg 6.1.2** and compile the arthenica v6.0.LTS wrapper source against it. The wrapper targets FFmpeg 6 natively — no porting needed. Required patches are minimal:

| Patch | Command | Reason |
|---|---|---|
| JNI class name rename | `sed 's/arthenica/antonkarpenko/g'` on `ffmpegkit.c`, `ffmpegkit_abidetect.c` | Package name in `classes.jar` uses `antonkarpenko` |
| SAF disable | `sed 's\| av_set_saf\|//av_set_saf\|g'` on `ffmpegkit.c` | `av_set_saf_*` are FFmpegKit-specific patches absent from vanilla FFmpeg |
| Thread-local log level | `sed 's/static int av_log_level/__thread int av_log_level/g'` on `libavutil/log.c` | Required for FFmpegKit's multi-session concurrent usage |

## What's Ready for Future Work

1. **CI workflow** (`build-minimal-aar.yml`) in the fork — successfully builds minimal FFmpeg `.so` files for all 3 ABIs
2. **FFmpeg 8 API migration patches** (partial) — sed-based patches for Categories 1-2 are written and tested
3. **AAR packaging pipeline** — downloads original AAR, replaces `.so` files, repackages with correct checksums
4. **Gradle integration research** — `exclusiveContent` in consuming app's `build.gradle.kts` forces local repo over Maven Central

## Key Findings

### NativeLoader.java Hard-Loads 7 Libraries
The AAR's `NativeLoader.java` calls `System.loadLibrary()` for: avutil, swscale, swresample, avcodec, avformat, avfilter, **avdevice**. All 7 must be present as `.so` files or the app crashes with `UnsatisfiedLinkError`. This is why `--enable-avdevice` is mandatory even though AgeLapse doesn't use any devices.

### Gradle Repository Shadowing Is Fragile
A Flutter plugin's `allprojects` block in its `build.gradle` does NOT propagate repositories to the consuming app. The consuming app must independently add the local Maven repo. `exclusiveContent` with `includeGroup`/`excludeGroup` is the correct mechanism but must be set up on BOTH sides.

### The Wrapper Uses 345+ FFmpeg Public API Symbols
All are from the stable public API (av_*, avformat_*, avcodec_*, etc.). `--disable-everything` doesn't remove these — it only removes codec/filter implementations. The ABI incompatibility comes from the vendored `fftools` code using INTERNAL APIs and struct members, not from the public API.

### Android x86/x86_64 Stripping
Adding `packaging { jniLibs { excludes += setOf("lib/x86_64/**", "lib/x86/**") } }` to the release build type in `android/app/build.gradle.kts` strips ~43MB of unused emulator-only native libs from release APKs. Debug builds keep all ABIs for emulator testing.

## References

- FFmpegKit source: https://github.com/arthenica/ffmpeg-kit
- FFmpeg 7 changelog (API removals): https://ffmpeg.org/index.html#news
- Flutter FFmpegKit fork: https://github.com/hugocornellier/ffmpeg_kit_flutter
- Maven artifact: `com.antonkarpenko:ffmpeg-kit-full-gpl:2.1.0`
