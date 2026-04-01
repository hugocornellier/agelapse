import 'package:flutter/material.dart';
import '../styles/styles.dart';
import 'dialog_title_row.dart';

void showQuickGuideDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.settingsCardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: DialogTitleRow(
        icon: Icons.lightbulb_outline_rounded,
        title: 'Quick Guide',
        iconColor: AppColors.accent,
        iconBackgroundColor: AppColors.accent.withValues(alpha: 0.15),
      ),
      content: SingleChildScrollView(
        child: Text(
          message,
          style: TextStyle(
            color: AppColors.settingsTextSecondary,
            fontSize: AppTypography.md,
            height: 1.6,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Got it',
            style: TextStyle(
              color: AppColors.settingsAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
