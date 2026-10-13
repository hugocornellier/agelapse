import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/raw_photo_extension_repair.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/format_decode_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Issue #41: a photo picked as `IMG_0001.HEIC` (the iPhone default) imported
/// fine and had a thumbnail, but on Linux its preview was black, stabilization
/// failed and manual stabilization said "Could not load photo file". The raw
/// file had been saved as `<timestamp>.HEIC` while the database recorded
/// `.heic`, and every later reader rebuilds the path from the database. Only a
/// case-sensitive file system (Linux, Android, iOS) tells the two apart, so the
/// first group passes trivially on macOS and Windows and is the real check on
/// the Linux lane.
///
/// Run with: `flutter test integration_test/import_extension_case_test.dart -d linux`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Import with an upper-case file extension (#41)', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await preloadFixtures();
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
            await deleteQuietly(Directory(projectDir));
          }
          await DB.instance.deleteProject(testProjectId!);
        } catch (_) {}
        testProjectId = null;
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final sample in const [
      (format: 'heic', pickedName: 'IMG_0001.HEIC'),
      (format: 'jpg', pickedName: 'IMG_0002.JPG'),
    ]) {
      testWidgets(
        '${sample.pickedName} is saved where every later lookup expects it',
        (tester) async {
          app.main();
          await tester.pump(const Duration(seconds: 2));

          if (fixturesUnavailable) {
            markTestSkipped('Test fixtures not available: $fixtureLoadError');
            return;
          }

          testProjectId = await DB.instance.addProject(
            'Extension case ${sample.pickedName}',
            'face',
            DateTime.now().millisecondsSinceEpoch,
          );

          final fixturePath = await getFormatSamplePathAsync(
            sample.format,
            'day1',
          );
          if (!await File(fixturePath).exists()) {
            markTestSkipped('${sample.format}/day1 sample not found');
            return;
          }

          final tempDir = await Directory.systemTemp.createTemp('ext_case_');
          final pickedPath = p.join(tempDir.path, sample.pickedName);
          await File(fixturePath).copy(pickedPath);

          final notifier = ValueNotifier<String>('');
          bool imported = false;
          try {
            imported = await GalleryUtils.importXFile(
              XFile(pickedPath),
              testProjectId!,
              notifier,
            );
          } finally {
            notifier.dispose();
            await deleteQuietly(tempDir);
          }
          expect(
            imported,
            isTrue,
            reason: '${sample.pickedName} should import',
          );
          await tester.pump(const Duration(seconds: 3));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(photos, hasLength(1));
          final timestamp = photos.single['timestamp'] as String;
          expect(photos.single['fileExtension'], '.${sample.format}');

          // The gallery preview list, stabilization and manual stabilization
          // all rebuild the raw path from the stored extension.
          final rawPath =
              await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
                timestamp,
                testProjectId!,
              );
          final rawDir = Directory(
            await DirUtils.getRawPhotoDirPath(testProjectId!),
          );
          final onDisk = rawDir.listSync().map((e) => p.basename(e.path));
          expect(
            File(rawPath).existsSync(),
            isTrue,
            reason:
                'The database points at ${p.basename(rawPath)} but photos_raw '
                'holds ${onDisk.toList()}. On a case-sensitive file system the '
                'preview shows black, stabilization fails and manual '
                'stabilization says "Could not load photo file" (#41).',
          );
          expect(await GalleryUtils.getAllRawImagePaths(testProjectId!), [
            rawPath,
          ]);

          // What the preview widget and the stabilizer load through.
          final cvBytes = await FormatDecodeUtils.loadCvCompatibleBytes(
            rawPath,
          );
          if (sample.format == 'heic' && Platform.isWindows) {
            // Windows CI has no HEVC Video Extensions, so the decode itself
            // is optional there. The path checks above are what matter.
            return;
          }
          expect(
            cvBytes,
            isNotNull,
            reason: 'the imported ${sample.format} should load from $rawPath',
          );
          expect(cvBytes!, isNotEmpty);
        },
      );
    }

    testWidgets(
      'a raw file an older version saved with an upper-case extension is '
      'renamed at startup and queued for stabilization',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        testProjectId = await DB.instance.addProject(
          'Extension case repair',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );

        final fixturePath = await getFormatSamplePathAsync('heic', 'day1');
        if (!await File(fixturePath).exists()) {
          markTestSkipped('heic/day1 sample not found');
          return;
        }

        final tempDir = await Directory.systemTemp.createTemp('ext_case_');
        final pickedPath = p.join(tempDir.path, 'day1.heic');
        await File(fixturePath).copy(pickedPath);
        final notifier = ValueNotifier<String>('');
        bool imported = false;
        try {
          imported = await GalleryUtils.importXFile(
            XFile(pickedPath),
            testProjectId!,
            notifier,
          );
        } finally {
          notifier.dispose();
          await deleteQuietly(tempDir);
        }
        expect(imported, isTrue);
        await tester.pump(const Duration(seconds: 3));

        final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(photos, hasLength(1));
        final timestamp = photos.single['timestamp'] as String;
        final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp,
          testProjectId!,
        );
        expect(File(rawPath).existsSync(), isTrue);

        // Leave the file as 2.6.0 and 2.7.0 did for IMG_0001.HEIC, and mark
        // the photo the way five failed stabilization passes would have.
        final legacyPath = p.setExtension(rawPath, '.HEIC');
        await File(rawPath).rename(legacyPath);
        final caseSensitive = !File(rawPath).existsSync();
        for (var i = 0; i < 5; i++) {
          await DB.instance.setPhotoStabFailed(timestamp, testProjectId!);
        }

        final renamed = await RawPhotoExtensionRepair.repairProject(
          testProjectId!,
        );

        expect(renamed, caseSensitive ? 1 : 0);
        expect(
          File(rawPath).existsSync(),
          isTrue,
          reason: 'after the repair the database path must resolve again',
        );
        final rawDir = Directory(
          await DirUtils.getRawPhotoDirPath(testProjectId!),
        );
        expect(rawDir.listSync(), hasLength(1));
        if (caseSensitive) {
          expect(
            p.basename(rawDir.listSync().single.path),
            p.basename(rawPath),
          );
          final repaired = await DB.instance.getPhotosByProjectID(
            testProjectId!,
          );
          expect(
            repaired.single['stabFailed'],
            0,
            reason: 'a renamed photo is queued for stabilization again',
          );
          expect(repaired.single['stabAttempts'] ?? 0, 0);
        }

        if (!Platform.isWindows) {
          final cvBytes = await FormatDecodeUtils.loadCvCompatibleBytes(
            rawPath,
          );
          expect(cvBytes, isNotNull);
        }
      },
    );
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
