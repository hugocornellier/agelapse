import 'package:flutter/material.dart';

/// A reusable confirmation dialog widget for destructive or significant actions.
///
/// Provides factory methods for common confirmation scenarios:
/// - [showReStabilization] - When settings change requires re-stabilizing photos
/// - [showRecompileVideo] - When settings change requires recompiling video only
class ConfirmActionDialog extends StatelessWidget {
  final String title;
  final String description;
  final IconData warningIcon;
  final String warningText;
  final String cancelText;
  final String confirmText;

  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.description,
    required this.warningIcon,
    required this.warningText,
    this.cancelText = 'Cancel',
    this.confirmText = 'Proceed Anyway',
  });

  // Color constants matching existing design
  static const _dangerColor = Color(0xFFDC2626);
  static const _dangerColorLight = Color(0x26DC2626);
  static const _dangerColorBorder = Color(0x4DDC2626);
  static const _cardBackground = Color(0xFF1C1C1E);
  static const _textPrimary = Color(0xFFF5F5F7);
  static const _textSecondary = Color(0xFF8E8E93);

  /// Shows a confirmation dialog for settings that require re-stabilization.
  ///
  /// Used when changing: resolution, orientation, aspect ratio, stabilization mode.
  static Future<bool> showReStabilization(
    BuildContext context,
    String settingName,
  ) async {
    return await _show(
      context,
      title: 'Are you sure?',
      description: 'You are about to change the $settingName.',
      warningIcon: Icons.refresh_rounded,
      warningText:
          'This will re-stabilize all photos.\nThis action cannot be undone.',
    );
  }

  /// Shows a confirmation dialog for settings that require video recompilation only.
  ///
  /// Used when changing: date stamp position, format, size, opacity.
  static Future<bool> showRecompileVideo(
    BuildContext context,
    String settingName,
  ) async {
    return await _show(
      context,
      title: 'Are you sure?',
      description: 'You are about to change the date stamp $settingName.',
      warningIcon: Icons.movie_outlined,
      warningText:
          'This will recompile your video with the new settings.\nYour photos will not be affected.',
    );
  }

  /// Internal method to show the dialog with the given parameters.
  static Future<bool> _show(
    BuildContext context, {
    required String title,
    required String description,
    required IconData warningIcon,
    required String warningText,
    String cancelText = 'Cancel',
    String confirmText = 'Proceed Anyway',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return ConfirmActionDialog(
              title: title,
              description: description,
              warningIcon: warningIcon,
              warningText: warningText,
              cancelText: cancelText,
              confirmText: confirmText,
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _dangerColorLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: _dangerColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _dangerColorLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _dangerColorBorder, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  warningIcon,
                  color: _dangerColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    warningText,
                    style: const TextStyle(
                      color: _dangerColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelText,
            style: const TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(true),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _dangerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
