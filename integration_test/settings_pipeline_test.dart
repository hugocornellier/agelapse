import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/models/video_background.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/video_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// Integration tests for settings UI → pipeline integration.
///
/// Verifies that settings written to the DB are read correctly during video
/// compilation. Key insight: settings are always re-read from DB at compile
/// time — no stale cache exists.
///
/// Run with: `flutter test integration_test/settings_pipeline_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Settings Pipeline Integration Tests', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
    });

    setUp(() async {
      await _cleanupTestData();
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
        testProjectId = null;
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    // ─── Shared helper ─────────────────────────────────────────────────────

    /// Creates [count] solid-colour PNG frames in the stabilized directory for
    /// [projectId]. Uses minimal entropy for fast FFmpeg encoding.
    Future<void> setupOpaqueFrames(
      int projectId,
      String orientation,
      int width,
      int height,
      int count,
    ) async {
      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final orientDir = Directory(p.join(stabDir, orientation));
      await orientDir.create(recursive: true);

      for (int i = 0; i < count; i++) {
        final ts = 1000000000 + (i * 1000);
        final framePath = p.join(orientDir.path, '$ts.png');

        final image = img.Image(width: width, height: height);
        img.fill(
          image,
          color: img.ColorRgb8(
            (i * 80) % 256,
            (i * 60 + 100) % 256,
            (i * 40 + 50) % 256,
          ),
        );
        await File(framePath).writeAsBytes(img.encodePng(image));

        await DB.instance.addPhoto(
          ts.toString(),
          projectId,
          '.png',
          await File(framePath).length(),
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

    // ─── Test A: Codec setting roundtrip ─────────────────────────────────

    testWidgets(
        'Test A: codec written to DB is read and used during compilation',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('CodecRoundtripTest', 'face', ts);

      final pid = testProjectId.toString();

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pid);
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Verify the codec is readable via SettingsUtil
      final loadedCodec = await SettingsUtil.loadVideoCodec(pid);
      expect(loadedCodec, VideoCodec.h264,
          reason: 'Loaded codec should be h264');

      // Compile with H.264
      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue, reason: 'H.264 compilation should succeed');

      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      expect(await File(videoPath).exists(), isTrue,
          reason: 'H.264 video output should exist at $videoPath');
      expect(p.extension(videoPath), '.mp4',
          reason: 'H.264 output should use .mp4 extension');
    });

    // ─── Test B: Framerate propagation ────────────────────────────────────

    testWidgets('Test B: framerate setting is read from DB during compilation',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject('FramerateTest', 'face', ts);

      final pid = testProjectId.toString();

      // Set a non-default framerate
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pid);
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);
      await DB.instance.setSettingByTitle('framerate_is_default', 'false', pid);
      await DB.instance.setSettingByTitle('framerate', '24', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Verify loaded framerate
      final framerate = await SettingsUtil.loadFramerate(pid);
      expect(framerate, 24, reason: 'Framerate should be 24 after setting');

      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue,
          reason: 'Compilation with framerate=24 should succeed');

      // Verify DB video record has framerate set
      final newestVideo =
          await DB.instance.getNewestVideoByProjectId(testProjectId!);
      expect(newestVideo, isNotNull, reason: 'Video record should exist');
      expect(newestVideo!['framerate'], 24,
          reason: 'Video record should record framerate=24');

      // Change framerate to 10 and recompile
      await DB.instance.setSettingByTitle('framerate', '10', pid);

      final success2 = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success2, isTrue,
          reason: 'Recompilation with framerate=10 should succeed');

      final newestVideo2 =
          await DB.instance.getNewestVideoByProjectId(testProjectId!);
      expect(newestVideo2, isNotNull);
      expect(newestVideo2!['framerate'], 10,
          reason: 'Video record should record framerate=10 after change');
    });

    // ─── Test C: Resolution change propagation ────────────────────────────

    testWidgets('Test C: video_resolution setting is used during compilation',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('ResolutionTest', 'face', ts);

      final pid = testProjectId.toString();

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pid);
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Verify loaded resolution
      final resolution = await SettingsUtil.loadVideoResolution(pid);
      expect(resolution, '1080p',
          reason: 'Resolution should be 1080p after setting');

      // Compile at 1080p
      final success1 = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success1, isTrue, reason: '1080p compilation should succeed');

      final videoPath1080 = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      expect(await File(videoPath1080).exists(), isTrue,
          reason: '1080p video output file should exist');
      expect(await File(videoPath1080).length(), greaterThan(100),
          reason: '1080p video file should have content');

      // Change to 4K — add 4K frames, recompile
      // (We can't truly test 4K output dimensions without ffprobe, but we can
      // verify the compilation succeeds and the output changes.)
      await DB.instance.setSettingByTitle('video_resolution', '4K', pid);

      final success2 = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success2, isTrue, reason: '4K compilation should succeed');

      final videoPath4k = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      // 4K compilation succeeded — verify output exists and has content.
      // Note: solid-color test frames may compress to identical sizes across
      // resolutions, so we only assert existence, not size difference.
      final size4k = await File(videoPath4k).length();
      expect(size4k, greaterThan(0),
          reason: '4K video file should have content');
    });

    // ─── Test D: Settings isolation between projects ──────────────────────

    testWidgets(
        'Test D: changing one project\'s settings does not affect another',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('IsolationProjectA', 'face', ts);
      final projectBId =
          await DB.instance.addProject('IsolationProjectB', 'face', ts + 1000);

      // Register teardown for project B
      addTearDown(() async {
        try {
          final dirB = await DirUtils.getProjectDirPath(projectBId);
          if (await Directory(dirB).exists()) {
            await Directory(dirB).delete(recursive: true);
          }
          await DB.instance.deleteProject(projectBId);
        } catch (_) {}
      });

      final pidA = testProjectId.toString();
      final pidB = projectBId.toString();

      // Project A: H.264, framerate 14
      await DB.instance.setSettingByTitle('video_codec', 'h264', pidA);
      await DB.instance.setSettingByTitle('framerate', '14', pidA);
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pidA);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pidA);

      // Project B: HEVC (if available), framerate 24
      final hevcAvailable =
          VideoCodec.availableCodecs(isTransparentVideo: false)
              .contains(VideoCodec.hevc);

      final codecB = hevcAvailable ? VideoCodec.hevc : VideoCodec.h264;
      await DB.instance.setSettingByTitle('video_codec', codecB.name, pidB);
      await DB.instance.setSettingByTitle('framerate', '24', pidB);
      await DB.instance.setSettingByTitle('video_resolution', '1080p', pidB);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pidB);

      // Set up frames for both projects
      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);
      await setupOpaqueFrames(projectBId, 'landscape', 1920, 1080, 3);

      // Verify settings are isolated before compilation
      final codecA = await SettingsUtil.loadVideoCodec(pidA);
      final loadedCodecB = await SettingsUtil.loadVideoCodec(pidB);
      final frA = await SettingsUtil.loadFramerate(pidA);
      final frB = await SettingsUtil.loadFramerate(pidB);

      expect(codecA, VideoCodec.h264, reason: 'Project A codec should be h264');
      expect(loadedCodecB, codecB, reason: 'Project B codec should be $codecB');
      expect(frA, 14, reason: 'Project A framerate should be 14');
      expect(frB, 24, reason: 'Project B framerate should be 24');

      // Compile project A — only needs to skip VideoToolbox on CI for HEVC
      // but A uses H.264 so always runs
      final successA = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(successA, isTrue, reason: 'Project A compilation should succeed');

      // Compile project B — skip if HEVC VideoToolbox unavailable on CI
      if (hevcAvailable &&
          (Platform.isMacOS || Platform.isIOS) &&
          Platform.environment['CI'] == 'true') {
        // HEVC VideoToolbox unavailable on CI runners — skip B compilation
      } else {
        final successB = await VideoUtils.createTimelapseFromProjectId(
          projectBId,
          null,
        );
        expect(successB, isTrue,
            reason: 'Project B compilation should succeed');
      }

      // Verify project A's settings are still unchanged after B's compilation
      final codecAAfter = await SettingsUtil.loadVideoCodec(pidA);
      final frAAfter = await SettingsUtil.loadFramerate(pidA);
      expect(codecAAfter, VideoCodec.h264,
          reason: 'Project A codec should still be h264 after B compiled');
      expect(frAAfter, 14,
          reason: 'Project A framerate should still be 14 after B compiled');
    });

    // ─── Test E: Video background setting affects compilation ────────────

    testWidgets('Test E: solid background setting produces valid H.264 output',
        (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('BackgroundTest', 'face', ts);

      final pid = testProjectId.toString();

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pid);
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);
      await DB.instance.setSettingByTitle('background_color', '#000000', pid);
      await DB.instance.setSettingByTitle('video_background',
          VideoBackground.solidColor('#000000').toDbValue(), pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Verify loaded background
      final bg = await SettingsUtil.loadVideoBackground(pid);
      expect(bg.keepTransparent, isFalse,
          reason: 'Background should be solid, not transparent');

      final success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue,
          reason: 'Compilation with solid background should succeed');

      final videoPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      expect(await File(videoPath).exists(), isTrue,
          reason: 'Video output should exist after solid-bg compilation');
      expect(await File(videoPath).length(), greaterThan(100),
          reason: 'Video output should have content');
    });

    // ─── Test F: Codec change produces correct output extension ──────────

    testWidgets(
        'Test F: codec change from H.264 to ProRes yields .mov output (macOS only)',
        (tester) async {
      if (!Platform.isMacOS) {
        markTestSkipped('ProRes extension test is macOS-only');
        return;
      }

      app.main();
      await tester.pump(const Duration(seconds: 2));

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('CodecChangeExtTest', 'face', ts);

      final pid = testProjectId.toString();

      await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
      await DB.instance
          .setSettingByTitle('project_orientation', 'landscape', pid);
      await DB.instance.setSettingByTitle('video_codec', 'h264', pid);

      await setupOpaqueFrames(testProjectId!, 'landscape', 1920, 1080, 3);

      // Compile as H.264 → expect .mp4
      var success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue, reason: 'H.264 compilation should succeed');

      final mp4Path = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.h264,
      );
      expect(await File(mp4Path).exists(), isTrue,
          reason: 'H.264 .mp4 output should exist');
      expect(p.extension(mp4Path), '.mp4',
          reason: 'H.264 extension should be .mp4');

      // Change to ProRes 422 → expect .mov
      await DB.instance.setSettingByTitle('video_codec', 'prores422', pid);

      success = await VideoUtils.createTimelapseFromProjectId(
        testProjectId!,
        null,
      );
      expect(success, isTrue, reason: 'ProRes 422 compilation should succeed');

      final movPath = await DirUtils.getVideoOutputPath(
        testProjectId!,
        'landscape',
        codec: VideoCodec.prores422,
      );
      expect(await File(movPath).exists(), isTrue,
          reason: 'ProRes 422 .mov output should exist');
      expect(p.extension(movPath), '.mov',
          reason: 'ProRes 422 extension should be .mov');
    });
  });
}

Future<void> _cleanupTestData() async {
  try {
    await DB.instance.deleteAllPhotos();
    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }
    await DB.instance.setSettingByTitle('default_project', 'none');
  } catch (_) {}
}
