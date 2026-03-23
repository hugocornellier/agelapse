/// Represents the video background mode.
///
/// When stabilized PNGs are transparent (alpha channel), the video can either
/// keep transparency (requiring alpha-capable codecs), composite onto a solid
/// color at compile time (allowing any codec), or use a blurred version of the
/// frame as the background.
class VideoBackground {
  /// Special value stored in DB meaning "keep transparent in video".
  static const String keepTransparentValue = 'TRANSPARENT';

  /// Special value stored in DB meaning "use blurred background".
  static const String blurredValue = 'BLURRED';

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

  /// Create a blurred video background.
  const VideoBackground.blurred()
      : keepTransparent = false,
        solidColorHex = null;

  /// Parse from stored DB value.
  /// 'TRANSPARENT' -> keepTransparent, 'BLURRED' -> blurred, otherwise hex color.
  factory VideoBackground.fromString(String value) {
    if (value.toUpperCase() == keepTransparentValue) {
      return const VideoBackground.transparent();
    }
    if (value.toUpperCase() == blurredValue) {
      return const VideoBackground.blurred();
    }
    return VideoBackground.solidColor(value);
  }

  /// Serialize for DB storage.
  String toDbValue() {
    if (keepTransparent) return keepTransparentValue;
    if (isBlurred) return blurredValue;
    return solidColorHex ?? '#000000';
  }

  /// Whether the background is a blurred version of the frame.
  bool get isBlurred => !keepTransparent && solidColorHex == null;

  /// Whether the background is a solid color.
  bool get isSolidColor => !keepTransparent && solidColorHex != null;

  /// Whether the video output needs an alpha-capable codec.
  bool get requiresAlphaCodec => keepTransparent;
}
