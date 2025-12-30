import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Integration tests for image format conversion (AVIF, HEIC).
///
/// These tests validate that the app can correctly import and convert
/// various image formats across all supported platforms.
///
/// Run with: `flutter test integration_test/image_format_test.dart -d <platform>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Image Format Conversion Tests', () {
    late Directory tempDir;
    late String avifPath;
    late String heicPath;

    setUpAll(() async {
      // Preload fixtures on mobile platforms
      await preloadFixtures();
      if (!fixturesUnavailable) {
        avifPath = await getFixturePathAsync('sample-avif.avif');
        heicPath = await getFixturePathAsync('sample-heic.HEIC');
      }
    });

    setUp(() async {
      // Create a temp directory for output files
      tempDir = await Directory.systemTemp.createTemp('agelapse_format_test_');
    });

    tearDown(() async {
      // Clean up temp directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    testWidgets('AVIF to PNG conversion works', (tester) async {
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available on this platform');
        return;
      }

      final avifFile = File(avifPath);

      // Verify sample file exists
      if (!await avifFile.exists()) {
        markTestSkipped('Sample AVIF file not found at: $avifPath');
        return;
      }

      // Define output PNG path
      final pngPath = p.join(tempDir.path, 'converted-avif.png');

      // Perform conversion
      final result = await GalleryUtils.convertAvifToPng(avifPath, pngPath);

      // Verify conversion succeeded
      expect(result, isTrue, reason: 'AVIF to PNG conversion should succeed');

      // Verify PNG file was created
      final pngFile = File(pngPath);
      expect(await pngFile.exists(), isTrue,
          reason: 'PNG output file should exist after conversion');

      // Verify PNG file has reasonable size (not empty)
      final pngSize = await pngFile.length();
      expect(pngSize, greaterThan(1000),
          reason: 'PNG file should have reasonable size (got $pngSize bytes)');
    });

    testWidgets('HEIC to JPG conversion works on macOS', (tester) async {
      // Skip on non-macOS platforms for now (HEIC uses sips on macOS)
      if (!Platform.isMacOS) {
        // HEIC conversion uses different methods per platform
        // This test focuses on macOS sips conversion
        return;
      }

      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available on this platform');
        return;
      }

      final heicFile = File(heicPath);

      // Verify sample file exists
      if (!await heicFile.exists()) {
        markTestSkipped('Sample HEIC file not found at: $heicPath');
        return;
      }

      // Define output JPG path
      final jpgPath = p.join(tempDir.path, 'converted-heic.jpg');

      // Perform conversion using sips (macOS built-in tool)
      final result = await Process.run(
        'sips',
        ['-s', 'format', 'jpeg', heicPath, '--out', jpgPath],
      );

      // Verify conversion succeeded
      expect(result.exitCode, equals(0),
          reason:
              'sips HEIC to JPG conversion should succeed: ${result.stderr}');

      // Verify JPG file was created
      final jpgFile = File(jpgPath);
      expect(await jpgFile.exists(), isTrue,
          reason: 'JPG output file should exist after conversion');

      // Verify JPG file has reasonable size (not empty)
      final jpgSize = await jpgFile.length();
      expect(jpgSize, greaterThan(1000),
          reason: 'JPG file should have reasonable size (got $jpgSize bytes)');
    });

    testWidgets('AVIF conversion handles invalid file gracefully',
        (tester) async {
      // Test with non-existent file - use a path that definitely doesn't exist
      final fakePath = p.join(tempDir.path, 'nonexistent.avif');
      final pngPath = p.join(tempDir.path, 'should-not-exist.png');

      final result = await GalleryUtils.convertAvifToPng(fakePath, pngPath);

      // Should return false, not crash
      expect(result, isFalse,
          reason: 'Conversion should return false for non-existent file');

      // PNG should not be created
      final pngFile = File(pngPath);
      expect(await pngFile.exists(), isFalse,
          reason: 'PNG should not be created when source does not exist');
    });

    testWidgets('converted PNG is valid and readable', (tester) async {
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available on this platform');
        return;
      }

      final avifFile = File(avifPath);
      if (!await avifFile.exists()) {
        markTestSkipped('Sample AVIF file not found at: $avifPath');
        return;
      }

      final pngPath = p.join(tempDir.path, 'validated-conversion.png');

      // Convert AVIF to PNG
      final conversionResult =
          await GalleryUtils.convertAvifToPng(avifPath, pngPath);
      expect(conversionResult, isTrue);

      // Read the PNG file
      final pngFile = File(pngPath);
      final pngBytes = await pngFile.readAsBytes();

      // Verify PNG magic number (first 8 bytes)
      // PNG signature: 137 80 78 71 13 10 26 10
      expect(pngBytes.length, greaterThan(8));
      expect(pngBytes[0], equals(137),
          reason: 'PNG should start with correct magic number');
      expect(pngBytes[1], equals(80), reason: 'P');
      expect(pngBytes[2], equals(78), reason: 'N');
      expect(pngBytes[3], equals(71), reason: 'G');
    });
  });
}
