# FFmpeg Full Pipeline Integration Test Plan

## Goal

End-to-end integration tests that verify the **bundled FFmpeg binaries** can compile
videos across every supported codec, resolution, orientation, and background mode on
macOS and Windows. Each test: create frames → set DB settings → compile → verify
output → verify playback.

---

## 1. Bundled FFmpeg Binary Verification

### macOS Binary (`assets/ffmpeg/mac/ffmpeg`)
- **Size**: 5.5 MB, universal binary (arm64 + x86_64)
- **Version**: ffmpeg 8.0.1 built with Apple clang
- **Build config**: `--disable-everything` + selective enables
- **Encoders**: `h264_videotoolbox`, `hevc_videotoolbox`, `prores_ks`
- **Decoders**: `png`, `wrapped_avframe`
- **Muxers**: `mp4`, `mov`
- **Demuxers**: `concat`, `image2`, `image_png_pipe`
- **Filters**: `split`, `format`, `scale`, `crop`, `gblur`, `overlay`, `colorchannelmixer`, `color`
- **Protocol**: `file`
- **Indev**: `lavfi`
- **Not compiled**: VP9, webm/matroska (not needed — VP9 is Windows/Linux only)

### Windows Binary (`assets/ffmpeg/windows/ffmpeg.exe` + 2 DLLs)
- **Size**: ~30 MB + `libgcc_s_seh-1.dll` + `libwinpthread-1.dll`
- **Version**: ffmpeg 8.0.1 built with MinGW GCC
- **Encoders**: `libx264`, `libx265`, `libvpx_vp9`, `prores_ks`
- **Decoders**: `png`, `wrapped_avframe`
- **Muxers**: `mp4`, `mov`, `webm`, `matroska`
- **Demuxers**: `concat`, `image2`, `image_png_pipe`
- **Filters**: `split`, `format`, `scale`, `crop`, `gblur`, `overlay`, `colorchannelmixer`, `color`
- **Protocol**: `file`
- **Indev**: `lavfi`

### How Binaries Are Resolved at Runtime

**macOS** (`video_utils.dart:1022-1026`):
```dart
final ffmpegExeMac = path.join(
  path.dirname(Platform.resolvedExecutable), '..', 'Resources', 'ffmpeg'
);
```
- No fallback. Uses app bundle's `Resources/ffmpeg` directly.
- Xcode build phase copies `assets/ffmpeg/mac/ffmpeg` → `Resources/` during build.
- Integration tests build the app → build phase runs → binary is available.

**Windows** (`video_utils.dart:1577-1631` via `_resolveFfmpegPath()`):
1. `_ensureBundledFfmpeg()` — extracts from `rootBundle` to `appSupportDir/bin/ffmpeg.exe`
2. Fallback: `_findFfmpegOnPath()` — `where ffmpeg` PATH lookup
3. Final fallback: bare `'ffmpeg'` command

Integration tests bundle assets → step 1 always succeeds → bundled binary used.

### Ensuring No Fallback in Tests

Each platform group starts with a sanity test that:
- macOS: verifies `Resources/ffmpeg` exists, runs `ffmpeg -version`, asserts exit code 0
- Windows: verifies bundled extraction worked, runs `ffmpeg.exe -version` from the extracted path

Since `_resolveFfmpegPath()` tries bundled first, all subsequent compilation tests
automatically use the bundled binary. The sanity test proves the binary is functional.

---

## 2. Codec × Platform Matrix

### macOS Available Codecs (Opaque)

| Codec | Encoder | Container | Pixel Format | Rate Control |
|-------|---------|-----------|-------------|--------------|
| H.264 | `h264_videotoolbox -allow_sw 1` | `.mp4` | `yuv420p` | Bitrate (`-b:v -maxrate -bufsize`) |
| HEVC | `hevc_videotoolbox -allow_sw 1` | `.mp4` | `yuv420p` | Bitrate |
| ProRes 422 | `prores_ks -profile:v standard` | `.mov` | `yuv422p10le` | Quality (no bitrate) |
| ProRes 422 HQ | `prores_ks -profile:v hq` | `.mov` | `yuv422p10le` | Quality |

### macOS Alpha Codec

| Codec | Encoder | Container | Pixel Format |
|-------|---------|-----------|-------------|
| ProRes 4444 | `prores_ks -profile:v 4444 -vendor apl0 -alpha_bits 16` | `.mov` | `yuva444p10le` |

### Windows Available Codecs (Opaque)

| Codec | Encoder | Container | Pixel Format | Rate Control |
|-------|---------|-----------|-------------|--------------|
| H.264 | `libx264` | `.mp4` | `yuv420p` | Bitrate + profile/level per resolution |
| HEVC | `libx265` | `.mp4` | `yuv420p` | Bitrate |

### Windows Alpha Codec

| Codec | Encoder | Container | Pixel Format |
|-------|---------|-----------|-------------|
| VP9 | `libvpx-vp9` | `.webm` | `yuva420p` |

### H.264 Profile/Level on Windows

| Resolution | Profile | Level |
|-----------|---------|-------|
| ≤1080p | Main | 4.1 |
| 4K | High | 5.1 |
| 8K / custom >4K | High | 6.0 |

### Special: 8K Auto-Upgrade (macOS only)
When H.264 + resolution ≥8K or any dimension >4096px → automatically upgrades to HEVC.
VideoToolbox's H.264 encoder has a 4096px dimension limit.

---

## 3. Background Modes

| Mode | DB Setting | What Happens in FFmpeg | Codec Constraint |
|------|-----------|----------------------|-----------------|
| Opaque source | `background_color` = any hex | Direct encode, no overlay | Any opaque codec |
| Transparent + keep alpha | `background_color` = `#TRANSPARENT`, `video_background` = `TRANSPARENT` | Format filter only | ProRes 4444 (macOS) or VP9 (Windows) |
| Transparent + solid color | `background_color` = `#TRANSPARENT`, `video_background` = hex color | `-f lavfi -i "color=..."` as input 0, overlay filter | Any opaque codec |
| Transparent + blurred | `background_color` = `#TRANSPARENT`, `video_background` = `BLURRED` | `split` → `gblur` → `overlay` filter | Any opaque codec |

---

## 4. Overlay Features

### Date Stamp
- **Enable**: `export_date_stamp_enabled` = `'true'`
- **Pipeline**: Generates PNG images per unique date → adds as FFmpeg inputs → chains overlay filters with `enable='gte(t,start)*lt(t,end)'`
- **No drawtext needed** — all text is pre-rendered as PNGs
- **Required filters**: `overlay` (already compiled in both binaries)

### Watermark
- **Enable**: `enable_watermark` = `'true'`
- **File**: PNG at `DirUtils.getWatermarkFilePath(projectId)` = `<projectDir>/watermarks/watermark.png`
- **Pipeline**: `colorchannelmixer=aa=<opacity>` → `overlay=<position>`
- **Settings**: `watermark_position` (lower_left/lower_right/upper_left/upper_right), `watermark_opacity` (0.0-1.0)

---

## 5. Test Matrix

### macOS Tests (12 tests)

| # | Codec | Resolution | Orientation | Background | Overlays | What It Validates |
|---|-------|-----------|-------------|-----------|---------|------------------|
| 1 | H.264 | 1080p | landscape | opaque | none | Baseline h264_videotoolbox compile+play |
| 2 | H.264 | 4K | portrait | opaque | none | Higher resolution + portrait orientation |
| 3 | H.264 | 8K | landscape | opaque | none | Auto-upgrade to HEVC (4096px limit) |
| 4 | HEVC | 1080p | landscape | opaque | none | hevc_videotoolbox baseline |
| 5 | HEVC | 4K | portrait | opaque | date stamp | HEVC + date stamp overlay |
| 6 | ProRes 422 | 1080p | landscape | opaque | none | prores_ks standard profile |
| 7 | ProRes 422 HQ | 1080p | portrait | opaque | none | prores_ks hq profile + portrait |
| 8 | ProRes 4444 | 1080p | landscape | transparent (keep) | none | Alpha codec, yuva444p10le |
| 9 | H.264 | 1080p | landscape | transparent + solid #000000 | none | Color overlay compositing |
| 10 | HEVC | 1080p | landscape | transparent + blurred | none | Blur filter chain (split+gblur+overlay) |
| 11 | H.264 | 1080p | landscape | opaque | watermark | Watermark overlay (colorchannelmixer) |
| 12 | H.264 | 1080p | landscape | opaque | date stamp + watermark | Both overlays combined |

### Windows Tests (10 tests)

| # | Codec | Resolution | Orientation | Background | Overlays | What It Validates |
|---|-------|-----------|-------------|-----------|---------|------------------|
| 1 | H.264 | 1080p | landscape | opaque | none | Baseline libx264 (Main/4.1) |
| 2 | H.264 | 4K | portrait | opaque | none | libx264 (High/5.1) + portrait |
| 3 | H.264 | 8K | landscape | opaque | none | libx264 (High/6.0) — no auto-upgrade |
| 4 | HEVC | 1080p | landscape | opaque | none | libx265 baseline |
| 5 | HEVC | 4K | portrait | opaque | date stamp | libx265 + date stamp overlay |
| 6 | VP9 | 1080p | landscape | transparent (keep) | none | Alpha webm (-crf 30 -row-mt 1) |
| 7 | H.264 | 1080p | landscape | transparent + solid #1A1A2E | none | Color overlay compositing |
| 8 | HEVC | 1080p | landscape | transparent + blurred | none | Blur filter chain |
| 9 | H.264 | 1080p | landscape | opaque | watermark | Watermark overlay |
| 10 | H.264 | 1080p | landscape | opaque | date stamp + watermark | Both overlays combined |

---

## 6. Test Structure

### File: `integration_test/e2e_pipeline_test.dart`

```
setUpAll:
  - initDatabase()
  - DB.instance.createTablesIfNotExist()

setUp / tearDown:
  - Create/delete project + cleanup project directory

Helpers:
  - setupOpaqueFrames(projectId, orientation, width, height, count)
  - setupTransparentFrames(projectId, orientation, width, height, count)
  - createWatermarkImage(projectId)  // generates simple PNG
  - verifyCompilation(projectId, orientation, codec, expectedExtension)
  - verifyPlayback(videoFile)  // with platform skip guards

Groups:
  group('FFmpeg binary sanity') → verify bundled binary exists + runs
  group('macOS codecs') → 12 tests (skip on non-macOS)
  group('Windows codecs') → 10 tests (skip on non-Windows)
```

### Each Test Pattern:
```dart
testWidgets('H.264 1080p landscape opaque', (tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // 1. Create project
  testProjectId = await DB.instance.addProject('Test', 'face', timestamp);

  // 2. Configure settings
  await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
  await DB.instance.setSettingByTitle('project_orientation', 'landscape', pid);
  await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

  // 3. Create frames in stabilized/<orientation>/
  await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 5);

  // 4. Compile
  final success = await VideoUtils.createTimelapseFromProjectId(testProjectId!, null);
  expect(success, isTrue);

  // 5. Verify output
  final videoPath = await DirUtils.getVideoOutputPath(testProjectId!, 'landscape', codec: VideoCodec.h264);
  final videoFile = File(videoPath);
  expect(await videoFile.exists(), isTrue);
  expect(await videoFile.length(), greaterThan(1000));

  // 6. Verify playback (with platform guards)
  if (!_skipPlayback) {
    final controller = VideoPlayerController.file(videoFile);
    await controller.initialize();
    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.duration.inMilliseconds, greaterThan(0));
    await controller.dispose();
  }
});
```

### Frame Dimensions Per Test:

| Resolution | Landscape (W×H) | Portrait (W×H) |
|-----------|-----------------|----------------|
| 1080p | 1920 × 1080 | 1080 × 1920 |
| 4K | 3840 × 2160 | 2160 × 3840 |
| 8K | 7680 × 4320 | 4320 × 7680 |

### Transparent Frame Creation:
```dart
final image = img.Image(width: w, height: h, numChannels: 4);
// Center opaque, edges transparent
for (int y = 0; y < h; y++) {
  for (int x = 0; x < w; x++) {
    final bool edge = x < 20 || x >= w-20 || y < 20 || y >= h-20;
    image.setPixelRgba(x, y, r, g, b, edge ? 0 : 255);
  }
}
```

---

## 7. Playback Skip Conditions

| Platform | Condition | Playback? | Reason |
|----------|----------|-----------|--------|
| macOS | any | Yes | AVFoundation works |
| macOS CI | any | Yes | AVFoundation works on CI runners |
| Windows | local | Yes | Windows Media Foundation |
| Windows CI | CI='true' | **Skip** | No WMF backend on GH Actions |
| Linux | CI='true' | **Skip** | mpv hangs under Xvfb |

Compilation is always verified. Playback is skipped only where the video player
framework doesn't work on CI.

---

## 8. CI Workflow

Use the existing `dev-test.yml` with `workflow_dispatch`:
- **Platform**: `macos` or `windows`
- **Test file**: `e2e_pipeline_test.dart`
- **Flutter channel**: `stable`

Run macOS and Windows separately to test each platform's codec suite independently.

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| HEVC VideoToolbox fails on CI (no GPU) | `-allow_sw 1` enables software fallback. If it fails, add CI skip. |
| 8K frames are huge (7680×4320 PNG) | Synthetic solid-color frames compress well. Monitor CI memory. |
| Date stamp PNG generation fails | DateStampUtils is well-tested. Use real timestamps for photos. |
| Watermark file missing | Test creates watermark PNG programmatically before compilation. |
| Windows bundled ffmpeg DLL extraction fails | Covered by ffmpeg binary sanity test at start of suite. |
| VP9 encoding very slow (software) | Use only 3 frames at 1080p — encoding takes seconds. |
| ProRes 4444 10-bit pixel format issues | Binary has prores_ks compiled. Test verifies .mov output. |
