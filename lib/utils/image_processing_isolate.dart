import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Input parameters for isolated image processing.
/// All fields must be transferable across isolate boundaries.
class ImageProcessingInput {
  final Uint8List bytes;
  final String? rotation; // "Landscape Left", "Landscape Right", or null
  final bool applyMirroring;
  final String extension; // ".jpg", ".png", etc.
  final int thumbnailWidth;
  final int thumbnailQuality;

  const ImageProcessingInput({
    required this.bytes,
    this.rotation,
    this.applyMirroring = false,
    required this.extension,
    this.thumbnailWidth = 500,
    this.thumbnailQuality = 90,
  });
}

/// Output from isolated image processing.
/// Contains processed image bytes, thumbnail bytes, and metadata.
class ImageProcessingOutput {
  final bool success;
  final Uint8List? processedBytes;
  final Uint8List? thumbnailBytes;
  final int width;
  final int height;
  final String? error;

  const ImageProcessingOutput({
    required this.success,
    this.processedBytes,
    this.thumbnailBytes,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  const ImageProcessingOutput.failure(this.error)
      : success = false,
        processedBytes = null,
        thumbnailBytes = null,
        width = 0,
        height = 0;
}

/// Top-level function for compute() - MUST be top-level or static.
/// Performs all CPU-intensive OpenCV operations in an isolate.
///
/// Operations performed:
/// 1. Decode image bytes to cv.Mat
/// 2. Rotate if deviceOrientation specified
/// 3. Flip horizontally if mirroring enabled
/// 4. Encode processed image back to bytes
/// 5. Create and encode thumbnail
ImageProcessingOutput processImageIsolateEntry(ImageProcessingInput input) {
  cv.Mat? rawImage;
  cv.Mat? thumbnail;

  try {
    // 1. Decode image bytes
    debugPrint(
        '[ImageProc] Decoding ${input.bytes.length} bytes in isolate...');
    rawImage = cv.imdecode(input.bytes, cv.IMREAD_COLOR);
    if (rawImage.isEmpty) {
      rawImage.dispose();
      return const ImageProcessingOutput.failure('Failed to decode image');
    }

    // Track if we need to re-encode the full image
    bool needsReencode = false;

    // 2. Rotate if needed
    if (input.rotation != null) {
      cv.Mat rotated;
      if (input.rotation == "Landscape Left") {
        rotated = cv.rotate(rawImage, cv.ROTATE_90_CLOCKWISE);
        needsReencode = true;
      } else if (input.rotation == "Landscape Right") {
        rotated = cv.rotate(rawImage, cv.ROTATE_90_COUNTERCLOCKWISE);
        needsReencode = true;
      } else {
        rotated = rawImage;
      }
      if (rotated != rawImage) {
        rawImage.dispose();
        rawImage = rotated;
      }
    }

    // 3. Flip if mirroring enabled
    if (input.applyMirroring) {
      final flipped = cv.flip(rawImage, 1); // 1 = horizontal flip
      rawImage.dispose();
      rawImage = flipped;
      needsReencode = true;
    }

    // 4. Encode full image (only if modified)
    Uint8List? processedBytes;
    if (needsReencode) {
      if (input.extension.toLowerCase() == ".png") {
        final (success, encoded) = cv.imencode('.png', rawImage);
        if (!success) {
          return const ImageProcessingOutput.failure('Failed to encode PNG');
        }
        processedBytes = encoded;
      } else {
        // Default to JPEG for all other formats
        final (success, encoded) = cv.imencode('.jpg', rawImage);
        if (!success) {
          return const ImageProcessingOutput.failure('Failed to encode JPEG');
        }
        processedBytes = encoded;
      }
    }

    // 5. Create thumbnail
    final aspectRatio = rawImage.rows / rawImage.cols;
    final thumbHeight = (input.thumbnailWidth * aspectRatio).round();
    thumbnail = cv.resize(rawImage, (input.thumbnailWidth, thumbHeight));

    final (thumbSuccess, thumbBytes) = cv.imencode(
      '.jpg',
      thumbnail,
      params:
          cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, input.thumbnailQuality]),
    );

    final width = rawImage.cols;
    final height = rawImage.rows;

    // Clean up before returning
    rawImage.dispose();
    rawImage = null;
    thumbnail.dispose();
    thumbnail = null;

    if (!thumbSuccess) {
      return ImageProcessingOutput(
        success: true,
        processedBytes: processedBytes,
        thumbnailBytes: null,
        width: width,
        height: height,
        error: 'Thumbnail encoding failed',
      );
    }

    debugPrint(
        '[ImageProc] Done: ${width}x$height, thumb=${thumbBytes.length} bytes');

    return ImageProcessingOutput(
      success: true,
      processedBytes: processedBytes,
      thumbnailBytes: thumbBytes,
      width: width,
      height: height,
    );
  } catch (e) {
    return ImageProcessingOutput.failure('Processing error: $e');
  } finally {
    // Ensure cleanup on any exit path
    rawImage?.dispose();
    thumbnail?.dispose();
  }
}

/// Check if the current platform supports isolate-based image processing.
///
/// Desktop platforms (macOS, Windows, Linux) are known to work with
/// opencv_dart in isolates. Mobile platforms (iOS, Android) may have
/// issues with native library loading in isolates, so we default to
/// main thread processing for safety.
bool get supportsIsolateProcessing {
  if (kIsWeb) return false;

  // Desktop platforms - opencv_dart works in isolates
  // Mobile platforms - needs testing, disabled for now for safety
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Process image safely with automatic fallback.
///
/// On supported platforms, processes in an isolate to avoid UI blocking.
/// On unsupported platforms or if isolate fails, falls back to main thread.
Future<ImageProcessingOutput> processImageSafely(
    ImageProcessingInput input) async {
  if (!supportsIsolateProcessing) {
    // Process on main thread for unsupported platforms
    debugPrint(
        '[ImageProc] Using MAIN THREAD (platform not supported for isolate)');
    return processImageIsolateEntry(input);
  }

  try {
    // Process in isolate
    debugPrint('[ImageProc] Using ISOLATE for ${input.bytes.length} bytes');
    return await compute(processImageIsolateEntry, input);
  } catch (e) {
    // Isolate failed - fall back to main thread processing
    debugPrint('[ImageProc] Isolate FAILED, falling back to main thread: $e');
    return processImageIsolateEntry(input);
  }
}
