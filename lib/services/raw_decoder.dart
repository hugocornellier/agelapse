import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'log_service.dart';

/// Decodes RAW/DNG image files to standard formats (PNG/TIFF).
///
/// Uses platform-specific strategies:
/// - macOS/iOS: Apple CIRAWFilter via MethodChannel
/// - Android/Windows/Linux: FFmpeg (bundled or system)
class RawDecoder {
  static const _rawExtensions = {
    '.dng',
    '.cr2',
    '.cr3',
    '.nef',
    '.arw',
    '.raf',
    '.orf',
    '.rw2',
  };

  static const _channel = MethodChannel('com.agelapse/raw_decoder');

  /// Check if a file extension is a RAW format.
  static bool isRawExtension(String ext) =>
      _rawExtensions.contains(ext.toLowerCase());

  /// Decode RAW → standard image file.
  ///
  /// Returns path to decoded file, or null on failure.
  /// When [sixteenBit] is true, outputs 16-bit PNG (Apple) or TIFF (FFmpeg).
  /// When false, outputs 8-bit PNG.
  static Future<String?> decodeToFile(
    String rawPath,
    String outputDir, {
    bool sixteenBit = false,
  }) async {
    final baseName = path.basenameWithoutExtension(rawPath);

    if (Platform.isMacOS || Platform.isIOS) {
      return _decodeApple(rawPath, outputDir, baseName, sixteenBit);
    }
    return _decodeFfmpeg(rawPath, outputDir, baseName, sixteenBit);
  }

  /// Apple platforms: use CIRAWFilter via MethodChannel.
  static Future<String?> _decodeApple(
    String rawPath,
    String outputDir,
    String baseName,
    bool sixteenBit,
  ) async {
    final ext = sixteenBit ? '.png' : '.png';
    final outputPath = path.join(outputDir, '$baseName$ext');
    try {
      final result = await _channel.invokeMethod<String>('decodeRaw', {
        'inputPath': rawPath,
        'outputPath': outputPath,
        'sixteenBit': sixteenBit,
      });
      if (result != null && await File(result).exists()) {
        return result;
      }
      LogService.instance
          .log('[RAW] Apple decode returned null or missing file');
      // Fall back to FFmpeg if native decode fails
      return _decodeFfmpeg(rawPath, outputDir, baseName, sixteenBit);
    } on MissingPluginException {
      LogService.instance
          .log('[RAW] MethodChannel not available, using FFmpeg');
      return _decodeFfmpeg(rawPath, outputDir, baseName, sixteenBit);
    } catch (e) {
      LogService.instance
          .log('[RAW] Apple decode error: $e, falling back to FFmpeg');
      return _decodeFfmpeg(rawPath, outputDir, baseName, sixteenBit);
    }
  }

  /// Non-Apple platforms: use FFmpeg to decode RAW.
  /// DNG (TIFF-based) decodes well; Bayer RAW formats have limited quality.
  static Future<String?> _decodeFfmpeg(
    String rawPath,
    String outputDir,
    String baseName,
    bool sixteenBit,
  ) async {
    final String outputPath;
    final List<String> args;

    if (sixteenBit) {
      outputPath = path.join(outputDir, '$baseName.tiff');
      args = ['-y', '-i', rawPath, '-pix_fmt', 'rgb48le', outputPath];
    } else {
      outputPath = path.join(outputDir, '$baseName.png');
      args = ['-y', '-i', rawPath, outputPath];
    }

    try {
      final ffmpegPath = await _resolveFfmpegPath();
      final result = await Process.run(ffmpegPath, args);
      if (result.exitCode == 0 && await File(outputPath).exists()) {
        LogService.instance.log('[RAW] FFmpeg decoded: $outputPath');
        return outputPath;
      }
      LogService.instance.log(
        '[RAW] FFmpeg decode failed (exit ${result.exitCode}): ${result.stderr}',
      );
      return null;
    } catch (e) {
      LogService.instance.log('[RAW] FFmpeg error: $e');
      return null;
    }
  }

  /// Resolve FFmpeg binary path for desktop platforms.
  static Future<String> _resolveFfmpegPath() async {
    if (Platform.isMacOS || Platform.isLinux) {
      // Check common locations
      for (final p in [
        '/usr/local/bin/ffmpeg',
        '/opt/homebrew/bin/ffmpeg',
        '/usr/bin/ffmpeg'
      ]) {
        if (await File(p).exists()) return p;
      }
      // Flatpak location
      const flatpakPath = '/app/lib/ffmpeg/bin/ffmpeg';
      if (await File(flatpakPath).exists()) return flatpakPath;
    }
    return 'ffmpeg'; // Fall back to PATH
  }
}
