import 'dart:convert';
import 'dart:io';

import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/services/crash_loop_guard.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/video_compile_coordinator.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// The crash-loop guard wired into the real app (#15, #42): a project whose
/// compiles kept closing the app is not compiled automatically, a compile the
/// user starts still runs and resumes auto-compile, and a photo the app died
/// on twice is marked failed before stabilization picks it up.
///
/// The guard is off in test mode, so each test installs an active one whose
/// notes start out as a crashed app would have left them. Compiles are
/// guarded as on a phone, where FFmpeg runs inside the app.
///
/// Run with: `flutter test integration_test/crash_loop_guard_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const String orientation = 'landscape';
  const int dayMs = 86400000;
  final CrashLoopGuard original = CrashLoopGuard.instance;
  int? projectId;

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
  });

  tearDown(() async {
    CrashLoopGuard.instance = original;
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

  /// Switches on a guard whose notes are [projects], as the last launch left
  /// them.
  void installGuard(Map<String, Object?> projects) {
    final notes = _Notes(jsonEncode({'version': 1, 'projects': projects}));
    CrashLoopGuard.instance = CrashLoopGuard.forTesting(
      store: notes,
      markPhotoFailed: (projectId, timestamp) =>
          DB.instance.setPhotoStabFailed(timestamp, projectId),
      appVersion: () async => 'test',
      active: true,
      guardCompiles: true,
    );
  }

  String timestampOf(int day) => (1700000000000 + day * dayMs).toString();

  /// A project with [photoCount] photos, one per day, stabilized (with
  /// frames on disk) when [stabilized] is set.
  Future<int> setUpProject(
    WidgetTester tester, {
    required int photoCount,
    required bool stabilized,
  }) async {
    app.main();
    await pumpUntilAppReady(tester);
    final id = await DB.instance.addProject(
      'Crash guard',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    projectId = id;
    final pid = id.toString();
    await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
    await DB.instance.setSettingByTitle(
      'project_orientation',
      orientation,
      pid,
    );
    await DB.instance.setSettingByTitle(
      'video_codec',
      VideoCodec.h264.name,
      pid,
    );
    await DB.instance.setSettingByTitle('framerate', '10', pid);
    await DB.instance.setSettingByTitle('framerate_is_default', 'false', pid);

    final dir = Directory(
      p.join(await DirUtils.getStabilizedDirPath(id), orientation),
    );
    await dir.create(recursive: true);
    for (int i = 0; i < photoCount; i++) {
      final ts = timestampOf(i);
      final image = img.Image(width: 1920, height: 1080);
      img.fill(image, color: img.ColorRgb8(40 * i, 255 - 40 * i, 128));
      final bytes = img.encodePng(image);
      await DB.instance.addPhoto(
        ts,
        id,
        '.png',
        bytes.length,
        '$ts.png',
        orientation,
      );
      if (!stabilized) continue;
      await File(p.join(dir.path, '$ts.png')).writeAsBytes(bytes);
      await DB.instance.setPhotoStabilized(
        ts,
        id,
        orientation,
        '16:9',
        '1080p',
        0.065,
        0.421875,
      );
    }
    return id;
  }

  testWidgets(
    'a project whose compiles kept closing the app is only compiled when the user asks',
    (tester) async {
      final id = await setUpProject(tester, photoCount: 4, stabilized: true);
      installGuard({
        '$id': {'compilesUnfinished': 2, 'compileAppVersion': 'test'},
      });

      // Opening the project: nothing to stabilize, a video is needed, and
      // auto-compile is on in Settings. Paused, it only flags the video.
      expect(
        await StabilizationService.instance.startStabilization(id),
        isTrue,
      );
      expect(await DB.instance.getNewestVideoByProjectId(id), isNull);
      expect(await DB.instance.getNewVideoNeeded(id) ?? 0, greaterThan(0));
      expect(await CrashLoopGuard.instance.isAutoCompilePaused(id), isTrue);

      // The user taps Compile Video, and the app survives it.
      final outcome = await VideoUtils.compileVideo(
        id,
        null,
        reason: 'manual compile',
      );
      expect(outcome, CompileOutcome.published);
      expect(await CrashLoopGuard.instance.isAutoCompilePaused(id), isFalse);
    },
  );

  testWidgets(
    'a photo the app died on twice is marked failed before stabilization picks it up',
    (tester) async {
      final id = await setUpProject(tester, photoCount: 3, stabilized: false);
      final crashed = timestampOf(0);
      installGuard({
        '$id': {
          'photosInFlight': [crashed],
          'photoDeaths': {crashed: 1},
        },
      });

      await CrashLoopGuard.instance.start();

      final photos = await DB.instance.getPhotosByProjectID(id);
      final failed = {
        for (final photo in photos)
          if (photo['stabFailed'] == 1) photo['timestamp'].toString(),
      };
      expect(failed, {crashed});
      final pending = await StabUtils.getUnstabilizedPhotos(id);
      expect(pending.map((photo) => photo['timestamp'].toString()), [
        timestampOf(1),
        timestampOf(2),
      ]);
      expect(
        await CrashLoopGuard.instance.mustStabilizeAlone(id, crashed),
        isTrue,
      );
    },
  );
}

/// Stands in for the guard's notes file.
class _Notes implements CrashGuardStore {
  _Notes(this.contents);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async {
    contents = value;
  }
}
