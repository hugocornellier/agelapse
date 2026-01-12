import 'package:flutter/material.dart';

ButtonStyle overlayButtonRoundStyle() {
  return ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    backgroundColor: AppColors.darkOverlay,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.all(18),
  );
}

ButtonStyle takePhotoRoundStyle() {
  return ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    minimumSize: Size.zero,
    backgroundColor: AppColors.darkOverlay,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.all(3),
  );
}

class AppColors {
  static Color darkOverlay = const Color(0xFF232121).withValues(alpha: 0.5);
  static const Color lightGrey = Color(0xffb4b0b0);
  static const Color lightBlue = Color(0xff66aacc);
  static const Color darkerLightBlue = Color(0xff3285af);
  static const Color evenDarkerLightBlue = Color(0xff206588);
  static const Color orange = Color(0xffc9a179);
  static const Color darkGrey = Color(0xff0F0F0F);
  static const Color lessDarkGrey = Color(0xff212121);

  // Modern settings card colors
  static const Color settingsBackground = Color(0xff0A0A0A);
  static const Color settingsCardBackground = Color(0xff1A1A1A);
  static const Color settingsCardBorder = Color(0xff2A2A2A);
  static const Color settingsDivider = Color(0xff2A2A2A);
  static const Color settingsAccent = Color(0xff4A9ECC);
  static const Color settingsTextPrimary = Color(0xffFFFFFF);
  static const Color settingsTextSecondary = Color(0xff8E8E93);
  static const Color settingsTextTertiary = Color(0xff636366);
  static const Color settingsInputBackground = Color(0xff1A1A1A);
}
