# FFmpeg Android Minimal AAR — Research Notes

## Summary

Investigation into reducing the Android FFmpegKit AAR from 108MB to ~12MB by building FFmpeg with `--disable-everything` and only enabling the codecs/filters AgeLapse actually uses. The minimal FFmpeg `.so` files build successfully, but integrating them requires a compatible `libffmpegkit.so` JNI wrapper — which proved to be a multi-day porting effort.

**Status: Deferred.** The CI workflow is ready and the minimal FFmpeg builds work. The blocker is `libffmpegkit.so` ABI compatibility.

## What We Built

### CI Workflow (`build-minimal-aar.yml` in ffmpeg_kit_flutter fork)

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

## The Blocker: `libffmpegkit.so`

### What It Is

`libffmpegkit.so` is the JNI wrapper that bridges Java/Kotlin (FFmpegKit Flutter plugin) to FFmpeg's C API. It contains:
- JNI method implementations (`Java_com_antonkarpenko_ffmpegkit_*`)
- Vendored `fftools` source code (FFmpeg's command-line tool logic)
- SAF (Storage Access Framework) integration for Android

### Why It Can't Use Our Minimal FFmpeg

The pre-built `libffmpegkit.so` in the Maven AAR (`com.antonkarpenko:ffmpeg-kit-full-gpl:2.1.0`) was compiled against the **full** FFmpeg. When paired with our minimal `.so` files, video encoding fails because:

1. The wrapper's vendored `fftools` code references internal FFmpeg symbols that `--disable-everything` removes
2. The wrapper was compiled against a **patched** FFmpeg 8 fork (not vanilla) — the patches aren't public

### Why We Can't Easily Rebuild It

The upstream `arthenica/ffmpeg-kit` wrapper source is for **FFmpeg 6.x LTS**. Compiling it against FFmpeg 8.x (n8.0.1) requires porting ~50+ API changes:

#### Category 1: Removed AVFrame Members (mechanical, sed-patchable)
| Old (FFmpeg 6) | New (FFmpeg 8) |
|---|---|
| `frame->key_frame` | `(frame->flags & AV_FRAME_FLAG_KEY)` |
| `frame->top_field_first` | `(frame->flags & AV_FRAME_FLAG_TOP_FIELD_FIRST)` |
| `frame->interlaced_frame` | `(frame->flags & AV_FRAME_FLAG_INTERLACED)` |
| `frame->pkt_duration` | `frame->duration` |
| `frame->pkt_pos` | removed (tracked separately) |
| `frame->pkt_size` | removed (tracked separately) |

#### Category 2: Removed AVCodecContext Members
| Old | New |
|---|---|
| `dec_ctx->ticks_per_frame` | removed entirely, use `2` or `repeat_pict + 2` |

#### Category 3: AVStream Side Data API (structural, NOT sed-patchable)
| Old | New |
|---|---|
| `st->side_data` / `st->nb_side_data` | `st->codecpar->coded_side_data` / `nb_coded_side_data` |
| `av_stream_new_side_data()` | `av_packet_side_data_new()` |
| `av_stream_get_side_data()` | `av_packet_side_data_get()` |

#### Category 4: FFmpegKit-Specific Patches (not in vanilla FFmpeg)
| Function | Purpose |
|---|---|
| `av_set_saf_open()` | Android SAF file access callbacks |
| `av_set_saf_close()` | Android SAF file close callbacks |
| `FFMPEG_KIT_BUILD_DATE` | Build-time macro |

#### Category 5: HDR Vivid Struct Changes
| Old | Status |
|---|---|
| `AVHDRVividColorToneMappingParams.three_Spline_TH_mode` | renamed/removed in FFmpeg 8 |
| `AVHDRVividColorToneMappingParams.three_Spline_TH_enable_MB` | renamed/removed |
| `AVHDRVividColorToneMappingParams.three_Spline_TH_enable` | renamed/removed |

#### Category 6: fftools Architecture Refactor
FFmpeg 8 split the monolithic `ffmpeg.c` into multiple files:
- `ffmpeg.c` → `ffmpeg.c` + `ffmpeg_dec.c` + `ffmpeg_enc.c` + `ffmpeg_sched.c`

The wrapper's `fftools_ffmpeg.c` contains code from ALL of these merged into one file from FFmpeg 6's structure. A full port would require understanding which code moved where.

### Estimated Effort

| Approach | Effort | Risk |
|---|---|---|
| Contact antonkarpenko for patched source | 0 (if they share) | May not respond |
| Port upstream wrapper to FFmpeg 8 | 3-5 days | Medium — many structural changes |
| Use FFmpeg 8's own fftools + add JNI glue | 2-3 days | Medium — different architecture |
| Accept full-gpl AAR (current) | 0 | None — already working |

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
