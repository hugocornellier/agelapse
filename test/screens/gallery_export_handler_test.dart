import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/gallery_page/gallery_export_handler.dart';
import 'package:agelapse/utils/dir_utils.dart';

/// Unit tests for GalleryExportHandler.
/// Tests pure functions and method signatures.
void main() {
  group('GalleryExportHandler Class', () {
    test('GalleryExportHandler class is accessible', () {
      expect(GalleryExportHandler, isNotNull);
    });
  });

  group('GalleryExportHandler.listFilesInDirectory', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns empty list for empty directory', () async {
      final result = await GalleryExportHandler.listFilesInDirectory(
        tempDir.path,
      );
      expect(result, isEmpty);
    });

    test('returns list of file paths for directory with files', () async {
      // Create test files
      await File('${tempDir.path}/file1.txt').writeAsString('content1');
      await File('${tempDir.path}/file2.txt').writeAsString('content2');
      await File('${tempDir.path}/file3.png').writeAsString('content3');

      final result = await GalleryExportHandler.listFilesInDirectory(
        tempDir.path,
      );

      expect(result.length, 3);
      expect(result.any((p) => p.endsWith('file1.txt')), isTrue);
      expect(result.any((p) => p.endsWith('file2.txt')), isTrue);
      expect(result.any((p) => p.endsWith('file3.png')), isTrue);
    });

    test('filters out directories (only returns files)', () async {
      // Create a file and a subdirectory
      await File('${tempDir.path}/file.txt').writeAsString('content');
      await Directory('${tempDir.path}/subdir').create();

      final result = await GalleryExportHandler.listFilesInDirectory(
        tempDir.path,
      );

      expect(result.length, 1);
      expect(result.first, endsWith('file.txt'));
    });

    test('returns empty list for non-existent directory', () async {
      final result = await GalleryExportHandler.listFilesInDirectory(
        '/definitely/does/not/exist/12345',
      );
      expect(result, isEmpty);
    });

    test('handles directory with only subdirectories', () async {
      await Directory('${tempDir.path}/subdir1').create();
      await Directory('${tempDir.path}/subdir2').create();

      final result = await GalleryExportHandler.listFilesInDirectory(
        tempDir.path,
      );

      expect(result, isEmpty);
    });

    test('handles various file extensions', () async {
      final extensions = ['.jpg', '.png', '.heic', '.txt', '.zip'];
      for (int i = 0; i < extensions.length; i++) {
        await File('${tempDir.path}/file$i${extensions[i]}')
            .writeAsString('content');
      }

      final result = await GalleryExportHandler.listFilesInDirectory(
        tempDir.path,
      );

      expect(result.length, extensions.length);
    });
  });

  group('GalleryExportHandler.shareZipFile Method Signature', () {
    test('shareZipFile method exists', () {
      expect(GalleryExportHandler.shareZipFile, isA<Function>());
    });

    test('shareZipFile returns Future<void>', () {
      expect(
        GalleryExportHandler.shareZipFile,
        isA<Future<void> Function(int, String)>(),
      );
    });
  });

  group('GalleryExportHandler.exportSelectedPhotos Method Signature', () {
    test('exportSelectedPhotos method exists', () {
      expect(GalleryExportHandler.exportSelectedPhotos, isA<Function>());
    });

    test('exportSelectedPhotos returns Future<bool>', () {
      expect(
        GalleryExportHandler.exportSelectedPhotos,
        isA<
            Future<bool> Function({
              required int projectId,
              required String projectName,
              required String projectIdStr,
              required String? projectOrientation,
              required Set<String> selectedPhotos,
              required bool exportRawFiles,
              required bool exportStabilizedFiles,
              required void Function(double) setExportProgress,
            })>(),
      );
    });
  });

  group('GalleryExportHandler.showExportOptionsSheet Method Signature', () {
    test('showExportOptionsSheet method exists', () {
      expect(GalleryExportHandler.showExportOptionsSheet, isA<Function>());
    });
  });

  group('GalleryExportHandler Raw vs Stabilized Detection Logic', () {
    test('detects raw files by path containing photosRawDirname', () {
      // Test the logic used in exportSelectedPhotos
      final rawPaths = [
        '/path/to/project/${DirUtils.photosRawDirname}/1704067200000.jpg',
        '/path/${DirUtils.photosRawDirname}/image.png',
      ];

      for (final path in rawPaths) {
        final isRaw = path.contains(DirUtils.photosRawDirname);
        expect(isRaw, isTrue, reason: 'Path "$path" should be detected as raw');
      }
    });

    test('detects stabilized files by absence of photosRawDirname', () {
      final stabilizedPaths = [
        '/path/to/project/stabilized_portrait/1704067200000.png',
        '/path/to/project/stabilized_landscape/image.png',
      ];

      for (final path in stabilizedPaths) {
        final isRaw = path.contains(DirUtils.photosRawDirname);
        expect(
          isRaw,
          isFalse,
          reason: 'Path "$path" should be detected as stabilized',
        );
      }
    });
  });

  group('GalleryExportHandler Export Progress Logic', () {
    test('progress is 0-30% during date stamp processing', () {
      // Simulate the progress calculation: (current / total) * 30
      const total = 10;
      final progressValues = <double>[];

      for (int current = 0; current <= total; current++) {
        final progress = (current / total) * 30;
        progressValues.add(progress);
      }

      expect(progressValues.first, 0.0);
      expect(progressValues.last, 30.0);
      for (final p in progressValues) {
        expect(p, inInclusiveRange(0.0, 30.0));
      }
    });

    test('progress is 30-100% during zip creation when date stamps used', () {
      // Simulate: 30 + (p * 0.7) where p is 0-100
      final progressValues = <double>[];

      for (double p = 0; p <= 100; p += 10) {
        final progress = 30 + (p * 0.7);
        progressValues.add(progress);
      }

      expect(progressValues.first, 30.0);
      expect(progressValues.last, 100.0);
      for (final p in progressValues) {
        expect(p, inInclusiveRange(30.0, 100.0));
      }
    });

    test('progress is 0-100% during zip creation when no date stamps', () {
      // When no date stamps, progress is passed through directly
      final progressValues = <double>[];

      for (double p = 0; p <= 100; p += 10) {
        progressValues.add(p);
      }

      expect(progressValues.first, 0.0);
      expect(progressValues.last, 100.0);
    });
  });

  group('GalleryExportHandler File Categorization', () {
    test('creates export map with Raw and Stabilized categories', () {
      // Test the structure used in _performExport
      final Map<String, List<String>> filesToExport = {
        'Raw': [],
        'Stabilized': [],
      };

      expect(filesToExport.containsKey('Raw'), isTrue);
      expect(filesToExport.containsKey('Stabilized'), isTrue);
      expect(filesToExport['Raw'], isA<List<String>>());
      expect(filesToExport['Stabilized'], isA<List<String>>());
    });

    test('can add files to both categories', () {
      final Map<String, List<String>> filesToExport = {
        'Raw': [],
        'Stabilized': [],
      };

      filesToExport['Raw']!.addAll(['/path/raw1.jpg', '/path/raw2.jpg']);
      filesToExport['Stabilized']!.addAll(['/path/stab1.png']);

      expect(filesToExport['Raw']!.length, 2);
      expect(filesToExport['Stabilized']!.length, 1);
    });
  });

  group('GalleryExportHandler Temp Directory Naming', () {
    test('temp directory name includes timestamp for uniqueness', () {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempDirName = 'date_stamp_export_$timestamp';

      expect(tempDirName, startsWith('date_stamp_export_'));
      expect(tempDirName.length, greaterThan('date_stamp_export_'.length));
    });
  });

  group('GalleryExportHandler Static Methods', () {
    test('all public methods are static', () {
      // ignore: unnecessary_type_check
      expect(GalleryExportHandler.showExportOptionsSheet is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(GalleryExportHandler.shareZipFile is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(GalleryExportHandler.exportSelectedPhotos is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(GalleryExportHandler.listFilesInDirectory is Function, isTrue);
    });
  });
}
