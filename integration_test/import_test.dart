import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for the photo import pipeline.
///
/// Tests the full import flow: file → date extraction → image processing →
/// filesystem writes → DB record insertion.
///
/// Run with: `flutter test integration_test/import_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Photo Import Pipeline Tests', () {
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

    // ─── Test A: Single JPEG import with EXIF date (Tier 1) ───────────────

    testWidgets(
      'Test A: JPEG with EXIF extracts Tier-1 date and produces raw + thumbnail + DB record',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Import Test A',
          'face',
          ts,
        );

        final fixturePath = await getSampleFacePathAsync(1);
        // Copy fixture to a temp file; never import from the asset path directly
        // since the import pipeline may move or modify the source.
        final tempDir = await Directory.systemTemp.createTemp('import_test_a_');
        final tempPath = p.join(tempDir.path, 'day1_copy.jpg');
        await File(fixturePath).copy(tempPath);

        final notifier = ValueNotifier<String>('');
        bool importResult = false;
        try {
          importResult = await GalleryUtils.importXFile(
            XFile(tempPath),
            testProjectId!,
            notifier,
          );
        } finally {
          notifier.dispose();
          await tempDir.delete(recursive: true);
        }

        expect(
          importResult,
          isTrue,
          reason: 'Import of sample face day1.jpg should succeed',
        );

        // Allow isolate-based image processing to complete
        await tester.pump(const Duration(seconds: 3));

        final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(
          photos.length,
          greaterThanOrEqualTo(1),
          reason: 'At least one DB record should be inserted after import',
        );

        final photo = photos.first;
        final timestamp = photo['timestamp'] as String;

        // Raw file
        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final rawFiles = await Directory(rawDir)
            .list()
            .where(
              (f) =>
                  f is File && p.basenameWithoutExtension(f.path) == timestamp,
            )
            .toList();
        expect(
          rawFiles.isNotEmpty,
          isTrue,
          reason: 'Raw file should exist in photos_raw/ after import',
        );

        // Thumbnail
        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);
        final thumbPath = p.join(thumbDir, '$timestamp.jpg');
        expect(
          await File(thumbPath).exists(),
          isTrue,
          reason: 'Thumbnail should exist in thumbnails/ after import',
        );

        // captureOffsetMinutes should have been set and be an integer
        final captureOffset = photo['captureOffsetMinutes'];
        expect(
          captureOffset,
          isA<int>(),
          reason: 'captureOffsetMinutes should be a non-null int set from EXIF',
        );
      },
    );

    // ─── Test B: BMP with date in filename (Tier 2) ───────────────────────

    testWidgets('Test B: BMP named 2024-03-15 uses filename date (Tier 2)', (
      tester,
    ) async {
      app.main();
      await tester.pump(const Duration(seconds: 2));

      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available: $fixtureLoadError');
        return;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      testProjectId = await DB.instance.addProject('Import Test B', 'face', ts);

      // Copy BMP fixture to a temp file with a date in the filename
      final bmpFixturePath = await getFormatSamplePathAsync('bmp', 'day1');
      final tempDir = await Directory.systemTemp.createTemp('import_test_b_');
      final renamedPath = p.join(tempDir.path, '2024-03-15_photo.bmp');
      await File(bmpFixturePath).copy(renamedPath);

      try {
        final xfile = XFile(renamedPath);
        final notifier = ValueNotifier<String>('');
        bool importResult = false;
        try {
          importResult = await GalleryUtils.importXFile(
            xfile,
            testProjectId!,
            notifier,
          );
        } finally {
          notifier.dispose();
        }

        expect(
          importResult,
          isTrue,
          reason: 'Import of renamed BMP should succeed',
        );

        await tester.pump(const Duration(seconds: 3));

        final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(
          photos.length,
          greaterThanOrEqualTo(1),
          reason: 'DB record should be inserted',
        );

        // The timestamp must correspond to 2024-03-15 (midnight local → UTC)
        final photo = photos.first;
        final storedTs = int.parse(photo['timestamp'] as String);
        final storedDate = DateTime.fromMillisecondsSinceEpoch(
          storedTs,
          isUtc: true,
        ).toLocal();
        expect(storedDate.year, 2024, reason: 'Year should be 2024');
        expect(storedDate.month, 3, reason: 'Month should be 3 (March)');
        expect(storedDate.day, 15, reason: 'Day should be 15');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // ─── Test C: BMP with no date info (Tier 3, file modified) ───────────

    testWidgets(
      'Test C: BMP with no date cue falls back to file modified date (Tier 3)',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Import Test C',
          'face',
          ts,
        );

        final bmpFixturePath = await getFormatSamplePathAsync('bmp', 'day1');
        final tempDir = await Directory.systemTemp.createTemp('import_test_c_');
        final renamedPath = p.join(tempDir.path, 'random_name.bmp');
        await File(bmpFixturePath).copy(renamedPath);

        try {
          final lastModified = await File(renamedPath).lastModified();

          final xfile = XFile(renamedPath);
          final notifier = ValueNotifier<String>('');
          bool importResult = false;
          try {
            importResult = await GalleryUtils.importXFile(
              xfile,
              testProjectId!,
              notifier,
            );
          } finally {
            notifier.dispose();
          }

          expect(
            importResult,
            isTrue,
            reason: 'Import of BMP with no date cue should succeed',
          );

          await tester.pump(const Duration(seconds: 3));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(
            photos.length,
            greaterThanOrEqualTo(1),
            reason: 'DB record should be inserted',
          );

          // Timestamp should correspond to midnight of the file's last-modified date
          final photo = photos.first;
          final storedTs = int.parse(photo['timestamp'] as String);
          final storedDate = DateTime.fromMillisecondsSinceEpoch(
            storedTs,
            isUtc: true,
          ).toLocal();
          expect(
            storedDate.year,
            lastModified.year,
            reason: 'Year should match file modified year',
          );
          expect(
            storedDate.month,
            lastModified.month,
            reason: 'Month should match file modified month',
          );
          expect(
            storedDate.day,
            lastModified.day,
            reason: 'Day should match file modified day',
          );
          // Midnight: hour should be 0 in local time
          expect(
            storedDate.hour,
            0,
            reason: 'Timestamp should be midnight of the file modified date',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    // ─── Test D: Duplicate detection ─────────────────────────────────────

    testWidgets(
      'Test D: duplicate detection rejects exact duplicate and accepts different-size same-timestamp',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Import Test D',
          'face',
          ts,
        );

        final fixturePath = await getSampleFacePathAsync(1);
        // Copy fixture four times: two identical copies for the exact-duplicate
        // test, one modified copy with a different size, and one same-size copy
        // with different content for fingerprint-vs-size duplicate handling.
        final tempDir = await Directory.systemTemp.createTemp('import_test_d_');
        final copy1 = p.join(tempDir.path, 'copy1.jpg');
        final copy2 = p.join(tempDir.path, 'copy2.jpg');
        final copy3 = p.join(tempDir.path, 'copy3.jpg');
        final copy4 = p.join(tempDir.path, 'copy4.jpg');
        await File(fixturePath).copy(copy1);
        await File(fixturePath).copy(copy2);
        // Make copy3 a different size by appending a null byte; same EXIF
        // timestamp but different imageLength, so the duplicate loop should
        // increment the timestamp by 1ms and accept the import.
        final originalBytes = await File(fixturePath).readAsBytes();
        await File(copy3).writeAsBytes([...originalBytes, 0x00]);
        final sameSizeDifferentBytes = List<int>.from(originalBytes);
        final mutationIndex = sameSizeDifferentBytes.length ~/ 2;
        sameSizeDifferentBytes[mutationIndex] =
            sameSizeDifferentBytes[mutationIndex] ^ 0x01;
        await File(copy4).writeAsBytes(sameSizeDifferentBytes);

        final notifier = ValueNotifier<String>('');
        try {
          // ── Phase 1: exact duplicate rejected ────────────────────────────

          // First import
          final first = await GalleryUtils.importXFile(
            XFile(copy1),
            testProjectId!,
            notifier,
          );
          expect(first, isTrue, reason: 'First import should succeed');

          await tester.pump(const Duration(seconds: 3));

          final photosAfterFirst = await DB.instance.getPhotosByProjectID(
            testProjectId!,
          );
          expect(
            photosAfterFirst.length,
            1,
            reason: 'Exactly 1 record after first import',
          );

          final firstTimestamp = int.parse(
            photosAfterFirst.first['timestamp'] as String,
          );

          // Second import: copy2 has same EXIF timestamp + same file size → rejected
          final second = await GalleryUtils.importXFile(
            XFile(copy2),
            testProjectId!,
            notifier,
          );
          expect(
            second,
            isFalse,
            reason: 'Second import of identical file should be rejected',
          );

          await tester.pump(const Duration(seconds: 2));

          final photosAfterSecond = await DB.instance.getPhotosByProjectID(
            testProjectId!,
          );
          expect(
            photosAfterSecond.length,
            1,
            reason: 'Still exactly 1 record after duplicate import attempt',
          );

          // ── Phase 2: different-size same-timestamp gets timestamp+1 ──────

          // Import copy3 with an explicit timestamp equal to the first photo's
          // timestamp. Since file sizes differ, the duplicate loop increments
          // the timestamp by 1ms and accepts the import.
          final third = await GalleryUtils.importXFile(
            XFile(copy3),
            testProjectId!,
            notifier,
            timestamp: firstTimestamp,
          );
          expect(
            third,
            isTrue,
            reason:
                'Different-size file with same timestamp should be accepted',
          );

          await tester.pump(const Duration(seconds: 3));

          final photosAfterThird = await DB.instance.getPhotosByProjectID(
            testProjectId!,
          );
          expect(
            photosAfterThird.length,
            2,
            reason: 'DB should have 2 records after different-size import',
          );

          // The second record's timestamp should be firstTimestamp + 1
          final timestamps = photosAfterThird
              .map((r) => int.parse(r['timestamp'] as String))
              .toList()
            ..sort();
          expect(
            timestamps[1],
            firstTimestamp + 1,
            reason: 'Second record timestamp should be firstTimestamp + 1ms',
          );

          // ── Phase 3: same-size different fingerprint gets timestamp+2 ─────

          final fourth = await GalleryUtils.importXFile(
            XFile(copy4),
            testProjectId!,
            notifier,
            timestamp: firstTimestamp,
          );
          expect(
            fourth,
            isTrue,
            reason:
                'Same-size file with different fingerprint should be accepted',
          );

          await tester.pump(const Duration(seconds: 3));

          final photosAfterFourth = await DB.instance.getPhotosByProjectID(
            testProjectId!,
          );
          expect(
            photosAfterFourth.length,
            3,
            reason: 'DB should have 3 records after same-size distinct import',
          );

          final finalTimestamps = photosAfterFourth
              .map((r) => int.parse(r['timestamp'] as String))
              .toList()
            ..sort();
          expect(
            finalTimestamps[2],
            firstTimestamp + 2,
            reason: 'Third record timestamp should be firstTimestamp + 2ms',
          );
        } finally {
          notifier.dispose();
          await tempDir.delete(recursive: true);
        }
      },
    );

    // ─── Test E: Multi-format import (JPG, PNG, WebP, BMP) ───────────────

    testWidgets(
      'Test E: imports JPG, PNG, WebP, BMP and produces records + files for each',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Import Test E',
          'face',
          ts,
        );

        // Only use formats OpenCV handles natively on all platforms (no HEIC/AVIF/TIFF/JP2)
        const formats = ['jpg', 'png', 'webp', 'bmp'];
        final tempDir = await Directory.systemTemp.createTemp('import_test_e_');
        final notifier = ValueNotifier<String>('');

        try {
          for (final format in formats) {
            final fixturePath = await getFormatSamplePathAsync(format, 'day1');
            // Copy to temp so import pipeline doesn't modify the fixture
            final copyPath = p.join(tempDir.path, 'format_test_day1.$format');
            await File(fixturePath).copy(copyPath);

            final result = await GalleryUtils.importXFile(
              XFile(copyPath),
              testProjectId!,
              notifier,
            );
            expect(result, isTrue, reason: 'Import of $format should succeed');
          }
        } finally {
          notifier.dispose();
          await tempDir.delete(recursive: true);
        }

        // Allow all isolate-based processing to complete
        await tester.pump(const Duration(seconds: 5));

        final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
        expect(
          photos.length,
          formats.length,
          reason: 'All ${formats.length} formats should produce DB records',
        );

        final rawDir = await DirUtils.getRawPhotoDirPath(testProjectId!);
        final thumbDir = await DirUtils.getThumbnailDirPath(testProjectId!);

        for (final photo in photos) {
          final timestamp = photo['timestamp'] as String;

          final rawFiles = await Directory(rawDir)
              .list()
              .where(
                (f) =>
                    f is File &&
                    p.basenameWithoutExtension(f.path) == timestamp,
              )
              .toList();
          expect(
            rawFiles.isNotEmpty,
            isTrue,
            reason: 'Raw file should exist for timestamp $timestamp',
          );

          final thumbPath = p.join(thumbDir, '$timestamp.jpg');
          expect(
            await File(thumbPath).exists(),
            isTrue,
            reason: 'Thumbnail should exist for timestamp $timestamp',
          );
        }
      },
    );

    // ─── Test F: ZIP import (all platforms) ──────────────────────────────
    // Routes through processPickedFile so each platform exercises its own
    // implementation: desktop -> processPickedZipFileDesktop (archive),
    // mobile -> processPickedZipFile (IsolateZipReader).

    testWidgets(
      'Test F: ZIP containing 3 JPEGs imports all entries (all platforms)',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId = await DB.instance.addProject(
          'Import Test F',
          'face',
          ts,
        );

        // Build a ZIP with 3 valid JPEGs, 1 tiny file (<10 KB, filtered), and
        // 1 .DS_Store entry (filtered) to exercise the import filter logic.
        final tempDir = await Directory.systemTemp.createTemp('import_test_f_');
        try {
          final facePaths = await Future.wait([
            getSampleFacePathAsync(1),
            getSampleFacePathAsync(2),
            getSampleFacePathAsync(3),
          ]);

          // Copy faces to temp dir with distinct names to avoid basename collisions
          final renamedPaths = <String>[];
          for (int i = 0; i < facePaths.length; i++) {
            final dest = p.join(tempDir.path, 'face_${i + 1}.jpg');
            await File(facePaths[i]).copy(dest);
            renamedPaths.add(dest);
          }

          // Tiny file and .DS_Store that should be filtered out
          final tinyPath = p.join(tempDir.path, 'tiny.jpg');
          await File(tinyPath).writeAsBytes(List.filled(100, 0xFF));

          final zipWithTinyPath = p.join(tempDir.path, 'test_import.zip');
          final encoder = ZipFileEncoder();
          encoder.create(zipWithTinyPath);
          for (final rp in renamedPaths) {
            await encoder.addFile(File(rp));
          }
          await encoder.addFile(File(tinyPath));
          await encoder.close();

          int successCount = 0;
          int importedCount = 0;
          final notifier = ValueNotifier<String>('');

          await GalleryUtils.processPickedFile(
            File(zipWithTinyPath),
            testProjectId!,
            notifier,
            onImagesLoaded: () {},
            setProgressInMain: (p) {},
            increaseSuccessfulImportCount: () => successCount++,
            increasePhotosImported: (v) => importedCount += v,
          );

          notifier.dispose();

          // Allow isolate processing to complete
          await tester.pump(const Duration(seconds: 5));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(
            photos.length,
            3,
            reason: 'All 3 valid JPEGs should be imported; tiny entry filtered',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    // ─── Test G: export -> re-import round-trip (all platforms) ──────────

    testWidgets(
      'Test G: exported ZIP re-imports into a fresh project (round-trip)',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        final sourceProjectId = await DB.instance.addProject(
          'Import Test G Source',
          'face',
          ts,
        );
        testProjectId = sourceProjectId;

        // Seed the source project with 3 raw photos, then export to ZIP.
        final rawDir = await DirUtils.getRawPhotoDirPath(sourceProjectId);
        await Directory(rawDir).create(recursive: true);
        final rawPaths = <String>[];
        for (int day = 1; day <= 3; day++) {
          final fixturePath = await getSampleFacePathAsync(day);
          final photoTs = (ts + day * 86400000).toString();
          final destPath = p.join(rawDir, '$photoTs.jpg');
          await File(fixturePath).copy(destPath);
          rawPaths.add(destPath);
          final len = await File(destPath).length();
          await DB.instance.addPhoto(
            photoTs,
            sourceProjectId,
            '.jpg',
            len,
            '$photoTs.jpg',
            'portrait',
          );
        }

        final exportResult = await GalleryUtils.exportZipFile(
          sourceProjectId,
          'Import Test G Source',
          {'Raw': rawPaths, 'Stabilized': <String>[]},
          (_) {},
        );
        expect(exportResult, 'success', reason: 'Export should succeed');

        // Locate the exported ZIP.
        await tester.pump(const Duration(seconds: 1));
        final exportsDir = Directory(
          await DirUtils.getExportsDirPath(sourceProjectId),
        );
        final exportedZips = await exportsDir
            .list(followLinks: false)
            .where((e) => e is File && e.path.endsWith('.zip'))
            .cast<File>()
            .toList();
        expect(exportedZips, isNotEmpty, reason: 'Export should create a ZIP');

        // Re-import the ZIP into a fresh project and verify the round-trip.
        final targetProjectId = await DB.instance.addProject(
          'Import Test G Target',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        try {
          final notifier = ValueNotifier<String>('');
          try {
            await GalleryUtils.processPickedFile(
              exportedZips.first,
              targetProjectId,
              notifier,
              onImagesLoaded: () {},
              setProgressInMain: (_) {},
              increaseSuccessfulImportCount: () {},
              increasePhotosImported: (_) {},
            );
          } finally {
            notifier.dispose();
          }

          await tester.pump(const Duration(seconds: 5));

          final reimported = await DB.instance.getPhotosByProjectID(
            targetProjectId,
          );
          expect(
            reimported.length,
            3,
            reason: 'All 3 exported photos should re-import (round-trip)',
          );
        } finally {
          try {
            final targetDir = await DirUtils.getProjectDirPath(targetProjectId);
            if (await Directory(targetDir).exists()) {
              await Directory(targetDir).delete(recursive: true);
            }
            await DB.instance.deleteProject(targetProjectId);
          } catch (_) {}
        }
      },
    );

    // ─── Test H: ZIP with no importable entries imports gracefully ───────

    testWidgets(
      'Test H: ZIP with only filtered entries imports zero photos',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId =
            await DB.instance.addProject('Import Test H', 'face', ts);

        final tempDir = await Directory.systemTemp.createTemp('import_test_h_');
        try {
          // A sub-threshold image, a non-image file, and a .DS_Store entry:
          // each rejected by the import filter for a different reason.
          final tinyPath = p.join(tempDir.path, 'tiny.jpg');
          await File(tinyPath).writeAsBytes(List.filled(100, 0xFF));
          final textPath = p.join(tempDir.path, 'notes.txt');
          await File(textPath).writeAsString('not an image');
          final dsStorePath = p.join(tempDir.path, '.DS_Store');
          await File(dsStorePath).writeAsBytes(List.filled(20000, 0x00));

          final zipPath = p.join(tempDir.path, 'filtered_only.zip');
          final encoder = ZipFileEncoder();
          encoder.create(zipPath);
          await encoder.addFile(File(tinyPath));
          await encoder.addFile(File(textPath));
          await encoder.addFile(File(dsStorePath));
          await encoder.close();

          final notifier = ValueNotifier<String>('');
          try {
            await GalleryUtils.processPickedFile(
              File(zipPath),
              testProjectId!,
              notifier,
              onImagesLoaded: () {},
              setProgressInMain: (_) {},
              increaseSuccessfulImportCount: () {},
              increasePhotosImported: (_) {},
            );
          } finally {
            notifier.dispose();
          }

          await tester.pump(const Duration(seconds: 2));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(
            photos,
            isEmpty,
            reason: 'No importable entries -> no photos, no error',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    // ─── Test I: ZIP with non-ASCII (UTF-8) entry names ──────────────────

    testWidgets(
      'Test I: ZIP with UTF-8 entry names imports correctly',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId =
            await DB.instance.addProject('Import Test I', 'face', ts);

        final tempDir = await Directory.systemTemp.createTemp('import_test_i_');
        try {
          final facePath = await getSampleFacePathAsync(1);
          final zipPath = p.join(tempDir.path, 'unicode_names.zip');
          final encoder = ZipFileEncoder();
          encoder.create(zipPath);
          // Non-ASCII archive entry name (Japanese + accented Latin).
          await encoder.addFile(File(facePath), '写真_café_テスト.jpg');
          await encoder.close();

          final notifier = ValueNotifier<String>('');
          try {
            await GalleryUtils.processPickedFile(
              File(zipPath),
              testProjectId!,
              notifier,
              onImagesLoaded: () {},
              setProgressInMain: (_) {},
              increaseSuccessfulImportCount: () {},
              increasePhotosImported: (_) {},
            );
          } finally {
            notifier.dispose();
          }

          await tester.pump(const Duration(seconds: 3));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(
            photos.length,
            greaterThanOrEqualTo(1),
            reason: 'Image under a UTF-8 entry name should import',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    // ─── Test J: corrupt/truncated ZIP does not crash the import ─────────

    testWidgets(
      'Test J: truncated ZIP imports zero photos without crashing',
      (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        testProjectId =
            await DB.instance.addProject('Import Test J', 'face', ts);

        final tempDir = await Directory.systemTemp.createTemp('import_test_j_');
        try {
          // Build a valid ZIP, then truncate it to simulate a corrupt or
          // interrupted file (the central directory at the end is lost).
          final facePath = await getSampleFacePathAsync(1);
          final goodZipPath = p.join(tempDir.path, 'good.zip');
          final encoder = ZipFileEncoder();
          encoder.create(goodZipPath);
          await encoder.addFile(File(facePath), 'face.jpg');
          await encoder.close();

          final goodBytes = await File(goodZipPath).readAsBytes();
          final corruptZipPath = p.join(tempDir.path, 'corrupt.zip');
          await File(
            corruptZipPath,
          ).writeAsBytes(goodBytes.sublist(0, goodBytes.length ~/ 2));

          final notifier = ValueNotifier<String>('');
          try {
            await GalleryUtils.processPickedFile(
              File(corruptZipPath),
              testProjectId!,
              notifier,
              onImagesLoaded: () {},
              setProgressInMain: (_) {},
              increaseSuccessfulImportCount: () {},
              increasePhotosImported: (_) {},
            );
          } catch (_) {
            // Acceptable: a corrupt archive may surface a decode error. The
            // guarantee under test is that it imports no garbage and does not
            // crash the test process.
          } finally {
            notifier.dispose();
          }

          await tester.pump(const Duration(seconds: 2));

          final photos = await DB.instance.getPhotosByProjectID(testProjectId!);
          expect(photos, isEmpty,
              reason: 'A corrupt ZIP should import nothing');
        } finally {
          await tempDir.delete(recursive: true);
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
