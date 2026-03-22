import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

/// Integration tests for video codec selection.
///
/// Tests all codec × resolution × transparency × orientation combinations
/// by compiling real videos via FFmpeg and verifying outputs.
///
/// Run with: `flutter test integration_test/video_codec_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Video Codec Integration Tests', () {
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

    /// Creates opaque test PNG frames (RGB, no alpha).
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

        // Create RGBA image with transparency in edges
        final image = img.Image(width: width, height: height, numChannels: 4);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            // Make edges transparent, center opaque
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

    /// Helper to create a project, set codec + settings, compile, and verify output.
    Future<void> runCodecTest({
      required WidgetTester tester,
      required String testName,
      required VideoCodec codec,
      required String resolution,
      required String orientation,
      required int width,
      required int height,
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

      // Configure settings
      await DB.instance.setSettingByTitle('video_resolution', resolution, pid);
      await DB.instance.setSettingByTitle(
        'project_orientation',
        orientation,
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
        await setupTransparentFrames(projectId, orientation, width, height, 3);
      } else {
        await setupOpaqueFrames(projectId, orientation, width, height, 3);
      }

      // Compile video
      final success = await VideoUtils.createTimelapseFromProjectId(
        projectId,
        null,
      );

      expect(success, isTrue, reason: '$testName compilation should succeed');

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
        reason: '$testName output file should exist at $videoPath',
      );

      final videoSize = await videoFile.length();
      expect(
        videoSize,
        greaterThan(100),
        reason: '$testName output file should have reasonable size',
      );

      // Verify correct extension
      final ext = p.extension(videoPath);
      expect(
        ext,
        codec.containerExtension,
        reason: '$testName should use ${codec.containerExtension} extension',
      );
    }

    // ===== H.264 Tests =====

    testWidgets('H.264 1080p landscape', (tester) async {
      await runCodecTest(
        tester: tester,
        testName: 'H.264 1080p',
        codec: VideoCodec.h264,
        resolution: '1080p',
        orientation: 'landscape',
        width: 1920,
        height: 1080,
        setProjectId: (id) => testProjectId = id,
      );
    });

    testWidgets('H.264 4K landscape', (tester) async {
      await runCodecTest(
        tester: tester,
        testName: 'H.264 4K',
        codec: VideoCodec.h264,
        resolution: '4K',
        orientation: 'landscape',
        width: 4096,
        height: 2304,
        setProjectId: (id) => testProjectId = id,
      );
    });

    testWidgets('H.264 portrait', (tester) async {
      await runCodecTest(
        tester: tester,
        testName: 'H.264 portrait',
        codec: VideoCodec.h264,
        resolution: '1080p',
        orientation: 'portrait',
        width: 1080,
        height: 1920,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== HEVC Tests =====
    // HEVC VideoToolbox requires hardware encoder access which is
    // unavailable on GitHub Actions macOS runners. Skip on CI.

    testWidgets('HEVC 1080p landscape', (tester) async {
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
      await runCodecTest(
        tester: tester,
        testName: 'HEVC 1080p',
        codec: VideoCodec.hevc,
        resolution: '1080p',
        orientation: 'landscape',
        width: 1920,
        height: 1080,
        setProjectId: (id) => testProjectId = id,
      );
    });

    testWidgets('HEVC 4K landscape', (tester) async {
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
      await runCodecTest(
        tester: tester,
        testName: 'HEVC 4K',
        codec: VideoCodec.hevc,
        resolution: '4K',
        orientation: 'landscape',
        width: 4096,
        height: 2304,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== ProRes 422 Tests =====

    testWidgets('ProRes 422 1080p landscape', (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes 422 tests only run on macOS');
        return;
      }
      await runCodecTest(
        tester: tester,
        testName: 'ProRes 422 1080p',
        codec: VideoCodec.prores422,
        resolution: '1080p',
        orientation: 'landscape',
        width: 1920,
        height: 1080,
        setProjectId: (id) => testProjectId = id,
      );
    });

    testWidgets('ProRes 422 portrait', (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes 422 tests only run on macOS');
        return;
      }
      await runCodecTest(
        tester: tester,
        testName: 'ProRes 422 portrait',
        codec: VideoCodec.prores422,
        resolution: '1080p',
        orientation: 'portrait',
        width: 1080,
        height: 1920,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== ProRes 422 HQ Tests =====

    testWidgets('ProRes 422 HQ 1080p landscape', (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes 422 tests only run on macOS');
        return;
      }
      await runCodecTest(
        tester: tester,
        testName: 'ProRes 422 HQ 1080p',
        codec: VideoCodec.prores422hq,
        resolution: '1080p',
        orientation: 'landscape',
        width: 1920,
        height: 1080,
        setProjectId: (id) => testProjectId = id,
      );
    });

    // ===== Transparent Video Tests =====

    testWidgets('ProRes 4444 transparent 1080p (macOS only)', (tester) async {
      if (!Platform.isMacOS && !Platform.isIOS) {
        markTestSkipped('ProRes 4444 test only runs on Apple platforms');
        return;
      }

      await runCodecTest(
        tester: tester,
        testName: 'ProRes 4444 transparent',
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

    testWidgets('VP9 transparent 1080p (non-Apple platforms)', (tester) async {
      if (Platform.isMacOS || Platform.isIOS) {
        markTestSkipped(
          'VP9 transparent test skipped on Apple (use ProRes 4444)',
        );
        return;
      }

      await runCodecTest(
        tester: tester,
        testName: 'VP9 transparent',
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

    // ===== Transparent PNGs + Solid Video Background Tests =====

    testWidgets('transparent PNGs with solid black video background (H.264)', (
      tester,
    ) async {
      await runCodecTest(
        tester: tester,
        testName: 'Transparent PNGs + solid bg H.264',
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

    testWidgets(
      'transparent PNGs with solid custom color video background (ProRes 422)',
      (tester) async {
        if (!Platform.isMacOS) {
          markTestSkipped('ProRes 422 tests only run on macOS');
          return;
        }
        await runCodecTest(
          tester: tester,
          testName: 'Transparent PNGs + custom bg ProRes 422',
          codec: VideoCodec.prores422,
          resolution: '1080p',
          orientation: 'landscape',
          width: 1920,
          height: 1080,
          transparent: true,
          videoBackground: VideoBackground.solidColor('#1A1A2E'),
          setProjectId: (id) => testProjectId = id,
        );
      },
    );

    // ===== Codec Change Cleanup Test =====

    testWidgets('codec change produces correct output extension', (
      tester,
    ) async {
      if (!Platform.isMacOS) {
        markTestSkipped('Extension change test requires ProRes (macOS only)');
        return;
      }
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Codec Change Test',
        'face',
        timestamp,
      );
      final pid = testProjectId.toString();

      // Set up with H.264
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        pid,
      );
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Compile as H.264
      var success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue);

      final mp4Path = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      expect(await File(mp4Path).exists(), isTrue);
      expect(p.extension(mp4Path), '.mp4');

      // Switch to ProRes 422
      await DB.instance.setSettingByTitle('video_codec', 'prores422', pid);

      success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue);

      final movPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.prores422,
      );
      expect(await File(movPath).exists(), isTrue);
      expect(p.extension(movPath), '.mov');
    });

    testWidgets('codec switch H.264 to HEVC produces valid output', (
      tester,
    ) async {
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
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Codec Switch Test',
        'face',
        timestamp,
      );
      final pid = testProjectId.toString();

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        pid,
      );
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Compile as H.264
      var success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue);

      // Switch to HEVC
      await DB.instance.setSettingByTitle('video_codec', 'hevc', pid);

      success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue);

      final mp4Path = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.hevc,
      );
      expect(await File(mp4Path).exists(), isTrue);
      expect(p.extension(mp4Path), '.mp4');
    });
  });
}
