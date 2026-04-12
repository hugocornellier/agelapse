import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

/// Integration tests that verify bundled ffmpeg binaries can execute on a
/// stock Windows machine (no dev tools in PATH).
///
/// Run with: `flutter test integration_test/ffmpeg_binary_test.dart -d windows`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Bundled FFmpeg binary', () {
    testWidgets('executes on stock Windows PATH', (tester) async {
      if (!Platform.isWindows) {
        markTestSkipped('Windows-only test');
        return;
      }

      // Extract the bundled ffmpeg.exe and its DLLs to a temp directory.
      final tempDir = await getTemporaryDirectory();
      final testBinDir = Directory(p.join(tempDir.path, 'ffmpeg_test'));
      if (await testBinDir.exists()) {
        await testBinDir.delete(recursive: true);
      }
      await testBinDir.create(recursive: true);

      // Extract ffmpeg.exe
      final exePath = p.join(testBinDir.path, 'ffmpeg.exe');
      final bytes = await rootBundle.load('assets/ffmpeg/windows/ffmpeg.exe');
      await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      expect(await File(exePath).exists(), isTrue);

      // Extract bundled DLLs (if present in assets).
      const dlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];
      for (final dll in dlls) {
        try {
          final dllBytes = await rootBundle.load(
            'assets/ffmpeg/windows/$dll',
          );
          await File(p.join(testBinDir.path, dll))
              .writeAsBytes(dllBytes.buffer.asUint8List(), flush: true);
        } catch (_) {
          // DLL not bundled — binary should be fully static.
        }
      }

      // Use minimal PATH: only Windows system dirs + our bundle dir.
      // This simulates a real user's machine with no dev tools.
      final minimalPath = '${testBinDir.path};'
          r'C:\Windows\System32;C:\Windows';

      final result = await Process.run(
        exePath,
        ['-version'],
        environment: {'PATH': minimalPath},
      );

      expect(result.exitCode, equals(0),
          reason: 'ffmpeg.exe must run on a stock Windows machine.\n'
              'Exit code: ${result.exitCode}\n'
              'stderr: ${result.stderr}');

      final stdout = result.stdout as String;
      expect(stdout, contains('ffmpeg version'),
          reason: 'ffmpeg -version should print version info');

      // Cleanup.
      await testBinDir.delete(recursive: true);
    });

    testWidgets('drawtext filter works with bundled binary', (tester) async {
      if (!Platform.isWindows) {
        // macOS bundled FFmpeg only has h264_videotoolbox which needs hardware.
        // The actual date stamp tests cover macOS via the full compilation pipeline.
        markTestSkipped('Windows bundled binary test');
        return;
      }

      // Extract ffmpeg and DLLs
      final tempDir = await getTemporaryDirectory();
      final testDir = Directory(p.join(tempDir.path, 'drawtext_test'));
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
      await testDir.create(recursive: true);

      final exePath = p.join(testDir.path, 'ffmpeg.exe');
      final bytes = await rootBundle.load('assets/ffmpeg/windows/ffmpeg.exe');
      await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      for (final dll in ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll']) {
        try {
          final dllBytes = await rootBundle.load('assets/ffmpeg/windows/$dll');
          await File(p.join(testDir.path, dll))
              .writeAsBytes(dllBytes.buffer.asUint8List(), flush: true);
        } catch (_) {}
      }

      // Extract font
      final fontBytes =
          await rootBundle.load('assets/fonts/Inter/Inter-Medium.ttf');
      final fontPath = p.join(testDir.path, 'test_font.ttf');
      await File(fontPath)
          .writeAsBytes(fontBytes.buffer.asUint8List(), flush: true);

      // Create a test PNG frame using Dart (1x1 blue pixel)
      final framePath = p.join(testDir.path, 'frame.png');
      final listPath = p.join(testDir.path, 'list.txt');
      final outPath = p.join(testDir.path, 'out.mp4');

      // Minimal valid 320x240 PNG (solid blue) generated in Dart
      final pngBytes = await _createSolidPng(320, 240);
      await File(framePath).writeAsBytes(pngBytes, flush: true);

      // Create concat list
      final escapedFramePath = framePath.replaceAll('\\', '/');
      await File(listPath).writeAsString(
        "file '$escapedFramePath'\nduration 0.1\n"
        "file '$escapedFramePath'\nduration 0.1\n",
      );

      // Use just the filename (relative path) — working dir is set to font dir
      final escapedFontPath = p.basename(fontPath);
      final filterComplex = '[0]drawtext='
          'fontfile=$escapedFontPath'
          ':text=Jan 15\\, 2024'
          ':fontsize=24'
          ':fontcolor=white'
          ':x=10:y=10'
          ':enable=gte(t\\,0.000000)*lt(t\\,0.100000)'
          '[dt0]';

      // Run FFmpeg with drawtext (working dir = font dir for Windows)
      final result = await Process.run(
          exePath,
          [
            '-y',
            '-f',
            'concat',
            '-safe',
            '0',
            '-i',
            listPath,
            '-filter_complex',
            filterComplex,
            '-map',
            '[dt0]',
            '-vsync',
            'cfr',
            '-r',
            '30',
            '-pix_fmt',
            'yuv420p',
            '-c:v',
            'libx264',
            '-b:v',
            '1000k',
            outPath,
          ],
          workingDirectory: p.dirname(fontPath));

      // Print full stderr for debugging
      if (result.exitCode != 0) {
        // ignore: avoid_print
        print('FFmpeg drawtext stderr:\n${result.stderr}');
        // ignore: avoid_print
        print('FFmpeg drawtext stdout:\n${result.stdout}');
        // ignore: avoid_print
        print('Filter complex: $filterComplex');
        // ignore: avoid_print
        print('Font path: $fontPath');
        // ignore: avoid_print
        print('Escaped font path: $escapedFontPath');
      }

      expect(result.exitCode, 0,
          reason:
              'Drawtext filter failed.\nstderr: ${result.stderr}\nfilter: $filterComplex');

      // Cleanup
      await testDir.delete(recursive: true);
    });
  });
}

/// Creates a solid blue PNG image of the given dimensions.
Future<Uint8List> _createSolidPng(int width, int height) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}
