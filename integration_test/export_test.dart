import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
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
    final createdZipPaths = <String>{};

    Future<File?> findRecentZipFile({
      required int sinceEpochMs,
      required int projectId,
    }) async {
      final thresholdMs =
          sinceEpochMs - const Duration(seconds: 5).inMilliseconds;
      final exportsDir = Directory(await DirUtils.getExportsDirPath(projectId));

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        File? newest;
        DateTime? newestModified;

        if (await exportsDir.exists()) {
          await for (final entity in exportsDir.list(followLinks: false)) {
            if (entity is! File || !entity.path.endsWith('.zip')) continue;

            final modified = await entity.lastModified();
            if (modified.millisecondsSinceEpoch < thresholdMs) continue;

            if (newestModified == null || modified.isAfter(newestModified)) {
              newest = entity;
              newestModified = modified;
            }
          }
        }

        if (newest != null) {
          createdZipPaths.add(newest.path);
          return newest;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      return null;
    }

    setUpAll(() async {
      initDatabase();
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

      for (final zipPath in createdZipPaths.toList()) {
        try {
          final zipFile = File(zipPath);
          if (await zipFile.exists()) {
            await zipFile.delete();
          }
        } catch (_) {}
      }
      createdZipPaths.clear();
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
        expect(
          await File(p).exists(),
          isTrue,
          reason: 'Raw image should exist: $p',
        );
      }

      // 3. Run export
      final exportStartedAt = DateTime.now().millisecondsSinceEpoch;
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
      expect(
        lastProgress,
        greaterThanOrEqualTo(98.0),
        reason: 'Progress should reach at least 98%',
      );

      // 5. Verify ZIP file exists in the actual save location used by the platform
      final zipFile = await findRecentZipFile(
        sinceEpochMs: exportStartedAt,
        projectId: testProjectId!,
      );
      expect(
        zipFile,
        isNotNull,
        reason: 'A ZIP file should be created after export',
      );
      expect(
        await zipFile!.exists(),
        isTrue,
        reason: 'Created ZIP file should exist on disk',
      );

      final zipSize = await zipFile.length();
      expect(
        zipSize,
        greaterThan(0),
        reason: 'ZIP file should not be empty (size=$zipSize)',
      );
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

      expect(
        result,
        'error',
        reason: 'Export with no files should return error',
      );
    });

    testWidgets('export raw photos uses sourceFilename with duplicate suffixes',
        (
      tester,
    ) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      if (fixturesUnavailable) {
        markTestSkipped('Fixtures unavailable: $fixtureLoadError');
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'Export Source Filename Test',
        'face',
        timestamp,
      );
      expect(testProjectId, isNotNull);

      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      final rawImagePaths = <String>[];
      final sourceFilename = 'IMG_4821.JPG';
      for (int day = 1; day <= 2; day++) {
        final fixturePath = await getSampleFacePathAsync(day);
        final photoTimestamp = (timestamp + day * 1000).toString();
        final destPath = path.join(rawDir, '$photoTimestamp.jpg');

        await File(fixturePath).copy(destPath);
        rawImagePaths.add(destPath);

        final fileLen = await File(destPath).length();
        await DB.instance.addPhoto(
          photoTimestamp,
          testProjectId!,
          '.jpg',
          fileLen,
          '$photoTimestamp.jpg',
          'portrait',
          sourceFilename: sourceFilename,
        );
      }

      final exportStartedAt = DateTime.now().millisecondsSinceEpoch;
      final result = await GalleryUtils.exportZipFile(
        testProjectId!,
        'Export Source Filename Test',
        {'Raw': rawImagePaths, 'Stabilized': []},
        (_) {},
      );

      expect(result, 'success', reason: 'Export should succeed');

      final zipFile = await findRecentZipFile(
        sinceEpochMs: exportStartedAt,
        projectId: testProjectId!,
      );
      expect(zipFile, isNotNull, reason: 'ZIP should be created');

      final zipBytes = await zipFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final exportedNames = archive.files.map((file) => file.name).toSet();

      expect(exportedNames, contains('Raw/IMG_4821.JPG'));
      expect(exportedNames, contains('Raw/IMG_4821 (2).JPG'));
    });
  });
}
