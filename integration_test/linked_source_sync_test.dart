import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import.dart';
import 'package:agelapse/services/project_folder_sync_service.dart';
import 'package:agelapse/services/settings_cache.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/linked_source_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for linked source folder sync.
///
/// Tests the core sync scenarios:
/// 1. New files in linked folder get imported
/// 2. Re-sync skips already-imported files
/// 3. Tombstoned files are not re-imported
/// 4. Subdirectory structure is preserved in sourceRelativePath
///
/// Run with: `flutter test integration_test/linked_source_sync_test.dart -d <platform>`
/// Desktop only (macOS, Linux, Windows).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  int? testProjectId;
  Directory? tempLinkedDir;

  SettingsCache buildCache(String linkedFolderPath) {
    return SettingsCache(
      hasOpenedNonEmptyGallery: false,
      isLightTheme: null,
      noPhotos: true,
      hasViewedFirstVideo: false,
      hasOpenedNotifications: false,
      hasTakenMoreThanOnePhoto: false,
      hasSeenGuideModeTut: false,
      hasTakenFirstPhoto: false,
      streak: 0,
      photoCount: 0,
      firstPhotoDate: '',
      lastPhotoDate: '',
      lengthInDays: 0,
      projectOrientation: 'portrait',
      aspectRatio: '9:16',
      resolution: '1080p',
      watermarkEnabled: false,
      stabilizationMode: 'off',
      image: null,
      eyeOffsetX: 0.0,
      eyeOffsetY: 0.0,
      galleryDateLabelsEnabled: false,
      exportDateStampEnabled: false,
      linkedSourceEnabled: true,
      linkedSourceMode: 'desktop_path',
      linkedSourceDisplayPath: linkedFolderPath,
      linkedSourceRootPath: linkedFolderPath,
    );
  }

  Future<void> cleanupTestData() async {
    try {
      await DB.instance.deleteAllPhotos();
      final projects = await DB.instance.getAllProjects();
      for (final project in projects) {
        await DB.instance.deleteProject(project['id'] as int);
      }
    } catch (_) {}
  }

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
  });

  setUp(() async {
    await cleanupTestData();
    await ProjectFolderSyncService.instance.stopWatching();
  });

  tearDown(() async {
    await ProjectFolderSyncService.instance.stopWatching();

    if (testProjectId != null) {
      try {
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final dir = Directory(rawDir);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
      try {
        await DB.instance.deleteProject(testProjectId!);
      } catch (_) {}
      testProjectId = null;
    }

    if (tempLinkedDir != null) {
      try {
        if (await tempLinkedDir!.exists()) {
          await tempLinkedDir!.delete(recursive: true);
        }
      } catch (_) {}
      tempLinkedDir = null;
    }
  });

  tearDownAll(() async {
    await cleanupFixtures();
  });

  group('Linked Source Folder Sync', () {
    Future<bool> ensureDesktop() async {
      if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
        markTestSkipped('Linked source sync is desktop-only');
        return false;
      }
      return true;
    }

    /// Creates a temp linked folder with test images copied into it.
    /// Returns the list of copied file paths.
    Future<List<String>> setUpLinkedFolder({
      int imageCount = 3,
      String? subdirectory,
    }) async {
      tempLinkedDir = await Directory.systemTemp.createTemp('linked_sync_');
      final targetDir = subdirectory != null
          ? Directory(p.join(tempLinkedDir!.path, subdirectory))
          : tempLinkedDir!;
      if (subdirectory != null) await targetDir.create(recursive: true);

      await preloadFixtures();

      final copiedPaths = <String>[];
      for (int day = 1; day <= imageCount && day <= 3; day++) {
        final fixturePath = await getSampleFacePathAsync(day);
        final destPath = p.join(targetDir.path, 'face_day$day.jpg');
        await File(fixturePath).copy(destPath);
        copiedPaths.add(destPath);
      }
      return copiedPaths;
    }

    testWidgets('imports new files from linked folder', (tester) async {
      if (!await ensureDesktop()) return;

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('SyncTest', 'face', timestamp);

      // Create raw photos directory
      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      // Set up linked folder with 3 images
      final copiedPaths = await setUpLinkedFolder(imageCount: 3);
      expect(copiedPaths.length, 3);

      // Configure linked source in DB
      await LinkedSourceUtils.persistDesktopFolderSelection(
        testProjectId!,
        tempLinkedDir!.path,
      );

      // Run sync
      final cache = buildCache(tempLinkedDir!.path);
      final result = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );

      // Verify all 3 files were imported
      expect(result.filesImported, 3,
          reason: 'Should import all 3 images from linked folder');
      expect(result.errors, isEmpty);

      // Verify photos exist in DB
      final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
      expect(photos.length, 3);

      // Verify all are marked as external_linked
      final linkedPhotos = await DB.instance.getPhotosBySourceLocationType(
        testProjectId!,
        'external_linked',
      );
      expect(linkedPhotos.length, 3);

      // Verify raw files exist on disk
      for (final photo in photos) {
        final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          photo['timestamp'] as String,
          testProjectId!,
        );
        expect(await File(rawPath).exists(), isTrue,
            reason: 'Raw photo should exist on disk');
      }

      cache.dispose();
    });

    testWidgets('re-sync skips already imported files', (tester) async {
      if (!await ensureDesktop()) return;

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('SyncSkipTest', 'face', timestamp);

      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      await setUpLinkedFolder(imageCount: 2);

      await LinkedSourceUtils.persistDesktopFolderSelection(
        testProjectId!,
        tempLinkedDir!.path,
      );

      // First sync — should import 2
      final cache = buildCache(tempLinkedDir!.path);
      final result1 = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );
      expect(result1.filesImported, 2);

      // Stop watching before second sync
      await ProjectFolderSyncService.instance.stopWatching();

      // Second sync — should import 0
      final result2 = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );
      expect(result2.filesImported, 0,
          reason: 'Re-sync should skip already imported files');
      expect(result2.filesSkipped, 2);

      // DB should still have exactly 2 photos
      final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
      expect(photos.length, 2);

      cache.dispose();
    });

    testWidgets('tombstoned files are not re-imported', (tester) async {
      if (!await ensureDesktop()) return;

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId =
          await DB.instance.addProject('TombstoneTest', 'face', timestamp);

      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      await setUpLinkedFolder(imageCount: 2);

      await LinkedSourceUtils.persistDesktopFolderSelection(
        testProjectId!,
        tempLinkedDir!.path,
      );

      // First sync — import both
      final cache = buildCache(tempLinkedDir!.path);
      final result1 = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );
      expect(result1.filesImported, 2);

      await ProjectFolderSyncService.instance.stopWatching();

      // Get one of the imported photos and tombstone its relative path
      final linkedPhotos = await DB.instance.getPhotosBySourceLocationType(
        testProjectId!,
        'external_linked',
      );
      expect(linkedPhotos.length, 2);

      final photoToDelete = linkedPhotos.first;
      final relativePath = photoToDelete['sourceRelativePath'] as String;
      final photoTimestamp = photoToDelete['timestamp'] as String;

      // Delete the photo from DB and add tombstone
      await DB.instance.deletePhoto(
        int.parse(photoTimestamp),
        testProjectId!,
      );
      await DB.instance.insertDeletedLinkedSource(
        testProjectId!,
        relativePath,
      );

      // Delete the raw file too
      final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        photoTimestamp,
        testProjectId!,
        fileExtension: photoToDelete['fileExtension'] as String?,
      );
      final rawFile = File(rawPath);
      if (await rawFile.exists()) await rawFile.delete();

      // Verify tombstone exists
      final isTombstoned = await DB.instance.isLinkedSourceDeleted(
        testProjectId!,
        relativePath,
      );
      expect(isTombstoned, isTrue);

      // Re-sync — should NOT re-import the tombstoned file
      final result2 = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );
      expect(result2.filesImported, 0,
          reason: 'Tombstoned file should not be re-imported');

      // DB should have exactly 1 photo (the non-deleted one)
      final remainingPhotos =
          await DB.instance.getPhotosByProjectID(testProjectId!);
      expect(remainingPhotos.length, 1);

      cache.dispose();
    });

    testWidgets('subdirectory paths are preserved in sourceRelativePath',
        (tester) async {
      if (!await ensureDesktop()) return;

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'SubdirSyncTest',
        'face',
        timestamp,
      );

      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      await Directory(rawDir).create(recursive: true);

      // Set up linked folder with images in a subdirectory
      const subdir = 'vacation/summer';
      await setUpLinkedFolder(imageCount: 2, subdirectory: subdir);

      await LinkedSourceUtils.persistDesktopFolderSelection(
        testProjectId!,
        tempLinkedDir!.path,
      );

      final cache = buildCache(tempLinkedDir!.path);
      final result = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );

      expect(result.filesImported, 2);

      // Verify sourceRelativePath includes the subdirectory
      final linkedPhotos = await DB.instance.getPhotosBySourceLocationType(
        testProjectId!,
        'external_linked',
      );
      expect(linkedPhotos.length, 2);

      for (final photo in linkedPhotos) {
        final relPath = photo['sourceRelativePath'] as String;
        expect(relPath, startsWith('$subdir/'),
            reason:
                'sourceRelativePath should preserve subdirectory structure, '
                'got: $relPath');
      }

      // Verify re-sync matches by relative path (no duplicates)
      await ProjectFolderSyncService.instance.stopWatching();
      final result2 = await ProjectFolderSyncService.instance.runStartupSync(
        testProjectId!,
        cache,
      );
      expect(result2.filesImported, 0,
          reason: 'Re-sync with subdirectory paths should skip existing');

      cache.dispose();
    });
  });
}
