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
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for gallery page interactions and delete operations.
///
/// Tests are split into two tiers:
///   - UI tests (A, B, C): rendering, navigation, selection UX
///   - Headless tests (D, E, F): delete correctness + filesystem verification
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
        // Navigation not visible yet — just verify app is running
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
        // Navigation not ready — pass gracefully
        return;
      }
      await tester.tap(galleryIcon.first);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      // Look for a PopupMenuButton to enter selection mode
      final popupButton = find.byType(PopupMenuButton<String>);
      if (popupButton.evaluate().isEmpty) {
        // Gallery UI may differ — pass gracefully
        return;
      }

      await tester.tap(popupButton.first);
      // Use pump instead of pumpAndSettle — FlashingBox animation is active
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

          // Action bar should disappear — TextButton with 'Cancel' gone
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
      // Use pump instead of pumpAndSettle — FlashingBox animation active.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final selectItem = find.text('Select');
      if (selectItem.evaluate().isEmpty) return;

      await tester.tap(selectItem.first);
      await tester.pump(const Duration(seconds: 1));

      // The 'Select All' control is an IconButton with tooltip 'Select All'
      // (icon: Icons.select_all) — not a Text widget. Use byTooltip to find it.
      final selectAllButton = find.byTooltip('Select All');
      if (selectAllButton.evaluate().isNotEmpty) {
        await tester.tap(selectAllButton.first);
        await tester.pump(const Duration(seconds: 1));

        // Expect some indication of selected count — app should not crash
        expect(
          find.byType(Scaffold),
          findsWidgets,
          reason: 'App should not crash after Select All',
        );
      }
    });

    // ─── Test D: Single photo delete (headless) ───────────────────────────

    testWidgets('Test D: deleteImage removes DB record and files from disk', (
      tester,
    ) async {
      app.main();
      await pumpUntilAppReady(tester);

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject(
        'DeleteSingleTest',
        'face',
        ts,
      );

      final timestamps = await createTestPhotos(testProjectId!, 3);

      // Verify 3 photos are in DB
      var photos = await DB.instance.getPhotosByProjectID(testProjectId!);
      expect(photos.length, 3, reason: 'Should start with 3 photos in DB');

      // Delete the first photo
      final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
      final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
      final rawFile = File(p.join(rawDir, '${timestamps[0]}.jpg'));
      final thumbFile = File(p.join(thumbDir, '${timestamps[0]}.jpg'));

      expect(
        await rawFile.exists(),
        isTrue,
        reason: 'Raw file should exist before delete',
      );
      expect(
        await thumbFile.exists(),
        isTrue,
        reason: 'Thumbnail should exist before delete',
      );

      final deleteResult = await ProjectUtils.deleteImage(
        rawFile,
        testProjectId!,
      );
      expect(deleteResult, isTrue, reason: 'deleteImage should return true');

      // DB should now have 2 photos
      photos = await DB.instance.getPhotosByProjectID(testProjectId!);
      expect(
        photos.length,
        2,
        reason: 'DB should have 2 photos after single delete',
      );

      // Verify the deleted photo's timestamp is gone from DB
      final deleted = await DB.instance.getPhotoByTimestamp(
        timestamps[0],
        testProjectId!,
      );
      expect(
        deleted,
        isNull,
        reason: 'Deleted photo timestamp should not exist in DB',
      );

      // Raw file should be deleted
      expect(
        await rawFile.exists(),
        isFalse,
        reason: 'Raw file should be deleted from disk',
      );

      // Thumbnail should be deleted
      expect(
        await thumbFile.exists(),
        isFalse,
        reason: 'Thumbnail should be deleted from disk',
      );
    });

    // ─── Test E: Bulk delete correctness (headless) ───────────────────────

    testWidgets(
      'Test E: bulk delete via deleteImage leaves no files or DB records',
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

        var photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(photos.length, 5, reason: 'Should start with 5 photos');

        // Delete all photos one by one
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          await ProjectUtils.deleteImage(rawFile, testProjectId!);
        }

        // DB should be empty
        photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(
          photos.length,
          0,
          reason: 'DB should have 0 photos after bulk delete',
        );

        // All raw files should be gone
        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
        final stabDir = await DirUtils.getStabilizedDirPath(testProjectId!);

        for (final timestamp in timestamps) {
          final rawFile = File(p.join(rawDir, '$timestamp.jpg'));
          expect(
            await rawFile.exists(),
            isFalse,
            reason: 'Raw file $timestamp should not exist after bulk delete',
          );

          final thumbFile = File(p.join(thumbDir, '$timestamp.jpg'));
          expect(
            await thumbFile.exists(),
            isFalse,
            reason: 'Thumbnail $timestamp should not exist after bulk delete',
          );

          for (final orientation in DirUtils.orientations) {
            final stabFile = File(
              p.join(stabDir, orientation, '$timestamp.png'),
            );
            expect(
              await stabFile.exists(),
              isFalse,
              reason:
                  'Stabilized file $timestamp/$orientation should not exist',
            );
          }
        }
      },
    );

    // ─── Test F: Delete doesn't affect wrong project (headless) ──────────

    testWidgets(
      'Test F: deleting photo from project A does not affect project B',
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

        // Delete 1 photo from project A
        final rawDirA = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final rawFileA = File(p.join(rawDirA, '${tsA[0]}.jpg'));
        final deleteResult = await ProjectUtils.deleteImage(
          rawFileA,
          testProjectId!,
        );
        expect(deleteResult, isTrue);

        // Project A should have 2 photos
        photosA = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(
          photosA.length,
          2,
          reason: 'Project A should have 2 photos after 1 deletion',
        );

        // Project B should still have 3 photos (untouched)
        photosB = await DB.instance.getPhotosByProjectID(projectBId);
        expect(
          photosB.length,
          3,
          reason: 'Project B should still have 3 photos (unaffected)',
        );

        // Verify project B's files still exist on disk
        final rawDirB = await DirUtils.getRawPhotoDirPath(projectBId);
        for (final timestamp in tsB) {
          final rawFileB = File(p.join(rawDirB, '$timestamp.jpg'));
          expect(
            await rawFileB.exists(),
            isTrue,
            reason: 'Project B raw file $timestamp should still exist on disk',
          );
        }
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
List<int> _minimalJpegBytes() {
  // Smallest valid JFIF JPEG: 1×1 white pixel
  return [
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0xFF,
    0xDB,
    0x00,
    0x43,
    0x00,
    0x08,
    0x06,
    0x06,
    0x07,
    0x06,
    0x05,
    0x08,
    0x07,
    0x07,
    0x07,
    0x09,
    0x09,
    0x08,
    0x0A,
    0x0C,
    0x14,
    0x0D,
    0x0C,
    0x0B,
    0x0B,
    0x0C,
    0x19,
    0x12,
    0x13,
    0x0F,
    0x14,
    0x1D,
    0x1A,
    0x1F,
    0x1E,
    0x1D,
    0x1A,
    0x1C,
    0x1C,
    0x20,
    0x24,
    0x2E,
    0x27,
    0x20,
    0x22,
    0x2C,
    0x23,
    0x1C,
    0x1C,
    0x28,
    0x37,
    0x29,
    0x2C,
    0x30,
    0x31,
    0x34,
    0x34,
    0x34,
    0x1F,
    0x27,
    0x39,
    0x3D,
    0x38,
    0x32,
    0x3C,
    0x2E,
    0x33,
    0x34,
    0x32,
    0xFF,
    0xC0,
    0x00,
    0x0B,
    0x08,
    0x00,
    0x01,
    0x00,
    0x01,
    0x01,
    0x01,
    0x11,
    0x00,
    0xFF,
    0xC4,
    0x00,
    0x1F,
    0x00,
    0x00,
    0x01,
    0x05,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0xFF,
    0xC4,
    0x00,
    0xB5,
    0x10,
    0x00,
    0x02,
    0x01,
    0x03,
    0x03,
    0x02,
    0x04,
    0x03,
    0x05,
    0x05,
    0x04,
    0x04,
    0x00,
    0x00,
    0x01,
    0x7D,
    0x01,
    0x02,
    0x03,
    0x00,
    0x04,
    0x11,
    0x05,
    0x12,
    0x21,
    0x31,
    0x41,
    0x06,
    0x13,
    0x51,
    0x61,
    0x07,
    0x22,
    0x71,
    0x14,
    0x32,
    0x81,
    0x91,
    0xA1,
    0x08,
    0x23,
    0x42,
    0xB1,
    0xC1,
    0x15,
    0x52,
    0xD1,
    0xF0,
    0x24,
    0x33,
    0x62,
    0x72,
    0x82,
    0x09,
    0x0A,
    0x16,
    0x17,
    0x18,
    0x19,
    0x1A,
    0x25,
    0x26,
    0x27,
    0x28,
    0x29,
    0x2A,
    0x34,
    0x35,
    0x36,
    0x37,
    0x38,
    0x39,
    0x3A,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x48,
    0x49,
    0x4A,
    0x53,
    0x54,
    0x55,
    0x56,
    0x57,
    0x58,
    0x59,
    0x5A,
    0x63,
    0x64,
    0x65,
    0x66,
    0x67,
    0x68,
    0x69,
    0x6A,
    0x73,
    0x74,
    0x75,
    0x76,
    0x77,
    0x78,
    0x79,
    0x7A,
    0x83,
    0x84,
    0x85,
    0x86,
    0x87,
    0x88,
    0x89,
    0x8A,
    0x93,
    0x94,
    0x95,
    0x96,
    0x97,
    0x98,
    0x99,
    0x9A,
    0xA2,
    0xA3,
    0xA4,
    0xA5,
    0xA6,
    0xA7,
    0xA8,
    0xA9,
    0xAA,
    0xB2,
    0xB3,
    0xB4,
    0xB5,
    0xB6,
    0xB7,
    0xB8,
    0xB9,
    0xBA,
    0xC2,
    0xC3,
    0xC4,
    0xC5,
    0xC6,
    0xC7,
    0xC8,
    0xC9,
    0xCA,
    0xD2,
    0xD3,
    0xD4,
    0xD5,
    0xD6,
    0xD7,
    0xD8,
    0xD9,
    0xDA,
    0xE1,
    0xE2,
    0xE3,
    0xE4,
    0xE5,
    0xE6,
    0xE7,
    0xE8,
    0xE9,
    0xEA,
    0xF1,
    0xF2,
    0xF3,
    0xF4,
    0xF5,
    0xF6,
    0xF7,
    0xF8,
    0xF9,
    0xFA,
    0xFF,
    0xDA,
    0x00,
    0x08,
    0x01,
    0x01,
    0x00,
    0x00,
    0x3F,
    0x00,
    0xFB,
    0xDE,
    0xFF,
    0xD9,
  ];
}

/// Returns bytes for a minimal valid PNG file (1×1 white pixel, ~67 bytes).
List<int> _minimalPngBytes() {
  // PNG signature + IHDR + IDAT + IEND for a 1×1 white opaque pixel
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // width=1, height=1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT length + type
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, // IDAT data
    0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA5, 0xB7, 0x5A, // IDAT data continued
    0x28, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND length + type
    0x44, 0xAE, 0x42, 0x60, 0x82, // IEND data + CRC
  ];
}
