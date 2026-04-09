import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/models/video_background.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/video_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration test: transparent project stabilization must preserve alpha,
/// and the compiled video must retain a real alpha channel.
///
/// Regression test for the v2.5.2 bug where `saveStabilizedImage` composited
/// BGRA PNGs onto black before writing to disk, destroying the alpha channel
/// and silently breaking ProRes 4444 / VP9 transparent video export.
///
/// This test exercises the FULL production path:
///   real fixture face photo
///   → FaceStabilizer.stabilize()          [calls saveStabilizedImage]
///   → stabilized PNG channel count assert  [catches the regression]
///   → VideoUtils.createTimelapse
///   → ffprobe pixel-format check
///   → ffmpeg first-frame alpha pixel assert
///
/// Run with:
///   flutter test integration_test/transparent_alpha_pipeline_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Transparent Alpha Pipeline', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await IsolatePool.instance.initialize();
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
      await IsolatePool.instance.dispose();
      await cleanupFixtures();
    });

    testWidgets(
      'stabilize() preserves alpha for transparent project and video retains alpha channel',
      (tester) async {
        // Requires macOS or Linux (ffprobe/ffmpeg available).
        if (!Platform.isMacOS && !Platform.isLinux) {
          markTestSkipped(
            'Transparent alpha probe requires macOS or Linux with ffprobe/ffmpeg',
          );
          return;
        }

        // Verify ffprobe and ffmpeg are available.
        const ffprobePath = '/opt/homebrew/bin/ffprobe';
        const ffmpegPath = '/opt/homebrew/bin/ffmpeg';
        final hasFfprobe = await File(ffprobePath).exists() ||
            (await Process.run('which', ['ffprobe'])).exitCode == 0;
        final hasFfmpeg = await File(ffmpegPath).exists() ||
            (await Process.run('which', ['ffmpeg'])).exitCode == 0;

        if (!hasFfprobe || !hasFfmpeg) {
          markTestSkipped(
            'ffprobe and ffmpeg are required for this test. '
            'Install via: brew install ffmpeg',
          );
          return;
        }

        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // ── 1. Load fixture face photo ──────────────────────────────────
        await preloadFixtures();
        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final fixturePath = await getSampleFacePathAsync(1);
        if (!await File(fixturePath).exists()) {
          markTestSkipped('Face fixture day1.jpg not found at $fixturePath');
          return;
        }

        // ── 2. Create transparent project ──────────────────────────────
        final projectTimestamp = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'TransparentAlphaTest',
          'face',
          projectTimestamp,
        );
        final pid = testProjectId.toString();

        const orientation = 'portrait';

        await DB.instance
            .setSettingByTitle('project_orientation', orientation, pid);
        await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
        await DB.instance.setSettingByTitle('aspect_ratio', '16:9', pid);
        await DB.instance
            .setSettingByTitle('background_color', '#TRANSPARENT', pid);

        // On macOS the alpha codec is ProRes 4444; on Linux it is VP9.
        final codec = Platform.isMacOS ? VideoCodec.prores4444 : VideoCodec.vp9;

        await DB.instance.setSettingByTitle('video_codec', codec.name, pid);
        await DB.instance.setSettingByTitle(
          'video_background',
          const VideoBackground.transparent().toDbValue(),
          pid,
        );

        // ── 3. Set up project directories ──────────────────────────────
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        await Directory(rawDir).create(recursive: true);

        final stabDir = await DirUtils.getStabilizedDirPath(testProjectId!);
        await Directory(p.join(stabDir, orientation)).create(recursive: true);

        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
        await Directory(p.join(thumbDir, 'stabilized', orientation))
            .create(recursive: true);

        final failDir = await DirUtils.getFailureDirPath(testProjectId!);
        await Directory(failDir).create(recursive: true);

        // ── 4. Copy fixture into raw dir and register in DB ────────────
        const ts = '1000000000';
        final rawPath = p.join(rawDir, '$ts.jpg');
        await File(fixturePath).copy(rawPath);
        final fileSize = await File(rawPath).length();

        await DB.instance.addPhoto(
          ts,
          testProjectId!,
          '.jpg',
          fileSize,
          '$ts.jpg',
          orientation,
        );

        // ── 5. Run the real stabilization pipeline ─────────────────────
        // This is the critical path — stabilize() calls saveStabilizedImage,
        // which is where the v2.5.2 regression lived.
        final settings = await StabilizationSettings.load(testProjectId!);
        final stabilizer =
            FaceStabilizer(testProjectId!, () {}, settings: settings);
        await stabilizer.init();

        late StabilizationResult stabResult;
        try {
          stabResult = await stabilizer.stabilize(rawPath, null, () {});
        } finally {
          await stabilizer.dispose();
        }

        expect(
          stabResult.success,
          isTrue,
          reason:
              'FaceStabilizer.stabilize() must succeed on the day1 face fixture. '
              'If this fails, the fixture may not have a detectable face or '
              'stabilization settings are misconfigured.',
        );

        // ── 6. Assert stabilized PNG has 4 channels (BGRA) ────────────
        // This is the core regression assertion. With the bug, saveStabilizedImage
        // would composite the BGRA PNG onto black, producing a 3-channel BGR PNG.
        // With the fix, the BGRA PNG is written to disk as-is (4 channels).
        final stabilizedPngPath = p.join(stabDir, orientation, '$ts.png');
        expect(
          await File(stabilizedPngPath).exists(),
          isTrue,
          reason:
              'Stabilized PNG must exist at $stabilizedPngPath after stabilize()',
        );

        final pngBytes = await File(stabilizedPngPath).readAsBytes();
        final decoded = img.decodePng(pngBytes);
        expect(
          decoded,
          isNotNull,
          reason: 'Stabilized PNG must decode as a valid image',
        );
        expect(
          decoded!.numChannels,
          equals(4),
          reason:
              'REGRESSION: stabilized PNG for a transparent project must have '
              '4 channels (BGRA). Got ${decoded.numChannels} channels. '
              'This means saveStabilizedImage composited the PNG onto black, '
              'destroying the alpha channel. See v2.5.2 fix.',
        );

        // At least one warpAffine border pixel must have alpha < 255.
        bool foundTransparentEdge = false;
        outerPng:
        for (int y = 0; y < decoded.height; y++) {
          for (int x = 0; x < decoded.width; x++) {
            if (decoded.getPixel(x, y).a < 255) {
              foundTransparentEdge = true;
              break outerPng;
            }
          }
        }
        expect(
          foundTransparentEdge,
          isTrue,
          reason:
              'At least one pixel in the stabilized PNG must be transparent '
              '(warpAffine border). If all pixels are opaque, the alpha channel '
              'was destroyed before the PNG was written to disk.',
        );

        // ── 7. Mark photo as stabilized so VideoUtils can find it ──────
        await DB.instance.setPhotoStabilized(
          ts,
          testProjectId!,
          orientation,
          '16:9',
          '1080p',
          stabResult.finalScore ?? 0.0,
          stabResult.finalEyeDistance ?? 0.421875,
        );

        // ── 8. Compile video ────────────────────────────────────────────
        final compileSuccess = await VideoUtils.createTimelapseFromProjectId(
          testProjectId!,
          null,
        );
        expect(
          compileSuccess,
          isTrue,
          reason: 'createTimelapseFromProjectId must succeed',
        );

        // ── 9. Assert output video exists ───────────────────────────────
        final videoPath = await DirUtils.getVideoOutputPath(
          testProjectId!,
          orientation,
          codec: codec,
        );
        expect(
          await File(videoPath).exists(),
          isTrue,
          reason: 'Output video must exist at $videoPath',
        );

        // ── 10. ffprobe: assert pixel format retains alpha ──────────────
        final ffprobeResult = await Process.run(
          ffprobePath,
          [
            '-v',
            'error',
            '-select_streams',
            'v:0',
            '-show_entries',
            'stream=pix_fmt',
            '-of',
            'csv=p=0',
            videoPath,
          ],
        );
        expect(
          ffprobeResult.exitCode,
          equals(0),
          reason: 'ffprobe must exit cleanly. stderr: ${ffprobeResult.stderr}',
        );

        final pixFmt = (ffprobeResult.stdout as String).trim();
        // yuva444p12le is what prores_ks produces on this machine (12-bit ProRes 4444).
        const alphaPxFmts = [
          'yuva444p10le',
          'yuva444p12le',
          'yuva420p',
          'yuva420p10le',
          'yuva422p10le',
        ];
        expect(
          alphaPxFmts.contains(pixFmt),
          isTrue,
          reason: 'Output pixel format must be alpha-capable. '
              'Got: "$pixFmt". Expected one of: $alphaPxFmts. '
              'REGRESSION: the compiled video has lost its alpha channel.',
        );

        // ── 11. ffmpeg: extract first frame, assert alpha pixels ────────
        final tmpDir = Directory.systemTemp.createTempSync('alpha_test_');
        final firstFramePath = p.join(tmpDir.path, 'frame0.png');
        try {
          final ffmpegResult = await Process.run(
            ffmpegPath,
            [
              '-y',
              '-i',
              videoPath,
              '-vframes',
              '1',
              '-vf',
              'format=rgba',
              firstFramePath,
            ],
          );
          expect(
            ffmpegResult.exitCode,
            equals(0),
            reason: 'ffmpeg frame extraction must succeed. '
                'stderr: ${ffmpegResult.stderr}',
          );

          final frameBytes = await File(firstFramePath).readAsBytes();
          final frame = img.decodePng(frameBytes);
          expect(frame, isNotNull,
              reason: 'Extracted first frame must decode as a valid PNG');
          expect(
            frame!.numChannels,
            equals(4),
            reason: 'Extracted first frame must have 4 channels (RGBA). '
                'REGRESSION: alpha channel was destroyed during compilation.',
          );

          bool foundTransparentVideoPixel = false;
          outerVideo:
          for (int y = 0; y < frame.height; y++) {
            for (int x = 0; x < frame.width; x++) {
              if (frame.getPixel(x, y).a < 255) {
                foundTransparentVideoPixel = true;
                break outerVideo;
              }
            }
          }
          expect(
            foundTransparentVideoPixel,
            isTrue,
            reason: 'At least one pixel in the exported video frame must have '
                'alpha < 255. REGRESSION: all pixels are fully opaque, '
                'meaning alpha was composited onto black during stabilization '
                'or video compilation.',
          );
        } finally {
          try {
            tmpDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      },
    );
  });
}
