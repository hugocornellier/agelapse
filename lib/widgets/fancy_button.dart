import 'package:flutter/material.dart';
import '../styles/styles.dart';

class FancyButton {
  static Widget buildElevatedButton(
    BuildContext context, {
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    Color? backgroundColor,
  }) {
    final bgColor = backgroundColor ?? AppColors.surfaceElevated;
    final luminance = bgColor.computeLuminance();
    final onDarkBg = luminance < 0.3;
    final textColor = onDarkBg ? Colors.white : AppColors.textPrimary;
    final iconBgColor = onDarkBg
        ? Colors.white.withValues(alpha: 0.15)
        : AppColors.accent.withValues(alpha: 0.15);
    final iconColor = onDarkBg ? Colors.white : AppColors.accent;
    final chevronColor =
        onDarkBg ? Colors.white.withValues(alpha: 0.6) : AppColors.textTertiary;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(color: color, width: 1),
        ),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTypography.lg,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: chevronColor, size: 22),
        ],
      ),
    );
  }
}
