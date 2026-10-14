import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/stabilization_state.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'memory_probe_utils.dart';
import 'test_utils.dart';

/// A large zip import on a real phone, the way #15 hit it: one zip of
/// hundreds of phone-sized photos, then the app stabilizing and compiling
/// them by itself.
///
/// The zip is made by tool/testlab/make_bulk_zip.py and pushed to the phone
/// at /sdcard/agelapse_bulk_import.zip (Test Lab's --other-files, or adb
/// push). MainActivityTest copies it into the app's files folder before the
/// app starts; without it this test skips, so it is not part of any suite.
/// See tool/testlab/README.md for how to run it.
///
/// The photos are imported through the gallery's own zip import. Then the
/// project is opened in the app like a user would, and the app's own
/// stabilization and auto-compile take it from there. Every 15 seconds the
/// test logs one `AGELAPSE_BULK {...}` line to logcat: photos stabilized and
/// failed, the stabilization state, memory, and elapsed time. A crash ends
/// the run; the last line shows how far it got and how memory was trending.
///
/// Dart defines:
/// - BULK_BUDGET_MINUTES (default 40): stop watching after this long, so
///   the run ends inside Test Lab's 45 minute limit. Ending early is not a
///   failure; the summary says how far it got.
/// - BULK_DATE_STAMPS (default false): turn on date stamps, the overlay path
///   behind an earlier Android 16 compile crash (#33).
/// - BULK_EXPECT_VIDEO (default false): fail unless every photo is done and
///   a video was compiled within the budget.
/// - BULK_ZIP_PATH (default empty): read the zip from this path instead of the
///   app's files folder, for running the same test on a desktop.
/// - BULK_HEADLESS (default false): don't start the app's UI; drive the
///   stabilization service directly. Comparing a headless run with a normal
///   one tells UI memory (thumbnails, image cache) from pipeline memory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const budgetMinutes = int.fromEnvironment(
    'BULK_BUDGET_MINUTES',
    defaultValue: 40,
  );
  const dateStamps = bool.fromEnvironment('BULK_DATE_STAMPS');
  const expectVideo = bool.fromEnvironment('BULK_EXPECT_VIDEO');
  const zipPath = String.fromEnvironment('BULK_ZIP_PATH');
  const headless = bool.fromEnvironment('BULK_HEADLESS');

  testWidgets('a large zip imports, stabilizes and compiles without crashing', (
    tester,
  ) async {
    final zip = File(
      zipPath.isNotEmpty
          ? zipPath
          : p.join(
              (await getApplicationSupportDirectory()).path,
              'agelapse_bulk_import.zip',
            ),
    );
    if (!await zip.exists()) {
      markTestSkipped('No zip at ${zip.path} (see tool/testlab/README.md)');
      return;
    }

    final clock = Stopwatch()..start();
    // Debug builds only; null leaves the Dart heap, external and GC figures
    // out of the report.
    final vm = await VmProbe.connect();
    Future<void> report(
      String phase, [
      Map<String, Object?> extra = const {},
    ]) async {
      final dart = vm != null ? await vm.measure() : const <String, Object?>{};
      // print, not debugPrint: debugPrint throttles and can drop lines.
      // ignore: avoid_print
      print(
        'AGELAPSE_BULK ${jsonEncode({'phase': phase, 'elapsedS': clock.elapsed.inSeconds, ...processMemory(), ...mallocStats(), ...dart, ...extra})}',
      );
    }

    initDatabase();
    await DB.instance.createTablesIfNotExist();
    final projectId = await DB.instance.addProject(
      'Bulk import',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    if (dateStamps) {
      await DB.instance.setSettingByTitle(
        'export_date_stamp_enabled',
        'true',
        '$projectId',
      );
    }
    await report('start', {
      'zipMb': (await zip.length()) ~/ 1000000,
      'budgetMinutes': budgetMinutes,
      'dateStamps': dateStamps,
    });

    // The gallery's own zip import, as after picking a zip.
    var inZip = 0;
    var lastProgress = -1;
    final notifier = ValueNotifier<String>('');
    await GalleryUtils.processPickedFile(
      zip,
      projectId,
      notifier,
      onImagesLoaded: () {},
      setProgressInMain: (progress) {
        if (progress ~/ 10 != lastProgress ~/ 10) {
          lastProgress = progress;
          unawaited(report('importing', {'percent': progress, 'inZip': inZip}));
        }
      },
      increaseSuccessfulImportCount: () {},
      increasePhotosImported: (count) => inZip += count,
    );
    notifier.dispose();
    // Checked at the end, so a short import still gets stabilized.
    final total = (await DB.instance.getPhotosByProjectID(projectId)).length;
    await report('imported', {'inZip': inZip, 'imported': total});

    await DB.instance.setSettingByTitle('default_project', '$projectId');
    if (headless) {
      // The service alone; it brings up its own isolate pool.
      unawaited(StabilizationService.instance.startStabilization(projectId));
    } else {
      // Open the project like a user: the app stabilizes and compiles it.
      await launchApp(tester);
    }

    final orientation = await SettingsUtil.loadProjectOrientation('$projectId');
    final budget = Duration(minutes: budgetMinutes);
    var done = false;
    var stabilized = 0;
    var failed = 0;
    var hasVideo = false;
    while (clock.elapsed < budget) {
      await tester.pump(const Duration(seconds: 15));
      stabilized = await DB.instance.getStabilizedPhotoCountByProjectID(
        projectId,
        orientation,
      );
      failed = (await DB.instance.getPhotosByProjectID(projectId))
          .where(
            (photo) => photo['stabFailed'] == 1 || photo['noFacesFound'] == 1,
          )
          .length;
      hasVideo = await DB.instance.getNewestVideoByProjectId(projectId) != null;
      final state = StabilizationService.instance.state;
      await report('running', {
        'stabilized': stabilized,
        'failed': failed,
        'total': total,
        'state': state.name,
        'video': hasVideo,
      });
      if (hasVideo && stabilized + failed >= total && !state.isActive) {
        done = true;
        break;
      }
    }

    await report('summary', {
      'done': done,
      'stabilized': stabilized,
      'failed': failed,
      'total': total,
      'video': hasVideo,
      'photosPerMinute': clock.elapsed.inSeconds == 0
          ? 0
          : (stabilized * 60 / clock.elapsed.inSeconds).toStringAsFixed(1),
    });
    expect(total, inZip, reason: 'every photo in the zip should import');
    expect(stabilized, greaterThan(0), reason: 'nothing was stabilized');
    if (expectVideo) {
      expect(done, isTrue, reason: 'all photos and a video within budget');
    }
  }, timeout: const Timeout(Duration(minutes: budgetMinutes + 4)));
}
