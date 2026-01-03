import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/utils/video_utils.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// Integration tests for video compilation with ffmpeg.
///
/// These tests verify that video encoding works correctly across
/// different resolutions and codecs (h264_videotoolbox, hevc_videotoolbox, libx264).
///
/// Run with: `flutter test integration_test/video_compilation_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Video Compilation Tests', () {
    int? testProjectId;

    setUpAll(() async {
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      testProjectId = null;
    });

    tearDown(() async {
      if (testProjectId != null) {
        try {
          // Clean up project directory (includes videos, stabilized, etc.)
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

    /// Creates test PNG frames in the stabilized directory
    Future<void> setupTestFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int frameCount,
    ) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientationDir = Directory(p.join(stabDir, orientation));
      await orientationDir.create(recursive: true);

      // Generate simple colored frames
      for (int i = 0; i < frameCount; i++) {
        final timestamp = 1000000000 + (i * 1000);
        final framePath = p.join(orientationDir.path, '$timestamp.png');

        // Create a simple colored image
        final image = img.Image(width: width, height: height);
        // Fill with a gradient color based on frame number
        final color = img.ColorRgb8(
          (i * 80) % 256,
          (i * 60 + 100) % 256,
          (i * 40 + 50) % 256,
        );
        img.fill(image, color: color);

        // Save as PNG
        final pngBytes = img.encodePng(image);
        await File(framePath).writeAsBytes(pngBytes);

        // Add to database
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

    testWidgets('compiles video at 1080p resolution', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Create project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Video Test 1080p',
        'face',
        timestamp,
      );

      // Set resolution to 1080p
      await DB.instance.setSettingByTitle(
        'video_resolution',
        '1080p',
        testProjectId.toString(),
      );
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        testProjectId.toString(),
      );

      // Create test frames (1920x1080)
      await setupTestFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Compile video
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );

      expect(success, isTrue, reason: '1080p video compilation should succeed');

      // Verify output file exists
      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
      );
      final videoFile = File(videoPath);
      expect(await videoFile.exists(), isTrue,
          reason: 'Video output file should exist');

      final videoSize = await videoFile.length();
      expect(videoSize, greaterThan(1000),
          reason: 'Video file should have reasonable size');
    });

    testWidgets('compiles video at 4K resolution', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Create project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Video Test 4K',
        'face',
        timestamp,
      );

      // Set resolution to 4K
      await DB.instance.setSettingByTitle(
        'video_resolution',
        '4K',
        testProjectId.toString(),
      );
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        testProjectId.toString(),
      );

      // Create test frames (3840x2160 - actual 4K, but use smaller for speed)
      // Using 2304 as short side per app's 4K definition
      await setupTestFrames(testProjectId!, 'landscape', 4096, 2304, 3);

      // Compile video
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );

      expect(success, isTrue, reason: '4K video compilation should succeed');

      // Verify output file exists
      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
      );
      final videoFile = File(videoPath);
      expect(await videoFile.exists(), isTrue,
          reason: 'Video output file should exist');
    });

    testWidgets('compiles video at 8K resolution using HEVC', (tester) async {
      // Skip on non-macOS for now (8K uses hevc_videotoolbox on macOS)
      if (!Platform.isMacOS) {
        markTestSkipped('8K HEVC test only runs on macOS');
        return;
      }

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Create project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Video Test 8K',
        'face',
        timestamp,
      );

      // Set resolution to 8K
      await DB.instance.setSettingByTitle(
        'video_resolution',
        '8K',
        testProjectId.toString(),
      );
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'landscape',
        testProjectId.toString(),
      );

      // Create test frames at 8K (7680x4320)
      // These are synthetic solid-color frames, so they compress very small
      await setupTestFrames(testProjectId!, 'landscape', 7680, 4320, 3);

      // Compile video - this should use hevc_videotoolbox
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );

      expect(success, isTrue,
          reason: '8K video compilation should succeed using HEVC encoder');

      // Verify output file exists
      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
      );
      final videoFile = File(videoPath);
      expect(await videoFile.exists(), isTrue,
          reason: 'Video output file should exist');

      final videoSize = await videoFile.length();
      expect(videoSize, greaterThan(1000),
          reason: 'Video file should have reasonable size');
    });

    testWidgets('compiles portrait video', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Create project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Video Test Portrait',
        'face',
        timestamp,
      );

      // Set portrait orientation
      await DB.instance.setSettingByTitle(
        'video_resolution',
        '1080p',
        testProjectId.toString(),
      );
      await DB.instance.setSettingByTitle(
        'project_orientation',
        'portrait',
        testProjectId.toString(),
      );

      // Create portrait test frames (1080x1920)
      await setupTestFrames(testProjectId!, 'portrait', 1080, 1920, 3);

      // Compile video
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );

      expect(success, isTrue,
          reason: 'Portrait video compilation should succeed');

      // Verify output file exists
      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'portrait',
      );
      final videoFile = File(videoPath);
      expect(await videoFile.exists(), isTrue,
          reason: 'Video output file should exist');
    });

    testWidgets('handles empty project gracefully', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Create project with no photos
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Empty Project',
        'face',
        timestamp,
      );

      // Attempt to compile - should return false, not crash
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );

      expect(success, isFalse,
          reason: 'Empty project should return false, not crash');
    });
  });
}
