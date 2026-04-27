import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agelapse/screens/recently_deleted_page.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/project_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Widget-level tests for [RecentlyDeletedPage].
///
/// Companion to the headless tests in `gallery_test.dart` (Tests D-J).
/// Those exercise the storage layer; these drive the actual page UI:
/// opens the page, taps tiles, dismisses dialogs, asserts SnackBars and
/// callback firing semantics.
///
/// Run with: `flutter test integration_test/recently_deleted_page_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('RecentlyDeletedPage widget', () {
    int? testProjectId;

    setUpAll(() async {
      initDatabase();
      await DB.instance.createTablesIfNotExist();
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
            await Directory(projectDir).delete(recursive: true);
          }
          await DB.instance.deleteProject(testProjectId!);
        } catch (_) {}
        testProjectId = null;
      }
    });

    Future<void> seedTrashed(int projectId, int count) async {
      final rawDir = await DirUtils.getRawPhotoDirPath(projectId);
      final thumbDir = await DirUtils.getThumbnailDirPath(projectId);
      await Directory(rawDir).create(recursive: true);
      await Directory(thumbDir).create(recursive: true);

      final base = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < count; i++) {
        final ts = (base + i * 1000).toString();
        final rawPath = p.join(rawDir, '$ts.jpg');
        final thumbPath = p.join(thumbDir, '$ts.jpg');
        await File(rawPath).writeAsBytes(_minimalJpegBytes());
        await File(thumbPath).writeAsBytes(_minimalJpegBytes());
        await DB.instance.addPhoto(
          ts,
          projectId,
          '.jpg',
          _minimalJpegBytes().length,
          '$ts.jpg',
          'portrait',
        );
        await ProjectUtils.deleteImage(File(rawPath), projectId);
      }
    }

    Future<void> pumpPage(
      WidgetTester tester, {
      required int projectId,
      Future<void> Function()? onRestored,
      Future<void> Function()? onPurged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecentlyDeletedPage(
            projectId: projectId,
            projectName: 'TestProject',
            onRestored: onRestored,
            onPurged: onPurged,
          ),
        ),
      );
      // Initial load + thumbnail FutureBuilders.
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // ─── empty state ─────────────────────────────────────────────────────

    testWidgets(
      'shows empty-state copy when there are no trashed photos',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'EmptyTrashTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await pumpPage(tester, projectId: testProjectId!);

        expect(find.text('No recently deleted photos'), findsOneWidget);
        // The header overflow menu should be hidden when the trash is empty.
        expect(find.byTooltip('More actions'), findsNothing);
        expect(find.byTooltip('Select'), findsNothing);
      },
    );

    // ─── grid renders + days label ───────────────────────────────────────

    testWidgets(
      'renders one tile per trashed photo with a days-remaining label',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'GridRenderTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 3);
        await pumpPage(tester, projectId: testProjectId!);

        // Days-remaining label for fresh deletes ceilings to "30d".
        expect(find.text('30d'), findsNWidgets(3));
        expect(find.byTooltip('Select'), findsOneWidget);
        expect(find.byTooltip('More actions'), findsOneWidget);
      },
    );

    // ─── single-tap → bottom sheet → restore ─────────────────────────────

    testWidgets(
      'tapping a tile opens the actions sheet; Restore fires onRestored '
      'and removes the row from trash',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'SingleRestoreTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 1);

        int restoredCallbacks = 0;
        int purgedCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onRestored: () async => restoredCallbacks++,
          onPurged: () async => purgedCallbacks++,
        );

        // Tap the only tile (the GestureDetector inside the grid).
        await tester.tap(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();

        expect(find.text('Restore'), findsOneWidget);
        expect(find.text('Delete Forever'), findsOneWidget);

        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Row no longer in trash.
        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed, isEmpty,
            reason: 'restored row should leave Recently Deleted');

        // The right callback fired (restore changes active set, purge does
        // not).
        expect(restoredCallbacks, equals(1),
            reason: 'onRestored should be invoked exactly once');
        expect(purgedCallbacks, equals(0),
            reason: 'onPurged must NOT fire on a successful restore');

        // SnackBar surfaces success.
        expect(find.text('Restored 1 photo'), findsOneWidget);
      },
    );

    // ─── Delete Forever → confirm → permanent delete fires onPurged only ─

    testWidgets(
      'Delete Forever requires confirmation and fires onPurged (not '
      'onRestored)',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'SinglePermDeleteTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 1);

        int restoredCallbacks = 0;
        int purgedCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onRestored: () async => restoredCallbacks++,
          onPurged: () async => purgedCallbacks++,
        );

        await tester.tap(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Delete Forever'));
        await tester.pumpAndSettle();

        // Confirm dialog must appear before any destructive action.
        expect(find.text('Delete Photo Forever?'), findsOneWidget);

        // Confirm.
        await tester.tap(find.widgetWithText(TextButton, 'Delete Forever'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed, isEmpty,
            reason: 'permanent-delete should remove the row');

        expect(purgedCallbacks, equals(1),
            reason: 'onPurged must fire after permanent delete');
        expect(restoredCallbacks, equals(0),
            reason:
                'onRestored must NOT fire on permanent delete (no recompile '
                'needed — saves a video pass)');
      },
    );

    // ─── cancel-button on confirm dialog leaves the row trashed ──────────

    testWidgets(
      'cancelling the Delete Forever confirm dialog leaves the row in '
      'Recently Deleted and fires no callbacks',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'CancelConfirmTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 1);

        int purgedCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onPurged: () async => purgedCallbacks++,
        );

        await tester.tap(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Forever'));
        await tester.pumpAndSettle();

        // Cancel button — ConfirmActionDialog uses "Cancel".
        final cancelFinder = find.widgetWithText(TextButton, 'Cancel');
        if (cancelFinder.evaluate().isNotEmpty) {
          await tester.tap(cancelFinder.first);
          await tester.pumpAndSettle();
        } else {
          // Older dialog may use a different label — just dismiss via barrier.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }

        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed.length, 1,
            reason: 'row must remain trashed when user cancels');
        expect(purgedCallbacks, equals(0));
      },
    );

    // ─── selection mode + Select All ─────────────────────────────────────

    testWidgets(
      'long-press enters selection mode; Select All highlights every tile',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'SelectAllTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 4);
        await pumpPage(tester, projectId: testProjectId!);

        await tester.longPress(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.text('Select All'), findsOneWidget);

        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        expect(find.text('4 selected'), findsOneWidget);
      },
    );

    // ─── Empty Trash overflow action ─────────────────────────────────────

    testWidgets(
      'Empty Trash overflow action removes every trashed row after a single '
      'confirm',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'EmptyTrashActionTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 3);

        int purgedCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onPurged: () async => purgedCallbacks++,
        );

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Empty Trash'));
        await tester.pumpAndSettle();

        // Single confirm at the menu, no per-photo prompt.
        expect(find.text('Empty Recently Deleted?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Empty Trash'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed, isEmpty,
            reason: 'all rows should be permanently deleted');
        expect(purgedCallbacks, equals(1));
      },
    );

    // ─── Restore All overflow action ─────────────────────────────────────

    testWidgets(
      'Restore All overflow action restores every trashed row after a single '
      'confirm and fires onRestored',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'RestoreAllActionTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 3);

        int restoredCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onRestored: () async => restoredCallbacks++,
        );

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore All'));
        await tester.pumpAndSettle();

        expect(find.text('Restore All Photos?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Restore All'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final trashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(trashed, isEmpty);

        final active = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(active.length, equals(3),
            reason: 'all 3 rows should now be active');
        expect(restoredCallbacks, equals(1));
      },
    );

    // ─── restore of a row whose raw file has been deleted ────────────────

    testWidgets(
      'restoring a row whose raw file is missing on disk leaves the row '
      'trashed and surfaces a warning SnackBar',
      (tester) async {
        testProjectId = await DB.instance.addProject(
          'RestoreMissingFileTest',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        await seedTrashed(testProjectId!, 1);

        // Manually delete the raw file off disk to simulate sync-folder
        // cleanup or OS deletion during the retention window.
        final trashedRows = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        final ts = trashedRows.first['timestamp'] as String;
        final ext = trashedRows.first['fileExtension'] as String;
        final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          ts,
          testProjectId!,
          fileExtension: ext,
        );
        await File(rawPath).delete();

        int restoredCallbacks = 0;
        await pumpPage(
          tester,
          projectId: testProjectId!,
          onRestored: () async => restoredCallbacks++,
        );

        await tester.tap(find.byType(GestureDetector).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Row stays trashed — no broken active row was resurrected.
        final stillTrashed = await DB.instance
            .getRecentlyDeletedPhotosByProjectID(testProjectId!);
        expect(stillTrashed.length, 1,
            reason:
                'restoreImage must abort when the raw file is missing on disk');

        // No restore callback (nothing actually restored → no recompile).
        expect(restoredCallbacks, equals(0),
            reason: 'onRestored must not fire when no row was restored');

        // SnackBar mentions the missing file.
        expect(find.textContaining('missing on disk'), findsOneWidget);
      },
    );
  });
}

// ─── helpers ────────────────────────────────────────────────────────────────

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

img.Image _whitePixel() {
  final image = img.Image(width: 1, height: 1);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return image;
}

List<int> _minimalJpegBytes() => img.encodeJpg(_whitePixel());
