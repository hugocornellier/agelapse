import 'package:flutter/material.dart';
import 'app_colors_data.dart';

ButtonStyle overlayButtonRoundStyle() {
  return ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    backgroundColor: AppColors.overlay.withValues(alpha: 0.5),
    foregroundColor: AppColors.textPrimary,
    padding: const EdgeInsets.all(18),
  );
}

ButtonStyle takePhotoRoundStyle() {
  return ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    minimumSize: Size.zero,
    backgroundColor: AppColors.overlay.withValues(alpha: 0.5),
    foregroundColor: AppColors.textPrimary,
    padding: const EdgeInsets.all(3),
  );
}

/// Typography scale for consistent font sizes across the app.
///
/// Usage: `fontSize: AppTypography.md` or `style: AppTypography.bodyMedium`
class AppTypography {
  // Font size scale (these remain const)
  static const double xs = 11; // Extra small - captions, badges
  static const double sm = 12; // Small - secondary text, metadata
  static const double md = 14; // Medium - body text (default)
  static const double lg = 16; // Large - emphasized body, buttons
  static const double xl = 18; // Extra large - subheadings
  static const double xxl = 20; // 2XL - section headers
  static const double xxxl = 24; // 3XL - page titles
  static const double display = 28; // Display - hero text, large titles

  // Pre-built text styles - GETTERS for dynamic theme colors
  static TextStyle get caption => TextStyle(
        fontSize: xs,
        color: AppColors.textSecondary,
      );

  static TextStyle get bodySmall => TextStyle(
        fontSize: sm,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontSize: md,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyLarge => TextStyle(
        fontSize: lg,
        color: AppColors.textPrimary,
      );

  static TextStyle get headingSmall => TextStyle(
        fontSize: xl,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get headingMedium => TextStyle(
        fontSize: xxl,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get headingLarge => TextStyle(
        fontSize: xxxl,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.bold,
      );

  static TextStyle get displayText => TextStyle(
        fontSize: display,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.bold,
      );
}

/// Global accessor for current theme colors.
/// Synced via MaterialApp.builder - always reflects current theme.
///
/// IMPORTANT: All fields are GETTERS, not const/static final.
/// This ensures theme changes are reflected immediately.
///
/// Prefer [context.appColors] in widgets for subtree override support.
class AppColors {
  AppColors._();

  static AppColorsData _current = AppColorsData.dark();

  /// Called by MaterialApp.builder to sync theme colors
  static void syncFromContext(BuildContext context) {
    final ext = Theme.of(context).extension<AppColorsData>();
    if (ext != null) {
      _current = ext;
    }
  }

  // Core color getters - delegate to _current (no caching!)
  static Color get background => _current.background;
  static Color get backgroundDark => _current.backgroundDark;
  static Color get surface => _current.surface;
  static Color get surfaceElevated => _current.surfaceElevated;
  static Color get textPrimary => _current.textPrimary;
  static Color get textSecondary => _current.textSecondary;
  static Color get textTertiary => _current.textTertiary;
  static Color get danger => _current.danger;
  static Color get success => _current.success;
  static Color get warning => _current.warning;
  static Color get warningMuted => _current.warningMuted;
  static Color get info => _current.info;
  static Color get accentLight => _current.accentLight;
  static Color get accent => _current.accent;
  static Color get accentDark => _current.accentDark;
  static Color get accentDarker => _current.accentDarker;
  static Color get overlay => _current.overlay;
  static Color get disabled => _current.disabled;
  static Color get guideCorner => _current.guideCorner;
  static Color get galleryBackground => _current.galleryBackground;

  // Settings aliases (for backwards compatibility)
  static Color get settingsBackground => backgroundDark;
  static Color get settingsCardBackground => surface;
  static Color get settingsCardBorder => surfaceElevated;
  static Color get settingsDivider => surfaceElevated;
  static Color get settingsAccent => accent;
  static Color get settingsTextPrimary => textPrimary;
  static Color get settingsTextSecondary => textSecondary;
  static Color get settingsTextTertiary => textTertiary;
  static Color get settingsInputBackground => surface;

  // Computed colors
  static Color get darkOverlay => overlay.withValues(alpha: 0.5);

  // DEPRECATED aliases - remove after full migration
  static Color get lightGrey => textSecondary;
  static Color get lightBlue => accentLight;
  static Color get darkerLightBlue => accentDark;
  static Color get evenDarkerLightBlue => accentDarker;
  static Color get orange => warningMuted;
  static Color get darkGrey => background;
  static Color get lessDarkGrey => surfaceElevated;
}
