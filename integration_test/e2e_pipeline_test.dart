import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/models/video_background.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/video_utils.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// End-to-end pipeline integration tests that verify bundled FFmpeg binaries
/// can compile videos across every supported codec, resolution, orientation,
/// and background mode on macOS and Windows.
///
/// Each test: create frames → set DB settings → compile → verify output → verify playback.
///
/// Run with:
///   flutter test integration_test/e2e_pipeline_test.dart -d macos
///   flutter test integration_test/e2e_pipeline_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  final bool isCI = Platform.environment['CI'] == 'true';

  /// Whether to skip playback assertions on this platform/environment.
  bool skipPlayback() {
    if (Platform.isWindows && isCI) return true;
    if (Platform.isLinux && isCI) return true;
    return false;
  }

  group('E2E Pipeline Tests', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      testProjectId = null;
    });

    tearDown(() async {
      if (testProjectId != null) {
        try {
          final projectDir = await DirUtils.getProjectDirPath(testProjectId!);
          if (await Directory(projectDir).exists()) {
            await Directory(projectDir).delete(recursive: true);
          }
          await DB.instance.deleteProject(testProjectId!);
        } catch (_) {}
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    // ── Helpers ────────────────────────────────────────────────────────

    Future<void> setupOpaqueFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int frameCount, {
      List<int>? timestamps,
    }) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientationDir = Directory(p.join(stabDir, orientation));
      await orientationDir.create(recursive: true);

      for (int i = 0; i < frameCount; i++) {
        final ts = timestamps != null ? timestamps[i] : 1000000000 + (i * 1000);
        final framePath = p.join(orientationDir.path, '$ts.png');

        final image = img.Image(width: width, height: height);
        img.fill(
          image,
          color: img.ColorRgb8(
            (i * 80) % 256,
            (i * 60 + 100) % 256,
            (i * 40 + 50) % 256,
          ),
        );

        final pngBytes = img.encodePng(image);
        await File(framePath).writeAsBytes(pngBytes);

        await DB.instance.addPhoto(
          ts.toString(),
          projectId,
          '.png',
          pngBytes.length,
          '$ts.png',
          orientation,
        );
        await DB.instance.setPhotoStabilized(
          ts.toString(),
          projectId,
          orientation,
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );
      }
    }

    Future<void> setupTransparentFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int frameCount, {
      List<int>? timestamps,
    }) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientationDir = Directory(p.join(stabDir, orientation));
      await orientationDir.create(recursive: true);

      for (int i = 0; i < frameCount; i++) {
        final ts = timestamps != null ? timestamps[i] : 1000000000 + (i * 1000);
        final framePath = p.join(orientationDir.path, '$ts.png');

        final image = img.Image(width: width, height: height, numChannels: 4);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final bool isEdge =
                x < 20 || x >= width - 20 || y < 20 || y >= height - 20;
            image.setPixelRgba(
              x,
              y,
              (i * 80 + x) % 256,
              (i * 60 + y) % 256,
              (i * 40 + 50) % 256,
              isEdge ? 0 : 255,
            );
          }
        }

        final pngBytes = img.encodePng(image);
        await File(framePath).writeAsBytes(pngBytes);

        await DB.instance.addPhoto(
          ts.toString(),
          projectId,
          '.png',
          pngBytes.length,
          '$ts.png',
          orientation,
        );
        await DB.instance.setPhotoStabilized(
          ts.toString(),
          projectId,
          orientation,
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );
      }
    }

    /// Creates a simple watermark PNG at the expected path for the project.
    Future<void> createTestWatermark(int projectId) async {
      final wmPath = await DirUtils.getWatermarkFilePath(projectId);
      final wmDir = Directory(p.dirname(wmPath));
      await wmDir.create(recursive: true);
      final image = img.Image(width: 100, height: 40);
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 200));
      await File(wmPath).writeAsBytes(img.encodePng(image));
    }

    /// Timestamps spread across different months (for date stamp overlay tests).
    List<int> dateStampTimestamps() => [
          DateTime(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch,
          DateTime(2024, 6, 15, 12, 0, 0).millisecondsSinceEpoch,
          DateTime(2024, 11, 15, 12, 0, 0).millisecondsSinceEpoch,
        ];

    /// Core test runner: creates project, sets settings, creates frames,
    /// compiles video, verifies output file and optionally playback.
    Future<void> runPipelineTest({
      required WidgetTester tester,
      required String testName,
      required VideoCodec codec,
      required String resolution,
      required String orientation,
      required int width,
      required int height,
      bool transparent = false,
      VideoBackground? videoBackground,
      bool enableDateStamp = false,
      bool enableWatermark = false,
      required void Function(int id) setProjectId,
    }) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectId = await DB.instance.addProject(
        testName,
        'face',
        timestamp,
      );
      setProjectId(projectId);
      final pid = projectId.toString();

      // Configure settings
      await DB.instance.setSettingByTitle('video_resolution', resolution, pid);
      await DB.instance.setSettingByTitle(
        'project_orientation',
        orientation,
        pid,
      );
      await DB.instance.setSettingByTitle('video_codec', codec.name, pid);
      await DB.instance.setSettingByTitle(
        'framerate_is_default',
        'false',
        pid,
      );
      await DB.instance.setSettingByTitle('framerate', '14', pid);

      if (transparent) {
        await DB.instance.setSettingByTitle(
          'background_color',
          '#TRANSPARENT',
          pid,
        );
      }
      if (videoBackground != null) {
        await DB.instance.setSettingByTitle(
          'video_background',
          videoBackground.toDbValue(),
          pid,
        );
      }

      // Date stamp overlay
      final List<int>? tsOverride;
      if (enableDateStamp) {
        await DB.instance.setSettingByTitle(
          'export_date_stamp_enabled',
          'true',
          pid,
        );
        tsOverride = dateStampTimestamps();
      } else {
        tsOverride = null;
      }

      // Watermark overlay
      if (enableWatermark) {
        await DB.instance.setSettingByTitle('enable_watermark', 'true', pid);
        await DB.instance.setSettingByTitle('watermark_position', 'lower left');
        await DB.instance.setSettingByTitle('watermark_opacity', '0.7');
        await createTestWatermark(projectId);
      }

      // Create frames
      const frameCount = 3;
      if (transparent) {
        await setupTransparentFrames(
          projectId,
          orientation,
          width,
          height,
          frameCount,
          timestamps: tsOverride,
        );
      } else {
        await setupOpaqueFrames(
          projectId,
          orientation,
          width,
          height,
          frameCount,
          timestamps: tsOverride,
        );
      }

      // Compile
      final success = await VideoUtils.createTimelapseFromProjectId(
        projectId,
        null,
      );
      expect(
        success,
        isTrue,
        reason: '$testName: compilation should succeed',
      );

      // Verify output file
      final videoPath = await DirUtils.getVideoOutputPath(
        projectId,
        orientation,
        codec: codec,
      );
      final videoFile = File(videoPath);
      expect(
        await videoFile.exists(),
        isTrue,
        reason: '$testName: output file should exist at $videoPath',
      );

      final fileSize = await videoFile.length();
      expect(
        fileSize,
        greaterThan(100),
        reason: '$testName: output file should have content ($fileSize bytes)',
      );

      // Verify correct extension
      final expectedExt = codec.containerExtension;
      expect(
        p.extension(videoPath),
        equals(expectedExt),
        reason: '$testName: should have $expectedExt extension',
      );

      // Verify playback (where supported)
      if (!skipPlayback()) {
        final controller = VideoPlayerController.file(videoFile);
        try {
          await controller.initialize();
          expect(
            controller.value.isInitialized,
            isTrue,
            reason: '$testName: player should initialize',
          );
          expect(
            controller.value.hasError,
            isFalse,
            reason: '$testName: player should not have error',
          );
          expect(
            controller.value.duration.inMilliseconds,
            greaterThan(0),
            reason: '$testName: video should have non-zero duration',
          );
        } finally {
          await controller.dispose();
        }
      }
    }

    // ── FFmpeg Binary Sanity ──────────────────────────────────────────

    group('FFmpeg binary sanity', () {
      testWidgets('bundled FFmpeg binary exists and runs', (tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 2));

        if (Platform.isMacOS) {
          final exeDir = p.dirname(Platform.resolvedExecutable);
          final resourcesDir = p.normalize(
            p.join(exeDir, '..', 'Resources'),
          );
          final ffmpegPath = p.join(resourcesDir, 'ffmpeg');
          expect(
            await File(ffmpegPath).exists(),
            isTrue,
            reason: 'Bundled ffmpeg should exist at $ffmpegPath',
          );

          final result = await Process.run(ffmpegPath, ['-version']);
          expect(result.exitCode, equals(0),
              reason: 'ffmpeg -version should succeed');
          expect(
            (result.stdout as String),
            contains('ffmpeg version'),
            reason: 'Should print version info',
          );
        } else if (Platform.isWindows) {
          // Verify the asset is loadable from the bundle
          final bytes = await rootBundle.load(
            'assets/ffmpeg/windows/ffmpeg.exe',
          );
          expect(
            bytes.lengthInBytes,
            greaterThan(1000000),
            reason:
                'Bundled ffmpeg.exe should be >1MB (got ${bytes.lengthInBytes})',
          );
        } else if (Platform.isLinux) {
          // Linux uses system ffmpeg — verify it's on PATH
          final result = await Process.run('which', ['ffmpeg']);
          expect(result.exitCode, equals(0),
              reason: 'ffmpeg should be available on PATH');
        } else {
          // iOS/Android use FFmpegKit — no binary to check directly.
          // The compilation tests themselves verify FFmpegKit works.
        }
      });
    });

    // ── macOS Codec Tests ─────────────────────────────────────────────

    group('macOS codecs', () {
      // Test 1: H.264 1080p landscape (baseline)
      testWidgets('H.264 1080p landscape opaque', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 1080p landscape',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 2: H.264 4K portrait
      testWidgets('H.264 4K portrait opaque', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 4K portrait',
          codec: VideoCodec.h264,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 3: H.264 8K landscape (auto-upgrades to HEVC)
      testWidgets('H.264 8K landscape auto-upgrade to HEVC', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 8K (→HEVC)',
          codec: VideoCodec.h264,
          resolution: '8K',
          orientation: 'landscape',
          width: 7680,
          height: 4320,
          setProjectId: (id) => testProjectId = id,
        );
        // Output is still .mp4 (HEVC in mp4 container) since the codec setting
        // is h264 but auto-upgraded internally. Verify the file exists.
      });

      // Test 4: HEVC 1080p landscape
      testWidgets('HEVC 1080p landscape opaque', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS HEVC 1080p landscape',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 5: HEVC 4K portrait + date stamp
      testWidgets('HEVC 4K portrait with date stamp', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS HEVC 4K portrait+datestamp',
          codec: VideoCodec.hevc,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          enableDateStamp: true,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 6: ProRes 422 1080p landscape
      testWidgets('ProRes 422 1080p landscape opaque', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS ProRes 422 1080p landscape',
          codec: VideoCodec.prores422,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 7: ProRes 422 HQ 1080p portrait
      testWidgets('ProRes 422 HQ 1080p portrait opaque', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS ProRes 422 HQ portrait',
          codec: VideoCodec.prores422hq,
          resolution: '1080p',
          orientation: 'portrait',
          width: 1080,
          height: 1920,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 8: ProRes 4444 transparent (keep alpha)
      testWidgets('ProRes 4444 1080p transparent keep alpha', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS ProRes 4444 transparent',
          codec: VideoCodec.prores4444,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.transparent(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 9: H.264 transparent + solid color overlay
      testWidgets('H.264 1080p transparent solid color overlay', (
        tester,
      ) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 solid color overlay',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#000000'),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 10: HEVC transparent + blurred background
      testWidgets('HEVC 1080p transparent blurred background', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS HEVC blurred bg',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.blurred(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 11: H.264 with watermark
      testWidgets('H.264 1080p landscape with watermark', (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 12: H.264 with date stamp + watermark
      testWidgets('H.264 1080p landscape date stamp + watermark', (
        tester,
      ) async {
        if (!Platform.isMacOS) {
          markTestSkipped('macOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'macOS H.264 datestamp+watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableDateStamp: true,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });
    });

    // ── Windows Codec Tests ───────────────────────────────────────────

    group('Windows codecs', () {
      // Test 1: H.264 1080p landscape (baseline, Main profile Level 4.1)
      testWidgets('H.264 1080p landscape opaque', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 1080p landscape',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 2: H.264 4K portrait (High profile Level 5.1)
      testWidgets('H.264 4K portrait opaque', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 4K portrait',
          codec: VideoCodec.h264,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 3: H.264 8K landscape (High profile Level 6.0, no auto-upgrade on Windows)
      testWidgets('H.264 8K landscape opaque', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 8K landscape',
          codec: VideoCodec.h264,
          resolution: '8K',
          orientation: 'landscape',
          width: 7680,
          height: 4320,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 4: HEVC 1080p landscape (libx265)
      testWidgets('HEVC 1080p landscape opaque', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win HEVC 1080p landscape',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 5: HEVC 4K portrait + date stamp
      testWidgets('HEVC 4K portrait with date stamp', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win HEVC 4K portrait+datestamp',
          codec: VideoCodec.hevc,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          enableDateStamp: true,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 6: VP9 transparent (keep alpha, webm)
      testWidgets('VP9 1080p transparent keep alpha', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win VP9 transparent',
          codec: VideoCodec.vp9,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.transparent(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 7: H.264 transparent + solid color overlay
      testWidgets('H.264 1080p transparent solid color overlay', (
        tester,
      ) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 solid color overlay',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#1A1A2E'),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 8: HEVC transparent + blurred background
      testWidgets('HEVC 1080p transparent blurred background', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win HEVC blurred bg',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.blurred(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 9: H.264 with watermark
      testWidgets('H.264 1080p landscape with watermark', (tester) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 10: H.264 with date stamp + watermark
      testWidgets('H.264 1080p landscape date stamp + watermark', (
        tester,
      ) async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Win H.264 datestamp+watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableDateStamp: true,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });
    });

    // ── Linux Codec Tests ─────────────────────────────────────────────

    group('Linux codecs', () {
      // Test 1: H.264 1080p landscape (baseline, libx264)
      testWidgets('H.264 1080p landscape opaque', (tester) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux H.264 1080p landscape',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 2: H.264 4K portrait
      testWidgets('H.264 4K portrait opaque', (tester) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux H.264 4K portrait',
          codec: VideoCodec.h264,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 3: HEVC 1080p landscape (libx265)
      testWidgets('HEVC 1080p landscape opaque', (tester) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux HEVC 1080p landscape',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 4: VP9 transparent (keep alpha, webm)
      testWidgets('VP9 1080p transparent keep alpha', (tester) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux VP9 transparent',
          codec: VideoCodec.vp9,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.transparent(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 5: H.264 transparent + solid color overlay
      testWidgets('H.264 1080p transparent solid color overlay', (
        tester,
      ) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux H.264 solid color overlay',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#000000'),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 6: HEVC transparent + blurred background
      testWidgets('HEVC 1080p transparent blurred background', (tester) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux HEVC blurred bg',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.blurred(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 7: H.264 with date stamp + watermark
      testWidgets('H.264 1080p landscape date stamp + watermark', (
        tester,
      ) async {
        if (!Platform.isLinux) {
          markTestSkipped('Linux only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Linux H.264 datestamp+watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableDateStamp: true,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });
    });

    // ── iOS Codec Tests ───────────────────────────────────────────────

    group('iOS codecs', () {
      // Test 1: H.264 1080p landscape (baseline)
      testWidgets('H.264 1080p landscape opaque', (tester) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS H.264 1080p landscape',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 2: H.264 4K portrait
      testWidgets('H.264 4K portrait opaque', (tester) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS H.264 4K portrait',
          codec: VideoCodec.h264,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 3: HEVC 1080p landscape
      testWidgets('HEVC 1080p landscape opaque', (tester) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS HEVC 1080p landscape',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 4: ProRes 4444 transparent (keep alpha)
      testWidgets('ProRes 4444 1080p transparent keep alpha', (tester) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS ProRes 4444 transparent',
          codec: VideoCodec.prores4444,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.transparent(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 5: H.264 transparent + solid color overlay
      testWidgets('H.264 1080p transparent solid color overlay', (
        tester,
      ) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS H.264 solid color overlay',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#000000'),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 6: HEVC transparent + blurred background
      testWidgets('HEVC 1080p transparent blurred background', (tester) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS HEVC blurred bg',
          codec: VideoCodec.hevc,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.blurred(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 7: H.264 with date stamp + watermark
      testWidgets('H.264 1080p landscape date stamp + watermark', (
        tester,
      ) async {
        if (!Platform.isIOS) {
          markTestSkipped('iOS only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'iOS H.264 datestamp+watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableDateStamp: true,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });
    });

    // ── Android Codec Tests ───────────────────────────────────────────

    group('Android codecs', () {
      // Test 1: H.264 1080p landscape (baseline, only opaque codec on Android)
      testWidgets('H.264 1080p landscape opaque', (tester) async {
        if (!Platform.isAndroid) {
          markTestSkipped('Android only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Android H.264 1080p landscape',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 2: H.264 4K portrait
      testWidgets('H.264 4K portrait opaque', (tester) async {
        if (!Platform.isAndroid) {
          markTestSkipped('Android only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Android H.264 4K portrait',
          codec: VideoCodec.h264,
          resolution: '4K',
          orientation: 'portrait',
          width: 2160,
          height: 3840,
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 3: VP9 transparent (keep alpha, webm)
      testWidgets('VP9 1080p transparent keep alpha', (tester) async {
        if (!Platform.isAndroid) {
          markTestSkipped('Android only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Android VP9 transparent',
          codec: VideoCodec.vp9,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: const VideoBackground.transparent(),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 4: H.264 transparent + solid color overlay
      testWidgets('H.264 1080p transparent solid color overlay', (
        tester,
      ) async {
        if (!Platform.isAndroid) {
          markTestSkipped('Android only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Android H.264 solid color overlay',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#000000'),
          setProjectId: (id) => testProjectId = id,
        );
      });

      // Test 5: H.264 with date stamp + watermark
      testWidgets('H.264 1080p landscape date stamp + watermark', (
        tester,
      ) async {
        if (!Platform.isAndroid) {
          markTestSkipped('Android only');
          return;
        }
        await runPipelineTest(
          tester: tester,
          testName: 'Android H.264 datestamp+watermark',
          codec: VideoCodec.h264,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          enableDateStamp: true,
          enableWatermark: true,
          setProjectId: (id) => testProjectId = id,
        );
      });
    });

    // ── Real Stabilization → Compilation ──────────────────────────────

    group('Real stabilization pipeline', () {
      testWidgets('stabilize sample faces then compile H.264 video', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Load sample face images (only available on desktop — test fixtures
        // are not bundled in pubspec.yaml for mobile builds).
        if (Platform.isAndroid || Platform.isIOS) {
          markTestSkipped(
            'Sample face fixtures not bundled on mobile (commented out in pubspec.yaml)',
          );
          return;
        }

        await preloadFixtures();

        final facePaths = <String>[];
        for (int day = 1; day <= 3; day++) {
          try {
            final path = await getSampleFacePathAsync(day);
            if (!await File(path).exists()) {
              markTestSkipped('Sample face day$day not available');
              return;
            }
            facePaths.add(path);
          } catch (_) {
            markTestSkipped('Sample face fixtures not available');
            return;
          }
        }

        // Create project
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final projectId = await DB.instance.addProject(
          'Real Stabilization Test',
          'face',
          timestamp,
        );
        testProjectId = projectId;
        final pid = projectId.toString();

        // Configure settings
        await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
        await DB.instance.setSettingByTitle(
          'project_orientation',
          'landscape',
          pid,
        );
        await DB.instance.setSettingByTitle('video_codec', 'h264', pid);
        await DB.instance.setSettingByTitle(
          'framerate_is_default',
          'false',
          pid,
        );
        await DB.instance.setSettingByTitle('framerate', '14', pid);

        // Stabilize each face image and write to stabilized dir
        final stabDir = await DirUtils.getStabilizedDirPath(projectId);
        final orientationDir = Directory(p.join(stabDir, 'landscape'));
        await orientationDir.create(recursive: true);

        for (int i = 0; i < facePaths.length; i++) {
          final bytes = await File(facePaths[i]).readAsBytes();

          // Detect face
          final faces = await StabUtils.getFacesFromBytes(bytes);
          if (faces == null || faces.isEmpty) {
            markTestSkipped('No face detected in day${i + 1}.jpg');
            return;
          }

          final face = faces.first;
          final leftEye = face.leftEye;
          final rightEye = face.rightEye;

          // Calculate rotation from eye landmarks
          double rotationDegrees = 0.0;
          if (leftEye != null && rightEye != null) {
            final dy = rightEye.y - leftEye.y;
            final dx = rightEye.x - leftEye.x;
            rotationDegrees = atan2(dy, dx) * 180 / pi;
          }

          // Stabilize
          final stabilized =
              await StabUtils.generateStabilizedImageBytesCVAsync(
            bytes,
            rotationDegrees,
            1.0, // scale
            0.0, // translateX
            0.0, // translateY
            1920, // canvas width
            1080, // canvas height
          );
          expect(
            stabilized,
            isNotNull,
            reason: 'Stabilization of day${i + 1}.jpg should succeed',
          );

          // Write stabilized PNG to stabilized dir
          final ts = 1000000000 + (i * 86400000); // days apart
          final framePath = p.join(orientationDir.path, '$ts.png');
          await File(framePath).writeAsBytes(stabilized!);

          // Register in DB
          await DB.instance.addPhoto(
            ts.toString(),
            projectId,
            '.png',
            stabilized.length,
            '$ts.png',
            'landscape',
          );
          await DB.instance.setPhotoStabilized(
            ts.toString(),
            projectId,
            'landscape',
            '16:9',
            '1080p',
            0.065,
            0.421875,
          );
        }

        // Compile video
        final success = await VideoUtils.createTimelapseFromProjectId(
          projectId,
          null,
        );
        expect(success, isTrue, reason: 'Compilation should succeed');

        // Verify output
        final videoPath = await DirUtils.getVideoOutputPath(
          projectId,
          'landscape',
          codec: VideoCodec.h264,
        );
        final videoFile = File(videoPath);
        expect(
          await videoFile.exists(),
          isTrue,
          reason: 'Video output should exist',
        );
        expect(
          await videoFile.length(),
          greaterThan(1000),
          reason: 'Video should have reasonable size',
        );

        // Verify playback (where supported)
        if (!skipPlayback()) {
          final controller = VideoPlayerController.file(videoFile);
          try {
            await controller.initialize();
            expect(controller.value.isInitialized, isTrue);
            expect(controller.value.hasError, isFalse);
            expect(controller.value.duration.inMilliseconds, greaterThan(0));
          } finally {
            await controller.dispose();
          }
        }
      });
    });
  });
}
