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
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.surfaceElevated,
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32.0),
          side: BorderSide(color: color, width: 0.5),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.overlay.withValues(alpha: 0.45),
            child: Icon(icon, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: AppTypography.lg, color: AppColors.textPrimary),
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: AppColors.textPrimary),
        ],
      ),
    );
  }
}
