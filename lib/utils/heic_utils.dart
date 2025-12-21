import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class HeicUtils {
  static const String _winHeicConverterAssetPath =
      'assets/heic/windows/heicConverter.exe';
  static const String _winMarkerName = 'heicConverter.version';
  static const String _currentVersion = '0.4.0';
  static String? _cachedExePath;

  /// Ensures HeicConverter.exe is extracted and returns its path.
  /// Returns empty string on non-Windows platforms.
  static Future<String> _ensureBundledHeicConverter() async {
    if (!Platform.isWindows) return '';
    if (_cachedExePath != null && await File(_cachedExePath!).exists()) {
      return _cachedExePath!;
    }

    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(path.join(dir.path, 'bin'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }

    final exePath = path.join(binDir.path, 'heicConverter.exe');
    final markerPath = path.join(binDir.path, _winMarkerName);
    final exeExists = await File(exePath).exists();
    final markerExists = await File(markerPath).exists();

    bool needsExtraction = !exeExists || !markerExists;

    // Check if version changed (for future updates)
    if (!needsExtraction && markerExists) {
      try {
        final storedVersion = await File(markerPath).readAsString();
        if (storedVersion.trim() != _currentVersion) {
          needsExtraction = true;
        }
      } catch (_) {
        needsExtraction = true;
      }
    }

    if (needsExtraction) {
      print('[HEIC] Extracting bundled heicConverter.exe...');
      try {
        final bytes = await rootBundle.load(_winHeicConverterAssetPath);
        await File(exePath)
            .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        await File(markerPath).writeAsString(_currentVersion, flush: true);
        print('[HEIC] heicConverter.exe extracted to: $exePath');
      } catch (e) {
        print('[HEIC] ERROR extracting heicConverter.exe: $e');
        return '';
      }
    }

    _cachedExePath = exePath;
    return exePath;
  }

  /// Converts HEIC to JPG on Windows using bundled HeicConverter.exe.
  /// Returns the output JPG path, or null if conversion failed.
  static Future<String?> convertHeicToJpg(String heicPath,
      {int quality = 95}) async {
    if (!Platform.isWindows) return null;

    final exePath = await _ensureBundledHeicConverter();
    if (exePath.isEmpty) return null;

    final jpgPath = path.setExtension(heicPath, '.jpg');

    // HeicConverter outputs JPG next to the original file by default
    final result = await Process.run(
      exePath,
      ['-q', quality.toString(), '--not-recursive', heicPath],
    );

    if (result.exitCode == 0 && await File(jpgPath).exists()) {
      return jpgPath;
    }

    print(
        '[HEIC] Conversion failed (exit code ${result.exitCode}): ${result.stderr}');
    return null;
  }

  /// Converts HEIC to JPG with custom output path.
  static Future<bool> convertHeicToJpgAt(String heicPath, String outputJpgPath,
      {int quality = 95}) async {
    final tempResult = await convertHeicToJpg(heicPath, quality: quality);
    if (tempResult == null) return false;

    // If output path differs, move the file
    if (tempResult != outputJpgPath) {
      try {
        await File(tempResult).copy(outputJpgPath);
        await File(tempResult).delete();
      } catch (e) {
        print('[HEIC] Failed to move converted file: $e');
        return false;
      }
    }
    return true;
  }
}
