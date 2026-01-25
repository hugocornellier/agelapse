import 'dart:io';

import 'package:flutter/material.dart';

import '../../styles/styles.dart';

/// Shared image options menu used by both gallery_page.dart and image_preview_navigator.dart.
/// Consolidates duplicate menu implementations.
class GalleryImageMenu {
  /// Shows the image options menu dialog.
  ///
  /// [context] - Build context for showing dialog
  /// [imageFile] - The image file being acted upon
  /// [onChangeDate] - Callback when "Change Date" is tapped
  /// [onStabDiffFace] - Callback when "Stabilize on Other Faces" is tapped
  /// [onRetryStab] - Callback when "Retry Stabilization" is tapped
  /// [onSetGuidePhoto] - Callback when "Set as Guide Photo" is tapped
  /// [onManualStab] - Callback when "Manual Stabilization" is tapped
  /// [onDelete] - Callback when "Delete Image" is tapped
  /// [useAppColors] - If true, uses AppColors styling (image_preview_navigator style)
  static Future<void> show({
    required BuildContext context,
    required File imageFile,
    required VoidCallback onChangeDate,
    required VoidCallback onStabDiffFace,
    required VoidCallback onRetryStab,
    required VoidCallback onSetGuidePhoto,
    required VoidCallback onManualStab,
    required VoidCallback onDelete,
    bool useAppColors = false,
  }) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: useAppColors
              ? AppColors.settingsCardBackground
              : AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(useAppColors ? 12 : 8.0),
          ),
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMenuItem(
                icon: Icons.calendar_today,
                title: 'Change Date',
                iconColor: AppColors.textPrimary,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onChangeDate();
                },
                useAppColors: useAppColors,
              ),
              _buildDivider(useAppColors),
              _buildMenuItem(
                icon: Icons.video_stable,
                title: 'Stabilize on Other Faces',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onStabDiffFace();
                },
                useAppColors: useAppColors,
              ),
              _buildDivider(useAppColors),
              _buildMenuItem(
                icon: Icons.refresh,
                title: 'Retry Stabilization',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onRetryStab();
                },
                useAppColors: useAppColors,
              ),
              _buildDivider(useAppColors),
              _buildMenuItem(
                icon: Icons.photo,
                title: 'Set as Guide Photo',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onSetGuidePhoto();
                },
                useAppColors: useAppColors,
              ),
              _buildDivider(useAppColors),
              _buildMenuItem(
                icon: Icons.handyman,
                title: 'Manual Stabilization',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onManualStab();
                },
                useAppColors: useAppColors,
              ),
              _buildDivider(useAppColors),
              _buildMenuItem(
                icon: Icons.delete,
                title: 'Delete Image',
                iconColor: AppColors.danger,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onDelete();
                },
                useAppColors: useAppColors,
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    bool useAppColors = false,
  }) {
    if (useAppColors) {
      return ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? AppColors.settingsTextSecondary,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
              fontSize: AppTypography.md, color: AppColors.settingsTextPrimary),
        ),
        onTap: onTap,
      );
    }

    return ListTile(
      leading: Icon(
        icon,
        color:
            iconColor?.withAlpha(204) ?? AppColors.textPrimary.withAlpha(150),
        size: 18.0,
      ),
      title: Text(
        title,
        style:
            TextStyle(fontSize: AppTypography.sm, color: AppColors.textPrimary),
      ),
      onTap: onTap,
    );
  }

  static Widget _buildDivider(bool useAppColors) {
    if (useAppColors) {
      return const Divider(height: 1, color: AppColors.settingsDivider);
    }
    return const Divider();
  }
}
