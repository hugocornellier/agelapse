import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/log_service.dart';

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
      LogService.instance.log('[HEIC] Extracting bundled heicConverter.exe...');
      try {
        final bytes = await rootBundle.load(_winHeicConverterAssetPath);
        await File(exePath)
            .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        await File(markerPath).writeAsString(_currentVersion, flush: true);
        LogService.instance
            .log('[HEIC] heicConverter.exe extracted to: $exePath');
      } catch (e) {
        LogService.instance
            .log('[HEIC] ERROR extracting heicConverter.exe: $e');
        return '';
      }
    }

    _cachedExePath = exePath;
    return exePath;
  }

  /// Converts HEIC to JPG on Windows using bundled HeicConverter.exe.
  /// Outputs directly to targetDir, returns the output JPG path or null if failed.
  static Future<String?> _convertHeic(String heicPath, String targetDir,
      {int quality = 95}) async {
    if (!Platform.isWindows) return null;

    final exePath = await _ensureBundledHeicConverter();
    if (exePath.isEmpty) return null;

    // heicConverter names output based on input filename
    final outputName = '${path.basenameWithoutExtension(heicPath)}.jpg';
    final outputPath = path.join(targetDir, outputName);

    final result = await Process.run(
      exePath,
      [
        '--files',
        heicPath,
        '-t',
        targetDir,
        '-q',
        quality.toString(),
        '--not-recursive',
        '--skip-prompt'
      ],
    );

    if (result.exitCode == 0 && await File(outputPath).exists()) {
      return outputPath;
    }

    LogService.instance.log(
        '[HEIC] Conversion failed (exit code ${result.exitCode}): ${result.stderr}');
    return null;
  }

  /// Converts HEIC to JPG, outputting next to the original file.
  /// Returns the output JPG path, or null if conversion failed.
  static Future<String?> convertHeicToJpg(String heicPath,
      {int quality = 95}) async {
    return _convertHeic(heicPath, path.dirname(heicPath), quality: quality);
  }

  /// Converts HEIC to JPG at a specific output path.
  static Future<bool> convertHeicToJpgAt(String heicPath, String outputJpgPath,
      {int quality = 95}) async {
    final targetDir = path.dirname(outputJpgPath);
    final desiredName = path.basename(outputJpgPath);

    final convertedPath =
        await _convertHeic(heicPath, targetDir, quality: quality);
    if (convertedPath == null) return false;

    // Rename if the desired filename differs from what heicConverter produced
    if (path.basename(convertedPath) != desiredName) {
      try {
        await File(convertedPath).rename(outputJpgPath);
      } catch (e) {
        LogService.instance.log('[HEIC] Failed to rename converted file: $e');
        return false;
      }
    }
    return true;
  }
}
