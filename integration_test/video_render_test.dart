import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/screens/create_page.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/log_service.dart';
import 'package:agelapse/services/video_diagnostics.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/video_utils.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// Checks that a video compiled on this device actually renders on the Create
/// page, using the page's own playback diagnostics (VideoDiagnostics), and
/// that the platform-view fallback works when the screen is black.
///
/// Written for a report of a black in-app video on iPhone 17 / iOS 27, where
/// the player ran normally but showed no picture. iOS only: the frame check
/// relies on the native video diagnostics plugin.
///
/// Run with: `flutter test integration_test/video_render_test.dart -d <device>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  test_config.isTestMode = true;

  int? projectId;

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
    // main() skips this in test mode; the assertions read the log file.
    await LogService.instance.initialize();
  });

  tearDown(() async {
    VideoDiagnostics.debugFrameCheckOverride = null;
    if (projectId == null) return;
    try {
      final projectDir = await DirUtils.getProjectDirPath(projectId!);
      if (await Directory(projectDir).exists()) {
        await deleteQuietly(Directory(projectDir));
      }
      await DB.instance.deleteProject(projectId!);
    } catch (_) {}
    projectId = null;
  });

  /// Compiles a portrait 1080p H.264 video on the device and shows the Create
  /// page for it, then returns the page's [PLAYER] log lines once the frame
  /// check (and any fallback) has run.
  Future<String> playOnCreatePage(WidgetTester tester) async {
    app.main();
    await pumpUntilAppReady(tester);

    final id = await DB.instance.addProject(
      'Video render test',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    projectId = id;
    final pid = id.toString();
    await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
    await DB.instance.setSettingByTitle('project_orientation', 'portrait', pid);
    await DB.instance.setSettingByTitle(
      'video_codec',
      VideoCodec.h264.name,
      pid,
    );
    await _writeStabilizedFrames(id, 'portrait', 1080, 1920, 20);

    final compiled = await VideoUtils.createTimelapseFromProjectId(id, null);
    expect(compiled, isTrue, reason: 'on-device compilation failed');

    await LogService.instance.clearLogs();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatePage(
            projectId: id,
            projectName: 'Video render test',
            stabilizingRunningInMain: false,
            unstabilizedPhotoCount: 0,
            photoIndex: 0,
            videoCreationActiveInMain: false,
            currentFrame: 0,
            cancelStabCallback: () async {},
            goToPage: (_) {},
            prevIndex: 0,
            hideNavBar: () async {},
            progressPercent: 0,
            stabCallback: () async {},
            refreshSettings: () async {},
            clearRawAndStabPhotos: () {},
            recompileVideoCallback: () async {},
            minutesRemaining: '',
          ),
        ),
      ),
    );

    // Player setup, the 3 s frame-check delay, the ~2.5 s frame probe, and the
    // player-layer log 2 s after a fallback.
    await pumpFor(tester, const Duration(seconds: 12));
    expect(find.byType(Chewie), findsOneWidget, reason: 'player never shown');

    await LogService.instance.flush();
    final report = (await LogService.instance.getLogContent())
        .split('\n')
        .where((line) => line.contains('[PLAYER]'))
        .join('\n');
    // ignore: avoid_print
    print('VIDEO_RENDER_LOG\n$report');
    return report;
  }

  testWidgets('compiled video renders on the Create page', (tester) async {
    if (!Platform.isIOS) {
      markTestSkipped('The frame check is iOS only');
      return;
    }
    final report = await playOnCreatePage(tester);

    expect(report, contains('Player initialized (textureView)'));
    expect(report, contains('AVFoundation track: vide avc1 1080.0x1920.0'));
    expect(report, contains('verdict ok'), reason: report);
    expect(report, isNot(contains('switching to the platform-view player')));
  });

  testWidgets('a black screen falls back to the platform-view player', (
    tester,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('The frame check is iOS only');
      return;
    }
    // Keep the real decode results but report the screen as black.
    VideoDiagnostics.debugFrameCheckOverride = (measured) => FrameCheck(
      screenLuma: 0,
      screenChroma: 0,
      framesDecoded: measured.framesDecoded,
      decodedLuma: measured.decodedLuma,
    );
    final report = await playOnCreatePage(tester);

    expect(report, contains('verdict notRendered'), reason: report);
    expect(report, contains('switching to the platform-view player'));
    expect(report, contains('Player initialized (platformView)'));
    expect(report, contains('readyForDisplay: true'), reason: report);
  });
}

/// Writes bright color-bar PNGs as already-stabilized photos.
Future<void> _writeStabilizedFrames(
  int projectId,
  String orientation,
  int width,
  int height,
  int count,
) async {
  final dir = Directory(
    p.join(await DirUtils.getStabilizedDirPath(projectId), orientation),
  );
  await dir.create(recursive: true);
  const colors = [
    [255, 0, 0],
    [0, 255, 0],
    [255, 255, 0],
    [0, 0, 255],
    [255, 0, 255],
    [0, 255, 255],
  ];
  final barWidth = width ~/ colors.length;
  for (var i = 0; i < count; i++) {
    final timestamp = 1000000000 + i * 1000;
    final image = img.Image(width: width, height: height);
    for (var b = 0; b < colors.length; b++) {
      final c = colors[(b + i) % colors.length];
      img.fillRect(
        image,
        x1: b * barWidth,
        y1: 0,
        x2: (b + 1) * barWidth - 1,
        y2: height - 1,
        color: img.ColorRgb8(c[0], c[1], c[2]),
      );
    }
    final png = img.encodePng(image);
    await File(p.join(dir.path, '$timestamp.png')).writeAsBytes(png);
    await DB.instance.addPhoto(
      timestamp.toString(),
      projectId,
      '.png',
      png.length,
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
