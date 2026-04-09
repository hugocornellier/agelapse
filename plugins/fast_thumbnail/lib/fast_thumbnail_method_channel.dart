import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fast_thumbnail.dart';
import 'fast_thumbnail_platform_interface.dart';

class MethodChannelFastThumbnail extends FastThumbnailPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('fast_thumbnail');

  @override
  Future<ThumbnailResult?> generate({
    required String inputPath,
    required String outputPath,
    int maxWidth = 500,
    int quality = 90,
  }) async {
    final result = await methodChannel.invokeMethod<Map>('generate', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'maxWidth': maxWidth,
      'quality': quality.clamp(1, 100),
    });
    if (result == null) return null;
    return ThumbnailResult(
      originalWidth: result['originalWidth'] as int,
      originalHeight: result['originalHeight'] as int,
    );
  }
}
