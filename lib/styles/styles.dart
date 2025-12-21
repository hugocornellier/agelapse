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
  static Color darkOverlay = const Color(0xFF232121).withOpacity(0.5);
  static const Color lightGrey = Color(0xffb4b0b0);
  static const Color lightBlue = Color(0xff66aacc);
  static const Color darkerLightBlue = Color(0xff3285af);
  static const Color evenDarkerLightBlue = Color(0xff206588);
  static const Color orange = Color(0xffc9a179);
  static const Color darkGrey = Color(0xff0F0F0F);
  static const Color lessDarkGrey = Color(0xff212121);
}
