import 'package:flutter/material.dart';
import '../styles/styles.dart';

Future<bool?> showUnsavedChangesDialog(
  BuildContext context, {
  Widget? additionalContent,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.save_outlined,
              color: AppColors.settingsAccent,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Unsaved Changes',
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: AppTypography.xl,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'You have unsaved changes. Do you want to save them before leaving?',
              style: TextStyle(
                color: AppColors.settingsTextSecondary,
                fontSize: AppTypography.md,
                height: 1.5,
              ),
            ),
            if (additionalContent != null) ...[
              const SizedBox(height: 16.0),
              additionalContent,
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              'Discard',
              style: TextStyle(
                color: AppColors.settingsTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text(
              'Save',
              style: TextStyle(
                color: AppColors.settingsAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
}
