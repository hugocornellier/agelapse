import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
          reason:
              'ffmpeg.exe must run on a stock Windows machine.\n'
              'Exit code: ${result.exitCode}\n'
              'stderr: ${result.stderr}');

      final stdout = result.stdout as String;
      expect(stdout, contains('ffmpeg version'),
          reason: 'ffmpeg -version should print version info');

      // Cleanup.
      await testBinDir.delete(recursive: true);
    });
  });
}
