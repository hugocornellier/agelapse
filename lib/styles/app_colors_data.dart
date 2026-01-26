import 'package:flutter/material.dart';

/// Theme-independent colors for photo overlays, camera guides, and exports.
/// These remain constant regardless of app theme to ensure visibility
/// on any background (photos, camera preview, etc.).
class PhotoOverlayColors {
  PhotoOverlayColors._();

  /// White text for date stamps and watermarks on photos
  static const Color text = Color(0xFFFFFFFF);

  /// Shadow behind photo overlay text (black @ 54%)
  static const Color textShadow = Color(0x8A000000);

  /// Secondary shadow (black @ 40%)
  static const Color textShadowLight = Color(0x66000000);

  /// Tertiary shadow (black @ 25%)
  static const Color textShadowLighter = Color(0x40000000);

  /// Camera grid lines (white @ 50%)
  static const Color cameraGuide = Color(0x80FFFFFF);

  /// Ghost image overlay on camera (white @ 95%)
  static const Color ghostImage = Color(0xF2FFFFFF);

  /// Background for text containers on photos (black @ 50%)
  static const Color textBackground = Color(0x80000000);
}

/// ThemeExtension holding all color tokens for light and dark themes.
@immutable
class AppColorsData extends ThemeExtension<AppColorsData> {
  const AppColorsData({
    required this.background,
    required this.backgroundDark,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.danger,
    required this.success,
    required this.warning,
    required this.warningMuted,
    required this.info,
    required this.accentLight,
    required this.accent,
    required this.accentDark,
    required this.accentDarker,
    required this.overlay,
    required this.disabled,
    required this.guideCorner,
    required this.galleryBackground,
  });

  final Color background;
  final Color backgroundDark;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color danger;
  final Color success;
  final Color warning;
  final Color warningMuted;
  final Color info;
  final Color accentLight;
  final Color accent;
  final Color accentDark;
  final Color accentDarker;
  final Color overlay;
  final Color disabled;
  final Color guideCorner;

  /// Gallery background - dark in both themes for photo grids
  final Color galleryBackground;

  /// Light theme color palette
  factory AppColorsData.light() => const AppColorsData(
        background: Color(0xFFFFFFFF),
        backgroundDark: Color(0xFFF5F5F7),
        surface: Color(0xFFF2F2F7),
        surfaceElevated: Color(0xFFE5E5EA),
        textPrimary: Color(0xFF000000),
        textSecondary: Color(0xFF6B6B6B),
        textTertiary: Color(0xFF8E8E93),
        danger: Color(0xFFDC2626),
        success: Color(0xFF16A34A),
        warning: Color(0xFFEA580C),
        warningMuted: Color(0xFF92400E),
        info: Color(0xFF1976D2),
        accentLight: Color(0xFF0288D1),
        accent: Color(0xFF0277BD),
        accentDark: Color(0xFF01579B),
        accentDarker: Color(0xFF014377),
        overlay: Color(0xFF000000),
        disabled: Color(0xFF9E9E9E),
        guideCorner: Color(0xFFB45309),
        galleryBackground: Color(0xFF1A1A1A),
      );

  /// Dark theme color palette
  factory AppColorsData.dark() => const AppColorsData(
        background: Color(0xFF0F0F0F),
        backgroundDark: Color(0xFF0A0A0A),
        surface: Color(0xFF1A1A1A),
        surfaceElevated: Color(0xFF2A2A2A),
        textPrimary: Color(0xFFFFFFFF),
        textSecondary: Color(0xFF8E8E93),
        textTertiary: Color(0xFF636366),
        danger: Color(0xFFEF4444),
        success: Color(0xFF22C55E),
        warning: Color(0xFFFF9500),
        warningMuted: Color(0xFFC9A179),
        info: Color(0xFF2196F3),
        accentLight: Color(0xFF40C4FF),
        accent: Color(0xFF4A9ECC),
        accentDark: Color(0xFF3285AF),
        accentDarker: Color(0xFF206588),
        overlay: Color(0xFF000000),
        disabled: Color(0xFF5A5A5A),
        guideCorner: Color(0xFF924904),
        galleryBackground: Color(0xFF0A0A0A),
      );

  @override
  AppColorsData copyWith({
    Color? background,
    Color? backgroundDark,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? danger,
    Color? success,
    Color? warning,
    Color? warningMuted,
    Color? info,
    Color? accentLight,
    Color? accent,
    Color? accentDark,
    Color? accentDarker,
    Color? overlay,
    Color? disabled,
    Color? guideCorner,
    Color? galleryBackground,
  }) {
    return AppColorsData(
      background: background ?? this.background,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningMuted: warningMuted ?? this.warningMuted,
      info: info ?? this.info,
      accentLight: accentLight ?? this.accentLight,
      accent: accent ?? this.accent,
      accentDark: accentDark ?? this.accentDark,
      accentDarker: accentDarker ?? this.accentDarker,
      overlay: overlay ?? this.overlay,
      disabled: disabled ?? this.disabled,
      guideCorner: guideCorner ?? this.guideCorner,
      galleryBackground: galleryBackground ?? this.galleryBackground,
    );
  }

  @override
  AppColorsData lerp(AppColorsData? other, double t) {
    if (other == null) return this;
    return AppColorsData(
      background: Color.lerp(background, other.background, t)!,
      backgroundDark: Color.lerp(backgroundDark, other.backgroundDark, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningMuted: Color.lerp(warningMuted, other.warningMuted, t)!,
      info: Color.lerp(info, other.info, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      accentDarker: Color.lerp(accentDarker, other.accentDarker, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      guideCorner: Color.lerp(guideCorner, other.guideCorner, t)!,
      galleryBackground:
          Color.lerp(galleryBackground, other.galleryBackground, t)!,
    );
  }
}

/// Extension on BuildContext for convenient access to AppColorsData.
extension AppColorsContext on BuildContext {
  /// Access the current theme's AppColorsData.
  /// Prefer this over the static AppColors shim in widgets.
  AppColorsData get appColors => Theme.of(this).extension<AppColorsData>()!;
}
