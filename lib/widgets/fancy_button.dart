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
    // Use accent color for icon background, with theme-appropriate opacity
    final iconBgColor = AppColors.accent.withValues(alpha: 0.15);
    final iconColor = AppColors.accent;

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
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
            size: 22,
          ),
        ],
      ),
    );
  }
}
