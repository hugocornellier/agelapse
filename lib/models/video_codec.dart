import 'dart:io';

import '../utils/platform_utils.dart';

/// Video codec selection for timelapse output.
///
/// Stored in settings as the enum name string (e.g., 'h264', 'hevc',
/// 'prores422', 'prores422hq', 'prores4444', 'vp9').
enum VideoCodec {
  h264,
  hevc,
  prores422,
  prores422hq,
  prores4444,
  vp9;

  /// Parse from stored string, defaults to [h264] if invalid.
  static VideoCodec fromString(String value) {
    return VideoCodec.values.firstWhere(
      (codec) => codec.name == value.toLowerCase(),
      orElse: () => VideoCodec.h264,
    );
  }

  /// Human-readable display name for the settings UI.
  String get displayName {
    switch (this) {
      case VideoCodec.h264:
        return 'H.264';
      case VideoCodec.hevc:
        return 'HEVC (H.265)';
      case VideoCodec.prores422:
        return 'ProRes 422';
      case VideoCodec.prores422hq:
        return 'ProRes 422 HQ';
      case VideoCodec.prores4444:
        return 'ProRes 4444';
      case VideoCodec.vp9:
        return 'VP9';
    }
  }

  /// Short description for tooltip/info text.
  String get description {
    switch (this) {
      case VideoCodec.h264:
        return 'Maximum compatibility. Plays everywhere.';
      case VideoCodec.hevc:
        if (Platform.isWindows) {
          return 'Smaller files, ideal for 4K+. Playback may require HEVC Video Extensions on Windows. Slower to encode.';
        }
        return 'Smaller files, ideal for 4K+. Requires modern devices (2016+). Slower to encode.';
      case VideoCodec.prores422:
        return 'Professional editing codec. Import into Final Cut Pro, DaVinci Resolve, or Premiere. Large files, .mov container.';
      case VideoCodec.prores422hq:
        return 'Highest quality editing codec. Broadcast-grade. Very large files, .mov container.';
      case VideoCodec.prores4444:
        return 'Alpha-capable ProRes for transparent video.';
      case VideoCodec.vp9:
        return 'Alpha-capable VP9 for transparent video.';
    }
  }

  /// Output container extension (including the dot).
  String get containerExtension {
    switch (this) {
      case VideoCodec.h264:
      case VideoCodec.hevc:
        return '.mp4';
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
      case VideoCodec.prores4444:
        return '.mov';
      case VideoCodec.vp9:
        return '.webm';
    }
  }

  /// Pixel format string for FFmpeg -pix_fmt.
  String get pixelFormat {
    switch (this) {
      case VideoCodec.h264:
      case VideoCodec.hevc:
        return 'yuv420p';
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
        return 'yuv422p10le';
      case VideoCodec.prores4444:
        return 'yuva444p10le';
      case VideoCodec.vp9:
        return 'yuva420p';
    }
  }

  /// Pixel format for high-bit-depth sources.
  /// Returns 10-bit format when [highBitDepth] is true and the codec supports it.
  String pixelFormatForSource({bool highBitDepth = false}) {
    if (!highBitDepth) return pixelFormat;
    switch (this) {
      case VideoCodec.hevc:
        return 'yuv420p10le';
      case VideoCodec.vp9:
        // Non-alpha VP9 can do 10-bit; alpha stays 8-bit
        return supportsAlpha ? 'yuva420p' : 'yuv420p10le';
      case VideoCodec.h264:
        // 10-bit H.264 has terrible compatibility, stay 8-bit
        return 'yuv420p';
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
      case VideoCodec.prores4444:
        // ProRes is already 10-bit
        return pixelFormat;
    }
  }

  /// Whether this codec supports alpha channel.
  bool get supportsAlpha => this == prores4444 || this == vp9;

  /// Whether this codec uses bitrate-based rate control (vs quality-based ProRes).
  bool get usesBitrateControl {
    switch (this) {
      case VideoCodec.h264:
      case VideoCodec.hevc:
      case VideoCodec.vp9:
        return true;
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
      case VideoCodec.prores4444:
        return false;
    }
  }

  /// Whether movflags +faststart should be applied.
  bool get usesMovFlags => this == h264 || this == hevc;

  /// FFmpeg encoder string for macOS/iOS (VideoToolbox hardware acceleration).
  String get encoderApple {
    switch (this) {
      case VideoCodec.h264:
        return 'h264_videotoolbox -allow_sw 1';
      case VideoCodec.hevc:
        return 'hevc_videotoolbox -allow_sw 1';
      case VideoCodec.prores422:
        return 'prores_ks -profile:v standard';
      case VideoCodec.prores422hq:
        return 'prores_ks -profile:v hq';
      case VideoCodec.prores4444:
        return 'prores_ks -profile:v 4444 -vendor apl0 -alpha_bits 16';
      case VideoCodec.vp9:
        throw StateError('VP9 is not available on Apple platforms');
    }
  }

  /// FFmpeg encoder string for Windows/Linux (software encoding).
  ///
  /// Flatpak's FFmpeg runtime (org.freedesktop.Platform.ffmpeg-full) ships
  /// libopenh264 instead of libx264, and does not include libx265.
  String get encoderDesktop {
    switch (this) {
      case VideoCodec.h264:
        return isFlatpak ? 'libopenh264' : 'libx264';
      case VideoCodec.hevc:
        if (isFlatpak) {
          throw StateError('HEVC is not available in the Flatpak FFmpeg runtime');
        }
        return 'libx265';
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
      case VideoCodec.prores4444:
        throw StateError('$name is not available on Windows/Linux');
      case VideoCodec.vp9:
        return 'libvpx-vp9';
    }
  }

  /// FFmpeg encoder string for Android (FFmpegKit software encoding).
  String get encoderAndroid {
    switch (this) {
      case VideoCodec.h264:
        return 'libx264';
      case VideoCodec.hevc:
      case VideoCodec.prores422:
      case VideoCodec.prores422hq:
      case VideoCodec.prores4444:
        throw StateError('$name is not available on Android');
      case VideoCodec.vp9:
        return 'libvpx-vp9';
    }
  }

  /// Resolves the correct encoder string for the current platform.
  String get encoder {
    if (isApple) return encoderApple;
    if (Platform.isAndroid) return encoderAndroid;
    return encoderDesktop;
  }

  /// Codec tag for container metadata (e.g., -tag:v avc1).
  /// Returns empty string if no tag is needed.
  String get codecTag {
    switch (this) {
      case VideoCodec.h264:
        if (isApple) return '-tag:v avc1';
        return '';
      case VideoCodec.hevc:
        if (isApple) return '-tag:v hvc1';
        return '';
      default:
        return '';
    }
  }

  /// Returns the codecs available for the given transparency state.
  /// [isTransparentVideo] means the output video itself should have alpha.
  static List<VideoCodec> availableCodecs({required bool isTransparentVideo}) {
    if (isTransparentVideo) {
      if (isApple) return [prores4444];
      return [vp9];
    }

    if (Platform.isMacOS) {
      return [h264, hevc, prores422, prores422hq];
    }
    if (Platform.isAndroid) {
      return [h264];
    }
    // Flatpak FFmpeg lacks libx265, only offer H.264
    if (isFlatpak) return [h264];
    // iOS, Windows, Linux: H.264 + HEVC
    return [h264, hevc];
  }

  /// Returns the default codec for the current state.
  static VideoCodec defaultCodec({required bool isTransparentVideo}) {
    if (isTransparentVideo) {
      if (isApple) return prores4444;
      return vp9;
    }
    return h264;
  }
}
