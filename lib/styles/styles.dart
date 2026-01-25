import 'package:flutter/material.dart';

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
  // Font size scale
  static const double xs = 11; // Extra small - captions, badges
  static const double sm = 12; // Small - secondary text, metadata
  static const double md = 14; // Medium - body text (default)
  static const double lg = 16; // Large - emphasized body, buttons
  static const double xl = 18; // Extra large - subheadings
  static const double xxl = 20; // 2XL - section headers
  static const double xxxl = 24; // 3XL - page titles
  static const double display = 28; // Display - hero text, large titles

  // Pre-built text styles
  static const TextStyle caption = TextStyle(
    fontSize: xs,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: sm,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: md,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: lg,
    color: AppColors.textPrimary,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: xl,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: xxl,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle headingLarge = TextStyle(
    fontSize: xxxl,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle displayText = TextStyle(
    fontSize: display,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );
}

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0F0F0F);
  static const Color backgroundDark = Color(0xFF0A0A0A);

  // Surfaces
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceElevated = Color(0xFF2A2A2A);

  // Semantic
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFFF9500);
  static const Color warningMuted = Color(0xFFC9A179);
  static const Color info = Color(0xFF2196F3);

  // Brand/Accent Ramp
  static const Color accentLight = Color(0xFF40C4FF);
  static const Color accent = Color(0xFF4A9ECC);
  static const Color accentDark = Color(0xFF3285AF);
  static const Color accentDarker = Color(0xFF206588);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);

  // Utility
  static const Color overlay = Color(0xFF000000);
  static const Color disabled = Color(0xFF5A5A5A);
  static const Color guideCorner = Color(0xFF924904);

  // Settings aliases (for backwards compatibility)
  static const Color settingsBackground = backgroundDark;
  static const Color settingsCardBackground = surface;
  static const Color settingsCardBorder = surfaceElevated;
  static const Color settingsDivider = surfaceElevated;
  static const Color settingsAccent = accent;
  static const Color settingsTextPrimary = textPrimary;
  static const Color settingsTextSecondary = textSecondary;
  static const Color settingsTextTertiary = textTertiary;
  static const Color settingsInputBackground = surface;

  // DEPRECATED - Keeping for backwards compatibility during migration
  // These will be removed after full migration
  static Color darkOverlay = overlay.withValues(alpha: 0.5);
  static const Color lightGrey = textSecondary;
  static const Color lightBlue = accentLight;
  static const Color darkerLightBlue = accentDark;
  static const Color evenDarkerLightBlue = accentDarker;
  static const Color orange = warningMuted;
  static const Color darkGrey = background;
  static const Color lessDarkGrey = surfaceElevated;
}
