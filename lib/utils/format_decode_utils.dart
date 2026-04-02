import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:heic_native/heic_native.dart';
import 'package:path/path.dart' as path;

import '../services/log_service.dart';
import '../services/raw_decoder.dart';
import 'gallery_utils.dart';

/// Centralized utility for decoding HEIC/AVIF/RAW bytes into cv-compatible
/// bytes that OpenCV's `cv.imdecode` can process.
class FormatDecodeUtils {
  static final Set<String> cvNativeExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.webp',
    '.gif',
    // TIFF and JP2 cause native crashes in cv.imdecode on Apple platforms
    // (opencv_dart's decoders segfault on macOS/iOS).
    // On non-Apple platforms, OpenCV handles these natively.
    if (!Platform.isMacOS && !Platform.isIOS) ...['.tif', '.tiff', '.jp2'],
  };

  /// Returns true if the given extension is NOT natively decodable by OpenCV
  /// and therefore needs conversion before passing to `cv.imdecode`.
  static bool needsConversion(String extension) {
    return !cvNativeExtensions.contains(extension.toLowerCase());
  }

  /// Load bytes that are guaranteed to be decodable by `cv.imdecode`.
  ///
  /// For native formats (JPG, PNG, BMP, WEBP, GIF, and TIFF/JP2 on
  /// non-Apple platforms), returns the raw file bytes unchanged.
  /// For non-native formats (HEIC, AVIF, RAW, TIFF/JP2 on Apple), performs
  /// one lossless conversion and returns the converted bytes.
  ///
  /// Returns null if the file cannot be read or conversion fails.
  static Future<Uint8List?> loadCvCompatibleBytes(String filePath) async {
    final ext = path.extension(filePath).toLowerCase();

    if (!needsConversion(ext)) {
      try {
        return await File(filePath).readAsBytes();
      } catch (e) {
        LogService.instance.log(
          '[FormatDecode] Failed to read native file $filePath: $e',
        );
        return null;
      }
    }

    final tempDir = path.dirname(filePath);
    return decodeToCvCompatibleBytes(filePath, ext, tempDir);
  }

  /// Decode a non-native format file to cv-compatible (PNG/JPG) bytes.
  ///
  /// Performs a lossless conversion where possible (see format matrix in plan).
  /// Creates a temp file, reads it, then deletes the temp file.
  /// Returns null on failure.
  static Future<Uint8List?> decodeToCvCompatibleBytes(
    String inputPath,
    String extension,
    String tempDir,
  ) async {
    final ext = extension.toLowerCase();

    if (ext == '.heic' || ext == '.heif') {
      return _decodeHeic(inputPath, tempDir);
    } else if (ext == '.avif') {
      return _decodeAvif(inputPath, tempDir);
    } else if (ext == '.tif' || ext == '.tiff') {
      return _decodeTiff(inputPath, tempDir);
    } else if (ext == '.jp2') {
      return _decodeJp2(inputPath, tempDir);
    } else if (RawDecoder.isRawExtension(ext)) {
      return _decodeRaw(inputPath, tempDir);
    }

    LogService.instance.log(
      '[FormatDecode] Unsupported extension for conversion: $ext',
    );
    return null;
  }

  /// Decode HEIC/HEIF to PNG bytes (lossless) via [HeicNative] on all platforms.
  static Future<Uint8List?> _decodeHeic(
    String inputPath,
    String tempDir,
  ) async {
    try {
      return await HeicNative.convertToBytes(inputPath,
          preserveMetadata: false);
    } catch (e) {
      LogService.instance.log('[FormatDecode] HEIC decode error: $e');
      return null;
    }
  }

  /// Decode TIFF to PNG bytes on Apple platforms where cv.imdecode crashes.
  ///
  /// - macOS: `sips` command
  /// - iOS: `sips` is unavailable; uses Flutter's image decoder via [GalleryUtils]
  static Future<Uint8List?> _decodeTiff(
    String inputPath,
    String tempDir,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPngPath = path.join(tempDir, '_fmt_decode_$timestamp.png');

    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sips', [
          '-s',
          'format',
          'png',
          inputPath,
          '--out',
          tempPngPath,
        ]);
        if (result.exitCode != 0 || !await File(tempPngPath).exists()) {
          LogService.instance.log(
            '[FormatDecode] sips TIFF conversion failed '
            '(exit ${result.exitCode})',
          );
          return null;
        }
      } else {
        // iOS: use Flutter's image codec which handles TIFF natively
        final result = await _decodeWithFlutterCodec(
          await File(inputPath).readAsBytes(),
        );
        if (result == null) {
          LogService.instance.log(
            '[FormatDecode] Flutter codec TIFF→PNG returned null',
          );
        }
        return result;
      }

      return _readAndCleanup(tempPngPath);
    } catch (e) {
      LogService.instance.log('[FormatDecode] TIFF decode error: $e');
      _tryDelete(tempPngPath);
      return null;
    }
  }

  /// Decode JPEG 2000 to PNG bytes on Apple platforms where cv.imdecode crashes.
  ///
  /// Same approach as TIFF — sips on macOS, Flutter codec on iOS.
  static Future<Uint8List?> _decodeJp2(
    String inputPath,
    String tempDir,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPngPath = path.join(tempDir, '_fmt_decode_$timestamp.png');

    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sips', [
          '-s',
          'format',
          'png',
          inputPath,
          '--out',
          tempPngPath,
        ]);
        if (result.exitCode != 0 || !await File(tempPngPath).exists()) {
          LogService.instance.log(
            '[FormatDecode] sips JP2 conversion failed '
            '(exit ${result.exitCode})',
          );
          return null;
        }
      } else {
        // iOS: use Flutter's image codec which handles JP2
        final result = await _decodeWithFlutterCodec(
          await File(inputPath).readAsBytes(),
        );
        if (result == null) {
          LogService.instance.log(
            '[FormatDecode] Flutter codec JP2→PNG returned null',
          );
        }
        return result;
      }

      return _readAndCleanup(tempPngPath);
    } catch (e) {
      LogService.instance.log('[FormatDecode] JP2 decode error: $e');
      _tryDelete(tempPngPath);
      return null;
    }
  }

  /// Decodes [bytes] to PNG via Flutter's image codec.
  /// Used on iOS for formats (TIFF, JP2) that the codec handles natively.
  static Future<Uint8List?> _decodeWithFlutterCodec(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      codec.dispose();
      frame.image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Decode AVIF to PNG bytes using [GalleryUtils.convertAvifToPng].
  static Future<Uint8List?> _decodeAvif(
    String inputPath,
    String tempDir,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPngPath = path.join(tempDir, '_fmt_decode_$timestamp.png');

    try {
      final success = await GalleryUtils.convertAvifToPng(
        inputPath,
        tempPngPath,
      );
      if (!success) {
        LogService.instance.log('[FormatDecode] AVIF conversion failed');
        return null;
      }

      return _readAndCleanup(tempPngPath);
    } catch (e) {
      LogService.instance.log('[FormatDecode] AVIF decode error: $e');
      _tryDelete(tempPngPath);
      return null;
    }
  }

  /// Decode RAW/DNG to PNG/TIFF bytes using [RawDecoder.decodeToFile].
  static Future<Uint8List?> _decodeRaw(
    String inputPath,
    String tempDir,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // RawDecoder picks the output filename based on the input basename,
    // so we copy the input to a uniquely-named temp file first to avoid
    // collisions.
    final uniqueBaseName = '_fmt_decode_$timestamp';
    final inputExt = path.extension(inputPath);
    final tempInputPath = path.join(tempDir, '$uniqueBaseName$inputExt');

    try {
      // Copy input to temp location with unique name so RawDecoder
      // produces a uniquely-named output.
      await File(inputPath).copy(tempInputPath);

      final decodedPath = await RawDecoder.decodeToFile(
        tempInputPath,
        tempDir,
      );

      // Clean up the temp copy of the input.
      _tryDelete(tempInputPath);

      if (decodedPath == null || !await File(decodedPath).exists()) {
        LogService.instance.log('[FormatDecode] RAW decode produced no output');
        return null;
      }

      return _readAndCleanup(decodedPath);
    } catch (e) {
      LogService.instance.log('[FormatDecode] RAW decode error: $e');
      _tryDelete(tempInputPath);
      return null;
    }
  }

  /// Read bytes from [filePath], then delete the file.
  static Future<Uint8List?> _readAndCleanup(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      _tryDelete(filePath);
      return bytes;
    } catch (e) {
      LogService.instance.log('[FormatDecode] Read/cleanup error: $e');
      _tryDelete(filePath);
      return null;
    }
  }

  /// Best-effort deletion of a temp file. Failures are logged but not thrown.
  static void _tryDelete(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      LogService.instance.log(
        '[FormatDecode] Failed to delete temp file $filePath: $e',
      );
    }
  }
}
