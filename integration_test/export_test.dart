import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as path;

import 'test_utils.dart';

/// Integration test for the ZIP export feature.
///
/// Tests the full export pipeline on-device:
/// 1. Creates a project and imports test fixture images
/// 2. Calls exportZipFile() to create a ZIP archive
/// 3. Verifies the ZIP is created successfully
///
/// Run on Android 16 emulator:
///   flutter test integration_test/export_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Export ZIP Tests', () {
    int? testProjectId;

    setUpAll(() async {
      await preloadFixtures();
      await DB.instance.createTablesIfNotExist();
    });

    tearDown(() async {
      if (testProjectId != null) {
        // Clean up exports directory
        try {
          final exportsDir = await DirUtils.getExportsDirPath(testProjectId!);
          final dir = Directory(exportsDir);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}

        // Clean up raw photos directory
        try {
          final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
          final dir = Directory(rawDir);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}

        // Delete project from DB
        try {
          await DB.instance.deleteProject(testProjectId!);
        } catch (_) {}
        testProjectId = null;
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    testWidgets('export raw photos to ZIP succeeds', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      if (fixturesUnavailable) {
        markTestSkipped('Fixtures unavailable: $fixtureLoadError');
        return;
      }

      // 1. Create test project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Export Test Project',
        'face',
        timestamp,
      );
      expect(testProjectId, isNotNull);
      expect(testProjectId, isPositive);

      // 2. Copy fixture images to raw photos directory
      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      final List<String> rawImagePaths = [];
      for (int day = 1; day <= 3; day++) {
        final fixturePath = await getSampleFacePathAsync(day);
        final fixtureFile = File(fixturePath);
        expect(
          await fixtureFile.exists(),
          isTrue,
          reason: 'Fixture day$day.jpg should exist at $fixturePath',
        );

        // Use a timestamp-based filename like the app does
        final photoTimestamp = (timestamp + day * 86400000).toString();
        final ext = path.extension(fixturePath);
        final destPath = path.join(rawDir, '$photoTimestamp$ext');

        await fixtureFile.copy(destPath);
        rawImagePaths.add(destPath);

        // Add DB record
        final fileLen = await File(destPath).length();
        await DB.instance.addPhoto(
          photoTimestamp,
          testProjectId!,
          ext,
          fileLen,
          '$photoTimestamp$ext',
          'portrait',
        );
      }

      expect(rawImagePaths.length, 3);

      // Verify files exist on disk
      for (final p in rawImagePaths) {
        expect(await File(p).exists(), isTrue,
            reason: 'Raw image should exist: $p');
      }

      // 3. Run export
      double lastProgress = 0;
      final result = await GalleryUtils.exportZipFile(
        testProjectId!,
        'Export Test Project',
        {'Raw': rawImagePaths, 'Stabilized': []},
        (progress) {
          lastProgress = progress;
        },
      );

      // 4. Verify result
      expect(result, 'success', reason: 'Export should succeed');
      expect(lastProgress, greaterThanOrEqualTo(98.0),
          reason: 'Progress should reach at least 98%');

      // 5. Verify ZIP file exists (check exports dir since actual filename includes timestamp)
      final exportsDir = await DirUtils.getExportsDirPath(testProjectId!);
      final exportsDirEntity = Directory(exportsDir);
      expect(await exportsDirEntity.exists(), isTrue,
          reason: 'Exports directory should exist');

      final zipFiles = await exportsDirEntity
          .list()
          .where((e) => e is File && e.path.endsWith('.zip'))
          .toList();
      expect(zipFiles.isNotEmpty, isTrue,
          reason: 'At least one ZIP file should exist in exports');

      final zipFile = File(zipFiles.first.path);
      final zipSize = await zipFile.length();
      expect(zipSize, greaterThan(0),
          reason: 'ZIP file should not be empty (size=$zipSize)');
    });

    testWidgets('export with empty file list returns error', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Create test project
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Empty Export Test',
        'face',
        timestamp,
      );

      // Export with no files
      final result = await GalleryUtils.exportZipFile(
        testProjectId!,
        'Empty Export Test',
        {'Raw': [], 'Stabilized': []},
        (progress) {},
      );

      expect(result, 'error',
          reason: 'Export with no files should return error');
    });
  });
}
