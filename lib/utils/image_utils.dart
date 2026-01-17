import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Image processing utilities using opencv_dart for fast native operations.
class ImageUtils {
  /// Decode image bytes to cv.Mat
  static cv.Mat decode(Uint8List bytes) {
    return cv.imdecode(bytes, cv.IMREAD_COLOR);
  }

  /// Decode image bytes to cv.Mat with alpha channel (for PNG with transparency)
  static cv.Mat decodeWithAlpha(Uint8List bytes) {
    return cv.imdecode(bytes, cv.IMREAD_UNCHANGED);
  }

  /// Encode cv.Mat to JPEG bytes
  static Uint8List? encodeJpg(cv.Mat mat, {int quality = 90}) {
    final (success, bytes) = cv.imencode(
      '.jpg',
      mat,
      params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]),
    );
    return success ? bytes : null;
  }

  /// Encode cv.Mat to PNG bytes
  static Uint8List? encodePng(cv.Mat mat) {
    final (success, bytes) = cv.imencode('.png', mat);
    return success ? bytes : null;
  }

  /// Resize image maintaining aspect ratio by width
  static cv.Mat resize(cv.Mat src, {required int width}) {
    final aspectRatio = src.rows / src.cols;
    final height = (width * aspectRatio).round();
    return cv.resize(src, (width, height), interpolation: cv.INTER_CUBIC);
  }

  /// Resize image to exact dimensions
  static cv.Mat resizeExact(
    cv.Mat src, {
    required int width,
    required int height,
  }) {
    return cv.resize(src, (width, height), interpolation: cv.INTER_CUBIC);
  }

  /// Rotate 90 degrees clockwise
  static cv.Mat rotateClockwise(cv.Mat src) {
    return cv.rotate(src, cv.ROTATE_90_CLOCKWISE);
  }

  /// Rotate 90 degrees counter-clockwise
  static cv.Mat rotateCounterClockwise(cv.Mat src) {
    return cv.rotate(src, cv.ROTATE_90_COUNTERCLOCKWISE);
  }

  /// Flip horizontally (mirror)
  static cv.Mat flipHorizontal(cv.Mat src) {
    return cv.flip(src, 1); // 1 = horizontal flip
  }

  /// Flip vertically
  static cv.Mat flipVertical(cv.Mat src) {
    return cv.flip(src, 0); // 0 = vertical flip
  }

  /// Create a black background image of the same size and composite the source on top
  static cv.Mat compositeOnBlackBackground(cv.Mat src) {
    // Create black background with same dimensions
    final bg = cv.Mat.zeros(src.rows, src.cols, cv.MatType.CV_8UC3);

    // If source has alpha channel, we need to handle transparency
    if (src.channels == 4) {
      // Split channels
      final channels = cv.split(src);
      final bgr = cv.merge(
        cv.VecMat.fromList([channels[0], channels[1], channels[2]]),
      );
      final alpha = channels[3];

      // Create mask from alpha channel
      final mask = alpha;

      // Copy using mask
      bgr.copyTo(bg, mask: mask);

      // Cleanup
      for (final ch in channels) {
        ch.dispose();
      }
      bgr.dispose();

      return bg;
    } else {
      // No alpha, just copy directly
      src.copyTo(bg);
      return bg;
    }
  }

  /// Create thumbnail (500px width by default, JPEG output)
  static Uint8List? createThumbnail(
    Uint8List imageBytes, {
    int width = 500,
    int quality = 90,
  }) {
    final mat = decode(imageBytes);
    if (mat.isEmpty) {
      mat.dispose();
      return null;
    }

    final resized = resize(mat, width: width);
    final result = encodeJpg(resized, quality: quality);

    mat.dispose();
    resized.dispose();

    return result;
  }

  /// Create thumbnail from PNG with black background composite (for stabilized images)
  static Uint8List? createThumbnailFromPng(
    Uint8List pngBytes, {
    int width = 500,
    int quality = 90,
  }) {
    final mat = decodeWithAlpha(pngBytes);
    if (mat.isEmpty) {
      mat.dispose();
      return null;
    }

    // Composite on black background if has alpha
    final composited =
        mat.channels == 4 ? compositeOnBlackBackground(mat) : mat;
    final resized = resize(composited, width: width);
    final result = encodeJpg(resized, quality: quality);

    if (composited != mat) {
      composited.dispose();
    }
    mat.dispose();
    resized.dispose();

    return result;
  }

  /// Composite PNG bytes on black background and return PNG bytes
  static Uint8List? compositeBlackPng(Uint8List pngBytes) {
    final mat = decodeWithAlpha(pngBytes);
    if (mat.isEmpty) {
      mat.dispose();
      return null;
    }

    final composited = compositeOnBlackBackground(mat);
    final result = encodePng(composited);

    mat.dispose();
    composited.dispose();

    return result;
  }

  /// Get image dimensions from bytes
  static (int width, int height)? getImageDimensions(Uint8List bytes) {
    final mat = decode(bytes);
    if (mat.isEmpty) {
      mat.dispose();
      return null;
    }
    final dims = (mat.cols, mat.rows);
    mat.dispose();
    return dims;
  }

  /// Validate an image file in an isolate (non-blocking)
  /// Returns true if the image can be decoded successfully
  static Future<bool> validateImageInIsolate(String filePath) async {
    return await compute(_validateImageFromPath, filePath);
  }

  /// Validate image bytes in an isolate (non-blocking)
  /// Returns true if the image can be decoded successfully
  static Future<bool> validateImageBytesInIsolate(Uint8List bytes) async {
    return await compute(_validateImageFromBytes, bytes);
  }

  static bool _validateImageFromPath(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;
      final bytes = file.readAsBytesSync();
      return _validateImageFromBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  static bool _validateImageFromBytes(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      final valid = !mat.isEmpty;
      mat.dispose();
      return valid;
    } catch (_) {
      return false;
    }
  }

  /// Convert image bytes to PNG in an isolate (non-blocking)
  /// Useful for AVIF/HEIC to PNG conversion
  static Future<Uint8List?> convertToPngInIsolate(Uint8List bytes) async {
    return await compute(_convertToPng, bytes);
  }

  static Uint8List? _convertToPng(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_UNCHANGED);
      if (mat.isEmpty) {
        mat.dispose();
        return null;
      }
      final result = encodePng(mat);
      mat.dispose();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Get image dimensions in an isolate (non-blocking)
  /// Returns (width, height) or null if decoding fails
  static Future<(int, int)?> getImageDimensionsInIsolate(
    Uint8List bytes,
  ) async {
    return await compute(_getImageDimensions, bytes);
  }

  static (int, int)? _getImageDimensions(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) {
        mat.dispose();
        return null;
      }
      final dims = (mat.cols, mat.rows);
      mat.dispose();
      return dims;
    } catch (_) {
      return null;
    }
  }
}
