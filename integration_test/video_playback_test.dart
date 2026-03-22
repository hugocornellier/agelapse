import 'dart:io';

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
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// Integration tests that compile videos then attempt playback via
/// VideoPlayerController.  These catch platform-specific codec support
/// issues — e.g. HEVC and ProRes throw on Windows because Windows Media
/// Foundation lacks decoders for those codecs.
///
/// Run with: `flutter test integration_test/video_playback_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Video Playback Tests', () {
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

    /// Creates opaque test PNG frames in the stabilized directory.
    Future<void> setupOpaqueFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int frameCount,
    ) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientationDir = Directory(p.join(stabDir, orientation));
      await orientationDir.create(recursive: true);

      for (int i = 0; i < frameCount; i++) {
        final timestamp = 1000000000 + (i * 1000);
        final framePath = p.join(orientationDir.path, '$timestamp.png');

        final image = img.Image(width: width, height: height);
        final color = img.ColorRgb8(
          (i * 80) % 256,
          (i * 60 + 100) % 256,
          (i * 40 + 50) % 256,
        );
        img.fill(image, color: color);

        final pngBytes = img.encodePng(image);
        await File(framePath).writeAsBytes(pngBytes);

        await DB.instance.addPhoto(
          timestamp.toString(),
          projectId,
          '.png',
          pngBytes.length,
          '$timestamp.png',
          orientation,
        );
        await DB.instance.setPhotoStabilized(
          timestamp.toString(),
          projectId,
          orientation,
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );
      }
    }

    /// Creates transparent test PNG frames (RGBA with alpha channel).
    Future<void> setupTransparentFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int frameCount,
    ) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientationDir = Directory(p.join(stabDir, orientation));
      await orientationDir.create(recursive: true);

      for (int i = 0; i < frameCount; i++) {
        final timestamp = 1000000000 + (i * 1000);
        final framePath = p.join(orientationDir.path, '$timestamp.png');

        final image = img.Image(width: width, height: height, numChannels: 4);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final bool isEdge =
                x < 20 || x >= width - 20 || y < 20 || y >= height - 20;
            final alpha = isEdge ? 0 : 255;
            image.setPixelRgba(
              x,
              y,
              (i * 80 + x) % 256,
              (i * 60 + y) % 256,
              (i * 40 + 50) % 256,
              alpha,
            );
          }
        }

        final pngBytes = img.encodePng(image);
        await File(framePath).writeAsBytes(pngBytes);

        await DB.instance.addPhoto(
          timestamp.toString(),
          projectId,
          '.png',
          pngBytes.length,
          '$timestamp.png',
          orientation,
        );
        await DB.instance.setPhotoStabilized(
          timestamp.toString(),
          projectId,
          orientation,
          '16:9',
          '1080p',
          0.065,
          0.421875,
        );
      }
    }

    /// Compiles a video with the given codec, then attempts playback via
    /// VideoPlayerController.  Returns normally on success, throws on failure.
    Future<void> compileAndPlay({
      required WidgetTester tester,
      required String testName,
      required VideoCodec codec,
      bool transparent = false,
      VideoBackground? videoBackground,
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

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        pid,
      );
      await DB.instance.setSettingByTitle('video_codec', codec.name, pid);

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

      // Create frames
      if (transparent) {
        await setupTransparentFrames(projectId, 'landscape', 1920, 1080, 3);
      } else {
        await setupOpaqueFrames(projectId, 'landscape', 1920, 1080, 3);
      }

      // Compile
      final success = await VideoUtils.createTimelapseFromProjectId(
        projectId,
        null,
      );
      expect(success, isTrue, reason: '$testName compilation should succeed');

      // Verify output exists
      final videoPath = await DirUtils.getVideoOutputPath(
        projectId,
        'landscape',
        codec: codec,
      );
      final videoFile = File(videoPath);
      expect(
        await videoFile.exists(),
        isTrue,
        reason: '$testName output file should exist at $videoPath',
      );

      // Attempt playback
      final controller = VideoPlayerController.file(videoFile);
      try {
        await controller.initialize();

        expect(
          controller.value.isInitialized,
          isTrue,
          reason: '$testName player should initialize',
        );
        expect(
          controller.value.hasError,
          isFalse,
          reason: '$testName player should not have error',
        );
        expect(
          controller.value.duration.inMilliseconds,
          greaterThan(0),
          reason: '$testName video should have non-zero duration',
        );
      } finally {
        await controller.dispose();
      }
    }

    // ===== H.264: should play on all platforms =====

    testWidgets('H.264 video compiles and plays back', (tester) async {
      await compileAndPlay(
        tester: tester,
        testName: 'H.264 playback',
        codec: VideoCodec.h264,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== HEVC: fails on Windows without HEVC Video Extensions =====

    testWidgets('HEVC video compiles and plays back', (tester) async {
      if (Platform.isAndroid) {
        markTestSkipped('HEVC is not available on Android');
        return;
      }
      if ((Platform.isMacOS || Platform.isIOS) &&
          Platform.environment['CI'] == 'true') {
        markTestSkipped(
          'HEVC VideoToolbox unavailable on CI (no hardware encoder)',
        );
        return;
      }
      await compileAndPlay(
        tester: tester,
        testName: 'HEVC playback',
        codec: VideoCodec.hevc,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== ProRes 422: fails on Windows (no MF decoder) =====

    testWidgets('ProRes 422 video compiles and plays back', (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes 422 playback test only runs on macOS');
        return;
      }
      await compileAndPlay(
        tester: tester,
        testName: 'ProRes 422 playback',
        codec: VideoCodec.prores422,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== ProRes 422 HQ: fails on Windows =====

    testWidgets('ProRes 422 HQ video compiles and plays back', (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes 422 HQ playback test only runs on macOS');
        return;
      }
      await compileAndPlay(
        tester: tester,
        testName: 'ProRes 422 HQ playback',
        codec: VideoCodec.prores422hq,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== ProRes 4444 transparent: Apple only =====

    testWidgets('ProRes 4444 transparent video compiles and plays back', (
      tester,
    ) async {
      if (!Platform.isMacOS && !Platform.isIOS) {
        markTestSkipped('ProRes 4444 test only runs on Apple platforms');
        return;
      }

      await compileAndPlay(
        tester: tester,
        testName: 'ProRes 4444 playback',
        codec: VideoCodec.prores4444,
        transparent: true,
        videoBackground: const VideoBackground.transparent(),
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== VP9: non-Apple only =====

    testWidgets('VP9 transparent video compiles and plays back', (
      tester,
    ) async {
      if (Platform.isMacOS || Platform.isIOS) {
        markTestSkipped(
          'VP9 transparent test skipped on Apple (use ProRes 4444)',
        );
        return;
      }

      await compileAndPlay(
        tester: tester,
        testName: 'VP9 playback',
        codec: VideoCodec.vp9,
        transparent: true,
        videoBackground: const VideoBackground.transparent(),
        setProjectId: (id) => testProjectId = id,
      );
    });
  });
}
