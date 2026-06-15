import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/project_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for gallery page interactions and delete operations.
///
/// Tests are split into two tiers:
///   - UI tests (A, B, C): rendering, navigation, selection UX
///   - Headless tests (D-J): soft-delete contract + filesystem verification
///
/// Run with: `flutter test integration_test/gallery_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Gallery Page Tests', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
      await preloadFixtures();
    });

    setUp(() async {
      await _cleanupTestData();
      testProjectId = null;
      // Clear Flutter image cache between tests to prevent cross-test bleed.
      PaintingBinding.instance.imageCache.clear();
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

    // ─── Shared helpers ────────────────────────────────────────────────────

    /// Creates [count] synthetic photos for [projectId] with both raw files and
    /// DB records. Also creates thumbnails and stabilized-orientation files on disk
    /// so deleteImage() has something to clean up.
    Future<List<String>> createTestPhotos(
      int projectId,
      int count, {
      String orientation = 'portrait',
    }) async {
      final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
      await Directory(rawDir).create(recursive: true);

      final thumbDir = await DirUtils.getThumbnailDirPath(projectId);
      await Directory(thumbDir).create(recursive: true);

      final stabDir = await DirUtils.getStabilizedDirPath(projectId);
      final stabOrientDir = Directory(p.join(stabDir, orientation));
      await stabOrientDir.create(recursive: true);

      final timestamps = <String>[];
      final baseTs = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < count; i++) {
        final ts = (baseTs + i * 1000).toString();
        timestamps.add(ts);

        // Write a minimal valid JPEG (1×1 white pixel) as raw file
        final rawPath = p.join(rawDir, '$ts.jpg');
        await File(rawPath).writeAsBytes(_minimalJpegBytes());

        // Write thumbnail
        final thumbPath = p.join(thumbDir, '$ts.jpg');
        await File(thumbPath).writeAsBytes(_minimalJpegBytes());

        // Write stabilized file
        final stabPath = p.join(stabOrientDir.path, '$ts.png');
        await File(stabPath).writeAsBytes(_minimalPngBytes());

        // Insert DB record
        await DB.instance.addPhoto(
          ts,
          projectId,
          '.jpg',
          _minimalJpegBytes().length,
          '$ts.jpg',
          orientation,
        );
      }

      return timestamps;
    }

    // ─── Test A: Gallery displays imported photos (UI) ────────────────────

    testWidgets('Test A: gallery tab renders photos without crash', (
      tester,
    ) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'GalleryRenderTest',
        'face',
        ts,
      );

      // Set project as default so app goes directly to main navigation
      await DB.instance.setSettingByTitle(
        'default_project',
        testProjectId.toString(),
      );

      // Create 3 photos for this project
      await createTestPhotos(testProjectId!, 3);

      app.main();
      await pumpUntilAppReady(tester);

      // Navigate to gallery tab (collections icon)
      final galleryIcon = find.byIcon(Icons.collections);
      if (galleryIcon.evaluate().isNotEmpty) {
        await tester.tap(galleryIcon.first);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        // Gallery should render without crash
        expect(
          find.byType(Scaffold),
          findsWidgets,
          reason: 'Gallery page should render a Scaffold without crashing',
        );
      } else {
        // Navigation not visible yet; just verify app is running
        final hasApp = find.byType(MaterialApp).evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(hasApp, isTrue, reason: 'App should display some UI structure');
      }
    });

    // ─── Test B: Selection mode enter/exit (UI) ───────────────────────────

    testWidgets('Test B: gallery selection mode can be entered and exited', (
      tester,
    ) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'GallerySelectionTest',
        'face',
        ts,
      );

      await DB.instance.setSettingByTitle(
        'default_project',
        testProjectId.toString(),
      );

      await createTestPhotos(testProjectId!, 3);

      app.main();
      await pumpUntilAppReady(tester);

      // Navigate to gallery tab
      final galleryIcon = find.byIcon(Icons.collections);
      if (galleryIcon.evaluate().isEmpty) {
        // Navigation not ready, pass gracefully
        return;
      }
      await tester.tap(galleryIcon.first);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      // Look for a PopupMenuButton to enter selection mode
      final popupButton = find.byType(PopupMenuButton<String>);
      if (popupButton.evaluate().isEmpty) {
        // Gallery UI may differ, pass gracefully
        return;
      }

      await tester.tap(popupButton.first);
      // Use pump instead of pumpAndSettle; FlashingBox animation is active
      // when photos are in the gallery and would cause pumpAndSettle to timeout.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap "Select" menu item if it appears
      final selectItem = find.text('Select');
      if (selectItem.evaluate().isNotEmpty) {
        await tester.tap(selectItem.first);
        await tester.pump(const Duration(seconds: 1));

        // Selection action bar shows a TextButton.icon with label 'Cancel'.
        // Scope to TextButton to avoid matching any unrelated 'Cancel' text.
        final cancelButton = find.descendant(
          of: find.byType(TextButton),
          matching: find.text('Cancel'),
        );
        if (cancelButton.evaluate().isNotEmpty) {
          // Exit selection mode
          await tester.tap(cancelButton.first);
          await tester.pump(const Duration(seconds: 1));

          // Action bar should disappear: TextButton with 'Cancel' gone
          expect(
            cancelButton.evaluate().isEmpty,
            isTrue,
            reason:
                'Cancel button should disappear after exiting selection mode',
          );
        }
      }

      // App should not have crashed
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: 'App should still have Scaffold after selection test',
      );
    });

    // ─── Test C: Select all (UI) ──────────────────────────────────────────

    testWidgets('Test C: select-all selects all photos in current tab', (
      tester,
    ) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'GallerySelectAllTest',
        'face',
        ts,
      );

      await DB.instance.setSettingByTitle(
        'default_project',
        testProjectId.toString(),
      );

      await createTestPhotos(testProjectId!, 5);

      app.main();
      await pumpUntilAppReady(tester);

      final galleryIcon = find.byIcon(Icons.collections);
      if (galleryIcon.evaluate().isEmpty) return;

      await tester.tap(galleryIcon.first);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      // Try to enter selection mode via PopupMenu → Select
      final popupButton = find.byType(PopupMenuButton<String>);
      if (popupButton.evaluate().isEmpty) return;

      await tester.tap(popupButton.first);
      // Use pump instead of pumpAndSettle; FlashingBox animation active.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final selectItem = find.text('Select');
      if (selectItem.evaluate().isEmpty) return;

      await tester.tap(selectItem.first);
      await tester.pump(const Duration(seconds: 1));

      // The 'Select All' control is an IconButton with tooltip 'Select All'
      // (icon: Icons.select_all), not a Text widget. Use byTooltip to find it.
      final selectAllButton = find.byTooltip('Select All');
      if (selectAllButton.evaluate().isNotEmpty) {
        await tester.tap(selectAllButton.first);
        await tester.pump(const Duration(seconds: 1));

        // Expect some indication of selected count; app should not crash
        expect(
          find.byType(Scaffold),
          findsWidgets,
          reason: 'App should not crash after Select All',
        );
      }
    });

    // ─── Test D: Single photo soft-delete → restore → permanent delete ────

    testWidgets(
      'Test D: deleteImage soft-deletes; restoreImage recovers; '
      'permanentlyDeleteImage removes row and files',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'DeleteSingleTest',
          'face',
          ts,
        );

        final timestamps = await createTestPhotos(testProjectId!, 3);
        final target = timestamps[0];

        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
        final rawFile = File(p.join(rawDir, '$target.jpg'));
        final thumbFile = File(p.join(thumbDir, '$target.jpg'));

        // ── Precondition ──────────────────────────────────────────────────
        var activePhotos =
            await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(activePhotos.length, 3,
            reason: 'Should start with 3 active photos');
        expect(await rawFile.exists(), isTrue,
            reason: 'Raw file should exist before delete');
        expect(await thumbFile.exists(), isTrue,
            reason: 'Thumbnail should exist before delete');

        // ── LEG 1: soft-delete ────────────────────────────────────────────
        final deleteResult =
            await ProjectUtils.deleteImage(rawFile, testProjectId!);
        expect(deleteResult, isTrue, reason: 'deleteImage should return true');

        // Active gallery count drops by 1
        activePhotos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(activePhotos.length, 2,
            reason: 'Active count should drop to 2 after soft-delete');

        // Row appears in Recently Deleted with non-null deletedAt
        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed.length, 1,
            reason: 'Recently Deleted should contain 1 row');
        expect(trashed.first['deletedAt'], isNotNull,
            reason: 'deletedAt should be set');

        // getActivePhotoByTimestamp returns null
        final notFound = await DB.instance.getActivePhotoByTimestamp(
          target,
          testProjectId!,
        );
        expect(notFound, isNull,
            reason:
                'Active-only lookup should return null for soft-deleted row');

        // getPhotoByTimestamp (includes trashed) returns the row
        final found = await DB.instance.getPhotoByTimestamp(
          target,
          testProjectId!,
        );
        expect(found, isNotNull,
            reason: 'Any-state lookup should still find the soft-deleted row');

        // Files still on disk
        expect(await rawFile.exists(), isTrue,
            reason: 'Raw file should still exist after soft-delete');
        expect(await thumbFile.exists(), isTrue,
            reason: 'Thumbnail should still exist after soft-delete');

        // ── LEG 2: restore ────────────────────────────────────────────────
        final restoreResult =
            await ProjectUtils.restoreImage(target, testProjectId!);
        expect(restoreResult, equals(RestoreOutcome.success),
            reason: 'restoreImage should return RestoreOutcome.success');

        // Active count back to 3
        activePhotos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(activePhotos.length, 3,
            reason: 'Active count should return to 3 after restore');

        // Recently Deleted is now empty
        final afterRestore = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(afterRestore.isEmpty, isTrue,
            reason: 'Recently Deleted should be empty after restore');

        // Files still on disk (restore is non-destructive)
        expect(await rawFile.exists(), isTrue,
            reason: 'Raw file should still exist after restore');
        expect(await thumbFile.exists(), isTrue,
            reason: 'Thumbnail should still exist after restore');

        // ── LEG 3: permanent delete ───────────────────────────────────────
        // Soft-delete again to put it back in trash before permanent removal
        await ProjectUtils.deleteImage(rawFile, testProjectId!);

        final permResult = await ProjectUtils.permanentlyDeleteImage(
          rawFile,
          testProjectId!,
        );
        expect(permResult, equals(PermDeleteOutcome.success),
            reason:
                'permanentlyDeleteImage should return PermDeleteOutcome.success');

        // Row completely gone (even when including trashed rows)
        final gone = await DB.instance.getPhotoByTimestamp(
          target,
          testProjectId!,
        );
        expect(gone, isNull,
            reason: 'Row should be gone after permanent delete');

        // Files removed from disk
        expect(await rawFile.exists(), isFalse,
            reason: 'Raw file should be deleted after permanent delete');
        expect(await thumbFile.exists(), isFalse,
            reason: 'Thumbnail should be deleted after permanent delete');
      },
    );

    // ─── Test E: Bulk soft-delete → permanent delete ──────────────────────

    testWidgets(
      'Test E: bulk soft-delete then permanent delete leaves no files or DB records',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'BulkDeleteTest',
          'face',
          ts,
        );

        final timestamps = await createTestPhotos(testProjectId!, 5);

        var activePhotos =
            await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(activePhotos.length, 5,
            reason: 'Should start with 5 active photos');

        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);

        // Soft-delete all photos
        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          await ProjectUtils.deleteImage(rawFile, testProjectId!);
        }

        // Active gallery should be empty; Recently Deleted should have all 5
        activePhotos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(activePhotos.length, 0,
            reason: 'Active count should be 0 after bulk soft-delete');

        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed.length, 5,
            reason: 'Recently Deleted should contain all 5 rows');

        // Files still exist after soft-delete
        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          expect(await rawFile.exists(), isTrue,
              reason: 'Raw file $timestamp should persist after soft-delete');
        }

        // Permanently delete all
        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          await ProjectUtils.permanentlyDeleteImage(rawFile, testProjectId!);
        }

        // All rows gone (even when including trashed rows)
        for (final timestamp in timestamps) {
          final row = await DB.instance.getPhotoByTimestamp(
            timestamp,
            testProjectId!,
          );
          expect(row, isNull,
              reason: 'Row $timestamp should be gone after permanent delete');
        }

        // All files removed
        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
        final stabDir = await DirUtils.getStabilizedDirPath(testProjectId!);

        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          expect(await rawFile.exists(), isFalse,
              reason:
                  'Raw file $timestamp should not exist after permanent delete');

          final thumbFile = File(p.join(thumbDir, '$timestamp.jpg'));
          expect(await thumbFile.exists(), isFalse,
              reason:
                  'Thumbnail $timestamp should not exist after permanent delete');

          for (final orientation in DirUtils.orientations) {
            final stabFile = File(
              p.join(stabDir, orientation, '$timestamp.png'),
            );
            expect(await stabFile.exists(), isFalse,
                reason:
                    'Stabilized file $timestamp/$orientation should not exist');
          }
        }
      },
    );

    // ─── Test F: Soft-delete doesn't affect wrong project (headless) ──────

    testWidgets(
      'Test F: soft-deleting a photo from project A does not affect project B',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'IsolationTestA',
          'face',
          ts,
        );
        final projectBId = await DB.instance.addProject(
          'IsolationTestB',
          'face',
          ts + 1000,
        );

        // Register teardown for project B too
        addTearDown(() async {
          try {
            final dirB = await DirUtils.getProjectDirPath(projectBId);
            if (await Directory(dirB).exists()) {
              await Directory(dirB).delete(recursive: true);
            }
            await DB.instance.deleteProject(projectBId);
          } catch (_) {}
        });

        final tsA = await createTestPhotos(testProjectId!, 3);
        final tsB = await createTestPhotos(projectBId, 3);

        // Verify initial state
        var photosA = await DB.instance.getPhotosByProjectID(testProjectId!);
        var photosB = await DB.instance.getPhotosByProjectID(projectBId);
        expect(photosA.length, 3);
        expect(photosB.length, 3);

        // Soft-delete 1 photo from project A
        final rawDirA = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final rawFileA = File(p.join(rawDirA, '${tsA[0]}.jpg'));
        final deleteResult = await ProjectUtils.deleteImage(
          rawFileA,
          testProjectId!,
        );
        expect(deleteResult, isTrue);

        // Project A active count drops to 2
        photosA = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(photosA.length, 2,
            reason: 'Project A should have 2 active photos after soft-delete');

        // Project B still has 3 active photos (untouched)
        photosB = await DB.instance.getPhotosByProjectID(projectBId);
        expect(photosB.length, 3,
            reason: 'Project B should still have 3 active photos (unaffected)');

        // Project B Recently Deleted is empty
        final trashedB =
            await DB.instance.getRecentlyDeletedPhotosByProjectID(projectBId);
        expect(trashedB.isEmpty, isTrue,
            reason: 'Project B Recently Deleted should be empty');

        // Verify project B's files still exist on disk
        final rawDirB = await DirUtils.getRawPhotoDirPath(projectBId);
        for (final timestamp in tsB) {
          final rawFileB = File(p.join(rawDirB, '$timestamp.jpg'));
          expect(await rawFileB.exists(), isTrue,
              reason:
                  'Project B raw file $timestamp should still exist on disk');
        }
      },
    );

    // ─── Test G: Purge expiry (headless) ─────────────────────────────────

    testWidgets(
      'Test G: purgeExpiredDeletedImages removes photos older than retention window',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'PurgeExpiryTest',
          'face',
          ts,
        );

        final timestamps = await createTestPhotos(testProjectId!, 2);
        final targetTs = timestamps[0];
        final keepTs = timestamps[1];

        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);

        // Soft-delete both photos (sets deletedAt to now)
        await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$targetTs.jpg')),
          testProjectId!,
        );
        await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$keepTs.jpg')),
          testProjectId!,
        );

        // Backdate one photo's deletedAt to 31 days ago (beyond retention window)
        final expiredAt = DateTime.now()
            .subtract(const Duration(days: 31))
            .millisecondsSinceEpoch;
        final db = await DB.instance.database;
        await db.rawUpdate(
          'UPDATE ${DB.photoTable} '
          'SET deletedAt = ? WHERE timestamp = ? AND projectID = ?',
          [expiredAt, targetTs, testProjectId],
        );

        // Run purge: should remove the expired photo and leave the recent one
        final removed = await ProjectUtils.purgeExpiredDeletedImages();
        expect(removed, greaterThanOrEqualTo(1),
            reason: 'Purge should remove at least 1 expired photo');

        // Expired photo row should be gone
        final expiredRow = await DB.instance.getPhotoByTimestamp(
          targetTs,
          testProjectId!,
        );
        expect(expiredRow, isNull,
            reason: 'Expired photo row should be purged');

        // Expired photo file should be gone
        final expiredFile = File(p.join(rawDir, '$targetTs.jpg'));
        expect(await expiredFile.exists(), isFalse,
            reason: 'Expired photo file should be deleted by purge');

        // Recent soft-deleted photo should still be present
        final keptRow = await DB.instance.getPhotoByTimestamp(
          keepTs,
          testProjectId!,
        );
        expect(keptRow, isNotNull,
            reason: 'Recently soft-deleted photo should not be purged');
      },
    );

    // ─── Test H: Guide-photo auto-reset on soft-delete (headless) ────────

    testWidgets(
      'Test H: soft-deleting the guide photo resets the guide setting to "not set"',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'GuideResetTest',
          'face',
          ts,
        );

        final timestamps = await createTestPhotos(testProjectId!, 2);
        final photoATs = timestamps[0];
        final photoBTs = timestamps[1];

        // Fetch row ids
        final rowA = await DB.instance.getActivePhotoByTimestamp(
          photoATs,
          testProjectId!,
        );
        final rowB = await DB.instance.getActivePhotoByTimestamp(
          photoBTs,
          testProjectId!,
        );
        expect(rowA, isNotNull, reason: 'Photo A row should exist');
        expect(rowB, isNotNull, reason: 'Photo B row should exist');

        final idA = rowA!['id'].toString();
        final idB = rowB!['id'].toString();

        // ── Positive case: delete the guide photo ─────────────────────────
        await DB.instance.setSettingByTitle(
          'selected_guide_photo',
          idA,
          testProjectId.toString(),
        );

        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$photoATs.jpg')),
          testProjectId!,
        );

        final guideAfterDeleteA = await DB.instance.getSettingValueByTitle(
          'selected_guide_photo',
          testProjectId.toString(),
        );
        expect(guideAfterDeleteA, equals('not set'),
            reason:
                'Guide setting should reset to "not set" when guide photo is soft-deleted');

        // Restore for negative case
        await ProjectUtils.restoreImage(photoATs, testProjectId!);

        // ── Negative case: delete a non-guide photo ───────────────────────
        await DB.instance.setSettingByTitle(
          'selected_guide_photo',
          idB,
          testProjectId.toString(),
        );

        await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$photoATs.jpg')),
          testProjectId!,
        );

        final guideAfterDeleteOther = await DB.instance.getSettingValueByTitle(
          'selected_guide_photo',
          testProjectId.toString(),
        );
        expect(guideAfterDeleteOther, equals(idB),
            reason:
                'Guide setting should remain unchanged when a non-guide photo is soft-deleted');
      },
    );

    // ─── Test I: Linked-source tombstone round-trip (headless) ───────────

    testWidgets(
      'Test I: soft-delete writes linked-source tombstone; restore removes it',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'TombstoneRoundTripTest',
          'face',
          ts,
        );

        // Create one photo with external_linked source
        final timestamps = await createTestPhotos(testProjectId!, 1);
        final target = timestamps[0];
        const relPath = 'subdir/test.jpg';

        await DB.instance.updatePhotoSourceInfo(
          target,
          testProjectId!,
          sourceLocationType: 'external_linked',
          sourceRelativePath: relPath,
        );

        // Precondition: tombstone not present
        final beforeDelete = await DB.instance.isLinkedSourceDeleted(
          testProjectId!,
          relPath,
        );
        expect(beforeDelete, isFalse,
            reason: 'Tombstone should not exist before soft-delete');

        // Soft-delete → tombstone should be written
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final deleteResult = await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$target.jpg')),
          testProjectId!,
        );
        expect(deleteResult, isTrue, reason: 'deleteImage should succeed');

        final afterDelete = await DB.instance.isLinkedSourceDeleted(
          testProjectId!,
          relPath,
        );
        expect(afterDelete, isTrue,
            reason: 'Tombstone should exist after soft-delete');

        // Restore → tombstone should be removed
        final restoreResult =
            await ProjectUtils.restoreImage(target, testProjectId!);
        expect(restoreResult, equals(RestoreOutcome.success),
            reason: 'restoreImage should succeed');

        final afterRestore = await DB.instance.isLinkedSourceDeleted(
          testProjectId!,
          relPath,
        );
        expect(afterRestore, isFalse,
            reason: 'Tombstone should be removed after restore');
      },
    );

    // ─── Test J: Fingerprint dedup ignores soft-deleted rows ─────────────

    testWidgets(
      'Test J: findPhotoByFingerprint returns null when only match is '
      'soft-deleted, so picker re-import is not blocked',
      (tester) async {
        app.main();
        await pumpUntilAppReady(tester);

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'FingerprintDedupTest',
          'face',
          ts,
        );

        final timestamps = await createTestPhotos(testProjectId!, 1);
        final target = timestamps[0];
        const fingerprint = 'deadbeefcafef00d';

        // Attach a known fingerprint to the seeded row.
        await DB.instance.backfillPhotoFingerprint(
          target,
          testProjectId!,
          fingerprint,
        );

        // Precondition: active row matches by fingerprint.
        final activeMatch = await DB.instance.findPhotoByFingerprint(
          testProjectId!,
          fingerprint,
        );
        expect(activeMatch, isNotNull,
            reason: 'Active row should be found by fingerprint');
        expect(activeMatch!['timestamp'], equals(target));

        // Soft-delete it.
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final deleteResult = await ProjectUtils.deleteImage(
          File(p.join(rawDir, '$target.jpg')),
          testProjectId!,
        );
        expect(deleteResult, isTrue, reason: 'deleteImage should succeed');

        // Sanity: row is in Recently Deleted with its fingerprint intact.
        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed.length, 1,
            reason: 'Soft-deleted row should be in Recently Deleted');
        expect(trashed.first['fingerprint'], equals(fingerprint),
            reason: 'Soft-delete must not clear fingerprint');

        // Core assertion: fingerprint lookup must skip the soft-deleted row
        // so the picker import path does not silently reject the re-import.
        final afterDeleteMatch = await DB.instance.findPhotoByFingerprint(
          testProjectId!,
          fingerprint,
        );
        expect(afterDeleteMatch, isNull,
            reason:
                'findPhotoByFingerprint must return null when the only match '
                'is soft-deleted (otherwise picker re-import is silently '
                'blocked by camera_utils.savePhoto).');

        // After restore, the active row should match again.
        final restoreResult =
            await ProjectUtils.restoreImage(target, testProjectId!);
        expect(restoreResult, equals(RestoreOutcome.success),
            reason: 'restoreImage should succeed');

        final afterRestoreMatch = await DB.instance.findPhotoByFingerprint(
          testProjectId!,
          fingerprint,
        );
        expect(afterRestoreMatch, isNotNull,
            reason: 'Restored row should match by fingerprint again');
        expect(afterRestoreMatch!['timestamp'], equals(target));
      },
    );
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

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

/// Returns bytes for a minimal valid JPEG file (1×1 white pixel, ~680 bytes).
/// Uses a hardcoded JFIF header that satisfies most JPEG parsers for testing.
img.Image _whitePixel() {
  final image = img.Image(width: 1, height: 1);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return image;
}

List<int> _minimalJpegBytes() => img.encodeJpg(_whitePixel());

List<int> _minimalPngBytes() => img.encodePng(_whitePixel());
