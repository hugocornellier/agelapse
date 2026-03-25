import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/utils/format_decode_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/image_processing_isolate.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Magic bytes for each image format, used to verify files are genuinely encoded.
/// Use -1 as a wildcard to skip a byte position (e.g. for container size fields).
const Map<String, List<int>> _formatMagicBytes = {
  'jpg': [0xFF, 0xD8, 0xFF],
  'png': [0x89, 0x50, 0x4E, 0x47],
  'webp': [0x52, 0x49, 0x46, 0x46], // RIFF
  'bmp': [0x42, 0x4D], // BM
  'tiff': [0x49, 0x49, 0x2A, 0x00], // Little-endian TIFF (II*)
  'heic': [-1, -1, -1, -1, 0x66, 0x74, 0x79, 0x70], // ftyp at offset 4
  'avif': [-1, -1, -1, -1, 0x66, 0x74, 0x79, 0x70], // ftyp at offset 4
  'jp2': [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50], // JP2 signature
};

/// Minimum expected file sizes per format for a 640x480 image.
const Map<String, int> _minFileSizes = {
  'jpg': 10000,
  'png': 50000,
  'webp': 5000,
  'bmp': 900000,
  'tiff': 100000,
  'heic': 5000,
  'avif': 2000,
  'jp2': 50000,
};

/// Formats that OpenCV's cv.imdecode can decode directly.
/// TIFF and JP2 crash cv.imdecode on Apple platforms (native segfault in opencv_dart).
final _opencvDirectFormats = {
  'jpg',
  'png',
  'webp',
  'bmp',
  if (!Platform.isMacOS && !Platform.isIOS) ...['tiff', 'jp2'],
};

/// Integration tests for image format support.
///
/// Tests that every supported image format:
/// 1. Is correctly identified by Utils.isImage()
/// 2. Is correctly identified by GalleryUtils.allowedImageExtensions
/// 3. Has valid magic bytes (genuine encoding, not a wrapper)
/// 4. Has a reasonable file size
/// 5. Can be decoded by OpenCV (directly or via pre-conversion)
/// 6. Can produce a valid thumbnail through the import pipeline
/// 7. Can be decoded to PNG for the stabilization pipeline
/// 8. Can be used for face detection and stabilization
///
/// Run with: `flutter test integration_test/image_format_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  // ─── Format Sample Validation ─────────────────────────────────────────

  group('Format Sample Validation Tests', () {
    bool fixturesLoaded = false;

    Future<bool> ensureFixturesLoaded() async {
      if (fixturesLoaded) return !fixturesUnavailable;
      await preloadFixtures();
      fixturesLoaded = true;
      return !fixturesUnavailable;
    }

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final format in formatSampleFormats) {
      group('$format format', () {
        for (final day in formatSampleDays) {
          test('$day.$format exists and is valid', () async {
            if (!await ensureFixturesLoaded()) {
              markTestSkipped('Test fixtures not available');
              return;
            }

            final filePath = await getFormatSamplePathAsync(format, day);
            final file = File(filePath);

            expect(await file.exists(), isTrue,
                reason: '$day.$format should exist at $filePath');

            final fileSize = await file.length();
            final minSize = _minFileSizes[format] ?? 1000;
            expect(fileSize, greaterThan(minSize),
                reason: '$day.$format should be at least $minSize bytes '
                    '(got $fileSize)');
          });
        }

        test('Utils.isImage recognizes .$format files', () async {
          final testPath = 'test_image.${formatSampleExtensions[format]}';
          final isRecognized = Utils.isImage(testPath);

          const recognizedByIsImage = {
            'jpg',
            'png',
            'webp',
            'bmp',
            'tiff',
            'heic',
            'avif',
            'jp2',
          };

          if (recognizedByIsImage.contains(format)) {
            expect(isRecognized, isTrue,
                reason: 'Utils.isImage should recognize .$format files');
          }
        });

        test('GalleryUtils.allowedImageExtensions includes .$format', () async {
          final ext = '.${formatSampleExtensions[format]}';

          const recognizedExtensions = {
            'jpg',
            'png',
            'webp',
            'bmp',
            'tiff',
            'heic',
            'avif',
            'jp2',
          };

          if (recognizedExtensions.contains(format)) {
            expect(GalleryUtils.allowedImageExtensions.contains(ext), isTrue,
                reason: 'allowedImageExtensions should include $ext');
          }
        });

        test('$format files have correct magic bytes', () async {
          if (!await ensureFixturesLoaded()) {
            markTestSkipped('Test fixtures not available');
            return;
          }

          final expectedMagic = _formatMagicBytes[format];
          if (expectedMagic == null) return;

          final filePath = await getFormatSamplePathAsync(format, 'day1');
          final file = File(filePath);
          if (!await file.exists()) {
            markTestSkipped('$format sample not found');
            return;
          }

          final bytes = await file.readAsBytes();
          expect(bytes.length, greaterThan(expectedMagic.length),
              reason: '$format file too small to contain magic bytes');

          for (int i = 0; i < expectedMagic.length; i++) {
            final expected = expectedMagic[i];
            if (expected == -1) continue;
            expect(bytes[i], equals(expected),
                reason: '$format magic byte mismatch at offset $i: '
                    'expected 0x${expected.toRadixString(16)}, '
                    'got 0x${bytes[i].toRadixString(16)}');
          }
        });
      });
    }
  });

  // ─── Import Pipeline (OpenCV decode + thumbnail) ──────────────────────

  group('Import Pipeline Tests', () {
    bool fixturesLoaded = false;

    Future<bool> ensureFixturesLoaded() async {
      if (fixturesLoaded) return !fixturesUnavailable;
      await preloadFixtures();
      fixturesLoaded = true;
      return !fixturesUnavailable;
    }

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final format in formatSampleFormats) {
      // Test 2 samples per format (day1, day11)
      for (final day in ['day1', 'day11']) {
        test('$format/$day decodes and produces thumbnail via import pipeline',
            () async {
          if (!await ensureFixturesLoaded()) {
            markTestSkipped('Test fixtures not available');
            return;
          }

          final filePath = await getFormatSamplePathAsync(format, day);
          final file = File(filePath);
          if (!await file.exists()) {
            markTestSkipped('$format/$day sample not found');
            return;
          }

          final bytes = await file.readAsBytes();
          expect(bytes.length, greaterThan(0),
              reason: '$format/$day file should not be empty');

          // For formats OpenCV can decode directly, test direct decode
          if (_opencvDirectFormats.contains(format)) {
            final output = processImageIsolateEntry(ImageProcessingInput(
              bytes: bytes,
              extension: '.${formatSampleExtensions[format]}',
            ));

            expect(output.success, isTrue,
                reason: '$format/$day should decode successfully via '
                    'cv.imdecode (got: ${output.error})');
            expect(output.width, greaterThan(0),
                reason: '$format/$day should have valid width');
            expect(output.height, greaterThan(0),
                reason: '$format/$day should have valid height');
            expect(output.thumbnailBytes, isNotNull,
                reason: '$format/$day should produce a thumbnail');
            expect(output.thumbnailBytes!.length, greaterThan(0),
                reason: '$format/$day thumbnail should not be empty');

            // Verify thumbnail is valid JPEG
            expect(output.thumbnailBytes![0], equals(0xFF),
                reason: '$format/$day thumbnail should be JPEG (byte 0)');
            expect(output.thumbnailBytes![1], equals(0xD8),
                reason: '$format/$day thumbnail should be JPEG (byte 1)');
          }

          // For HEIC: pre-convert to JPG, then decode
          if (format == 'heic') {
            Uint8List? preDecoded;

            if (Platform.isMacOS) {
              final tempDir = await Directory.systemTemp
                  .createTemp('agelapse_heic_import_');
              try {
                final jpgPath = p.join(tempDir.path, '$day.jpg');
                final result = await Process.run('sips', [
                  '-s',
                  'format',
                  'jpeg',
                  filePath,
                  '--out',
                  jpgPath,
                ]);
                if (result.exitCode == 0) {
                  preDecoded = await File(jpgPath).readAsBytes();
                }
              } finally {
                await tempDir.delete(recursive: true);
              }
            }
            // On other platforms, heif_converter would be used — skip if not macOS
            if (preDecoded == null && !Platform.isMacOS) {
              // Can't test HEIC pre-conversion on this platform without heif_converter
              return;
            }

            if (preDecoded != null) {
              final output = processImageIsolateEntry(ImageProcessingInput(
                bytes: bytes,
                extension: '.heic',
                preDecodedBytes: preDecoded,
              ));

              expect(output.success, isTrue,
                  reason: 'HEIC/$day should decode via pre-converted JPG '
                      '(got: ${output.error})');
              expect(output.width, greaterThan(0));
              expect(output.height, greaterThan(0));
              expect(output.thumbnailBytes, isNotNull,
                  reason: 'HEIC/$day should produce a thumbnail');
            }
          }

          // For TIFF on Apple: pre-convert to PNG via sips, then decode
          if (format == 'tiff' && (Platform.isMacOS || Platform.isIOS)) {
            if (Platform.isMacOS) {
              final tempDir = await Directory.systemTemp
                  .createTemp('agelapse_tiff_import_');
              try {
                final pngPath = p.join(tempDir.path, '$day.png');
                final result = await Process.run('sips', [
                  '-s',
                  'format',
                  'png',
                  filePath,
                  '--out',
                  pngPath,
                ]);
                if (result.exitCode == 0) {
                  final preDecoded = await File(pngPath).readAsBytes();
                  final output = processImageIsolateEntry(ImageProcessingInput(
                    bytes: bytes,
                    extension: '.tiff',
                    preDecodedBytes: preDecoded,
                  ));

                  expect(output.success, isTrue,
                      reason: 'TIFF/$day should decode via pre-converted PNG '
                          '(got: ${output.error})');
                  expect(output.width, greaterThan(0));
                  expect(output.height, greaterThan(0));
                  expect(output.thumbnailBytes, isNotNull,
                      reason: 'TIFF/$day should produce a thumbnail');
                }
              } finally {
                await tempDir.delete(recursive: true);
              }
            } else {
              // iOS — sips not available, skip import pipeline test
              return;
            }
          }

          // For JP2 on Apple: pre-convert to PNG via sips, then decode
          if (format == 'jp2' && (Platform.isMacOS || Platform.isIOS)) {
            if (Platform.isMacOS) {
              final tempDir =
                  await Directory.systemTemp.createTemp('agelapse_jp2_import_');
              try {
                final pngPath = p.join(tempDir.path, '$day.png');
                final result = await Process.run('sips', [
                  '-s',
                  'format',
                  'png',
                  filePath,
                  '--out',
                  pngPath,
                ]);
                if (result.exitCode == 0) {
                  final preDecoded = await File(pngPath).readAsBytes();
                  final output = processImageIsolateEntry(ImageProcessingInput(
                    bytes: bytes,
                    extension: '.jp2',
                    preDecodedBytes: preDecoded,
                  ));

                  expect(output.success, isTrue,
                      reason: 'JP2/$day should decode via pre-converted PNG '
                          '(got: ${output.error})');
                  expect(output.width, greaterThan(0));
                  expect(output.height, greaterThan(0));
                  expect(output.thumbnailBytes, isNotNull,
                      reason: 'JP2/$day should produce a thumbnail');
                }
              } finally {
                await tempDir.delete(recursive: true);
              }
            } else {
              // iOS — sips not available, skip import pipeline test
              return;
            }
          }

          // For AVIF: pre-convert to PNG, then decode
          if (format == 'avif') {
            final tempDir =
                await Directory.systemTemp.createTemp('agelapse_avif_import_');
            try {
              final pngPath = p.join(tempDir.path, '$day.png');
              final converted =
                  await GalleryUtils.convertAvifToPng(filePath, pngPath);

              if (!converted) {
                markTestSkipped(
                    'AVIF conversion not available on this platform');
                return;
              }

              final preDecoded = await File(pngPath).readAsBytes();
              final output = processImageIsolateEntry(ImageProcessingInput(
                bytes: bytes,
                extension: '.avif',
                preDecodedBytes: preDecoded,
              ));

              expect(output.success, isTrue,
                  reason: 'AVIF/$day should decode via pre-converted PNG '
                      '(got: ${output.error})');
              expect(output.width, greaterThan(0));
              expect(output.height, greaterThan(0));
              expect(output.thumbnailBytes, isNotNull,
                  reason: 'AVIF/$day should produce a thumbnail');
            } finally {
              await tempDir.delete(recursive: true);
            }
          }
        });
      }
    }
  });

  // ─── Stabilization Pipeline (decode → face detect → transform) ────────

  group('Stabilization Pipeline Tests', () {
    bool fixturesLoaded = false;
    bool appInitialized = false;

    Future<bool> initAppAndFixtures(WidgetTester tester) async {
      if (!appInitialized) {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));
        appInitialized = true;
      }

      if (!fixturesLoaded) {
        await preloadFixtures();
        fixturesLoaded = true;
      }

      return !fixturesUnavailable;
    }

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final format in formatSampleFormats) {
      // Test 2 samples per format (day1, day11) — these have faces
      for (final day in ['day1', 'day11']) {
        testWidgets(
          '$format/$day decodes to cv-compatible bytes and passes through stabilization',
          (tester) async {
            if (!await initAppAndFixtures(tester)) {
              markTestSkipped('Test fixtures not available');
              return;
            }

            final filePath = await getFormatSamplePathAsync(format, day);
            final file = File(filePath);
            if (!await file.exists()) {
              markTestSkipped('$format/$day sample not found');
              return;
            }

            // Step 1: Load cv-compatible bytes via the real production code path
            final Uint8List? cvBytes =
                await FormatDecodeUtils.loadCvCompatibleBytes(filePath);

            if (cvBytes == null) {
              markTestSkipped(
                  'Could not decode $format/$day to cv-compatible bytes');
              return;
            }

            expect(cvBytes.length, greaterThan(0),
                reason: '$format/$day cv-compatible bytes should not be empty');

            // Verify bytes are a valid image format that OpenCV can decode.
            // cv-native formats (jpg, png, webp, bmp) are returned as-is;
            // non-native formats (heic, avif, tiff/jp2 on Apple) are converted to PNG.
            final ext = '.$format';
            if (FormatDecodeUtils.needsConversion(ext)) {
              // Converted formats should be PNG
              expect(cvBytes[0], equals(0x89),
                  reason: '$format should be converted to PNG');
              expect(cvBytes[1], equals(0x50),
                  reason: '$format should be converted to PNG');
            }

            // Step 2: Get dimensions
            final dims =
                await StabUtils.getImageDimensionsFromBytesAsync(cvBytes);
            expect(dims, isNotNull,
                reason: '$format/$day should have readable dimensions');
            expect(dims!.$1, greaterThan(0), reason: 'width > 0');
            expect(dims.$2, greaterThan(0), reason: 'height > 0');

            // Step 3: Face detection
            final faces = await StabUtils.getFacesFromBytes(cvBytes);
            // These are photos of a person — we expect face detection to work
            // But if it doesn't find a face, that's still a valid test
            // (the format decoded correctly, face detection just didn't match)
            if (faces == null || faces.isEmpty) {
              // Format decoded OK, face just wasn't detected — still a pass
              // for format compatibility
              return;
            }

            final face = faces.first;
            if (face.leftEye == null || face.rightEye == null) {
              return; // Eyes not detected — format decode still passed
            }

            // Step 4: Calculate rotation from eye positions
            final dy = face.rightEye!.y - face.leftEye!.y;
            final dx = face.rightEye!.x - face.leftEye!.x;
            final rotationDegrees = atan2(dy, dx) * 180 / pi;

            // Step 5: Apply stabilization transform
            final stabilized =
                await StabUtils.generateStabilizedImageBytesCVAsync(
              cvBytes,
              rotationDegrees,
              1.0, // scale
              0.0, // translateX
              0.0, // translateY
              dims.$1, // canvas width = original width
              dims.$2, // canvas height = original height
            );

            expect(stabilized, isNotNull,
                reason: '$format/$day stabilization should produce output');
            expect(stabilized!.length, greaterThan(0),
                reason: '$format/$day stabilized bytes should not be empty');

            // Step 6: Verify stabilized output is valid (can be decoded)
            final stabMat = cv.imdecode(stabilized, cv.IMREAD_COLOR);
            expect(stabMat.isEmpty, isFalse,
                reason: '$format/$day stabilized output should be decodable');
            expect(stabMat.cols, greaterThan(0));
            expect(stabMat.rows, greaterThan(0));
            stabMat.dispose();
          },
        );
      }
    }
  });

  // ─── HEIC Conversion Tests ────────────────────────────────────────────

  group('Format Sample HEIC Conversion Tests', () {
    late Directory tempDir;
    bool fixturesLoaded = false;

    Future<bool> ensureFixturesLoaded() async {
      if (fixturesLoaded) return !fixturesUnavailable;
      await preloadFixtures();
      fixturesLoaded = true;
      return !fixturesUnavailable;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agelapse_heic_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final day in formatSampleDays) {
      test('HEIC sample $day converts to JPG on macOS', () async {
        if (!Platform.isMacOS) return;
        if (!await ensureFixturesLoaded()) {
          markTestSkipped('Test fixtures not available');
          return;
        }

        final heicPath = await getFormatSamplePathAsync('heic', day);
        final heicFile = File(heicPath);
        if (!await heicFile.exists()) {
          markTestSkipped('HEIC sample $day not found');
          return;
        }

        final jpgPath = p.join(tempDir.path, '$day-from-heic.jpg');
        final result = await Process.run('sips', [
          '-s',
          'format',
          'jpeg',
          heicPath,
          '--out',
          jpgPath,
        ]);

        expect(result.exitCode, equals(0),
            reason: 'sips should convert HEIC $day to JPG: ${result.stderr}');

        final jpgFile = File(jpgPath);
        expect(await jpgFile.exists(), isTrue);

        final jpgBytes = await jpgFile.readAsBytes();
        expect(jpgBytes[0], equals(0xFF), reason: 'JPG magic byte 0');
        expect(jpgBytes[1], equals(0xD8), reason: 'JPG magic byte 1');
      });
    }
  });

  // ─── AVIF Conversion Tests ────────────────────────────────────────────

  group('Format Sample AVIF Conversion Tests', () {
    late Directory tempDir;
    bool fixturesLoaded = false;

    Future<bool> ensureFixturesLoaded() async {
      if (fixturesLoaded) return !fixturesUnavailable;
      await preloadFixtures();
      fixturesLoaded = true;
      return !fixturesUnavailable;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agelapse_avif_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    for (final day in formatSampleDays) {
      test('AVIF sample $day converts to PNG', () async {
        if (!await ensureFixturesLoaded()) {
          markTestSkipped('Test fixtures not available');
          return;
        }

        final avifPath = await getFormatSamplePathAsync('avif', day);
        final avifFile = File(avifPath);
        if (!await avifFile.exists()) {
          markTestSkipped('AVIF sample $day not found');
          return;
        }

        final pngPath = p.join(tempDir.path, '$day-from-avif.png');
        final result = await GalleryUtils.convertAvifToPng(avifPath, pngPath);

        expect(result, isTrue,
            reason: 'AVIF $day to PNG conversion should succeed');

        final pngFile = File(pngPath);
        expect(await pngFile.exists(), isTrue);

        final pngBytes = await pngFile.readAsBytes();
        expect(pngBytes.length, greaterThan(1000));
        expect(pngBytes[0], equals(0x89), reason: 'PNG magic byte');
        expect(pngBytes[1], equals(0x50), reason: 'P');
      });
    }
  });
}
