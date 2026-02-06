/// Represents the video background mode.
///
/// When stabilized PNGs are transparent (alpha channel), the video can either
/// keep transparency (requiring alpha-capable codecs) or composite onto a solid
/// color at compile time (allowing any codec).
class VideoBackground {
  /// Special value stored in DB meaning "keep transparent in video".
  static const String keepTransparentValue = 'TRANSPARENT';

  final bool keepTransparent;
  final String? solidColorHex;

  /// Create a transparent video background.
  const VideoBackground.transparent()
      : keepTransparent = true,
        solidColorHex = null;

  /// Create a solid color video background.
  VideoBackground.solidColor(String hexColor)
      : keepTransparent = false,
        solidColorHex = hexColor.toUpperCase();

  /// Parse from stored DB value.
  /// 'TRANSPARENT' -> keepTransparent, otherwise hex color.
  factory VideoBackground.fromString(String value) {
    if (value.toUpperCase() == keepTransparentValue) {
      return const VideoBackground.transparent();
    }
    return VideoBackground.solidColor(value);
  }

  /// Serialize for DB storage.
  String toDbValue() {
    if (keepTransparent) return keepTransparentValue;
    return solidColorHex ?? '#000000';
  }

  /// Whether the video output needs an alpha-capable codec.
  bool get requiresAlphaCodec => keepTransparent;
}
