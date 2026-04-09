import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fast_thumbnail.dart';
import 'fast_thumbnail_method_channel.dart';

abstract class FastThumbnailPlatform extends PlatformInterface {
  FastThumbnailPlatform() : super(token: _token);

  static final Object _token = Object();

  static FastThumbnailPlatform _instance = MethodChannelFastThumbnail();

  static FastThumbnailPlatform get instance => _instance;

  static set instance(FastThumbnailPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<ThumbnailResult?> generate({
    required String inputPath,
    required String outputPath,
    int maxWidth = 500,
    int quality = 90,
  }) {
    throw UnimplementedError('generate() has not been implemented.');
  }
}
