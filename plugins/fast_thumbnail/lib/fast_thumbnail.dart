import 'fast_thumbnail_platform_interface.dart';

class ThumbnailResult {
  final int originalWidth;
  final int originalHeight;

  const ThumbnailResult({
    required this.originalWidth,
    required this.originalHeight,
  });
}

class FastThumbnail {
  /// Generates a JPEG thumbnail at [outputPath] from the image at [inputPath].
  /// Returns a [ThumbnailResult] with the original image dimensions (after EXIF
  /// rotation is applied), or null on failure.
  static Future<ThumbnailResult?> generate({
    required String inputPath,
    required String outputPath,
    int maxWidth = 500,
    int quality = 90,
  }) {
    return FastThumbnailPlatform.instance.generate(
      inputPath: inputPath,
      outputPath: outputPath,
      maxWidth: maxWidth,
      quality: quality,
    );
  }
}
