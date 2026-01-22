import 'package:flutter/material.dart';

/// A reusable confirmation dialog widget for destructive or significant actions.
///
/// Provides factory methods for common confirmation scenarios:
/// - [showReStabilization] - When settings change requires re-stabilizing photos
/// - [showRecompileVideo] - When settings change requires recompiling video only
class ConfirmActionDialog extends StatelessWidget {
  final String title;
  final String description;
  final IconData? warningIcon;
  final String? warningText;
  final IconData titleIcon;
  final String cancelText;
  final String confirmText;

  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.description,
    this.warningIcon,
    this.warningText,
    this.titleIcon = Icons.warning_amber_rounded,
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

  /// Shows a confirmation dialog for date changes that affect the video.
  ///
  /// [orderChanged] - true if the photo sequence will change
  /// [dateStampChanged] - true if only the date stamp text will change (no reorder)
  static Future<bool> showDateChangeRecompile(
    BuildContext context, {
    required bool orderChanged,
  }) async {
    final String description;
    final String warning;

    if (orderChanged) {
      description = 'Changing this date will reorder your photos.';
      warning =
          'Your video will be recompiled with the new photo sequence.\nYour photos will not be affected.';
    } else {
      description =
          'Changing this date will update the date stamp on this frame.';
      warning =
          'Your video will be recompiled with the new date.\nYour photos will not be affected.';
    }

    return await _show(
      context,
      title: 'Recompile Video?',
      description: description,
      warningIcon: Icons.movie_outlined,
      warningText: warning,
    );
  }

  /// Shows a confirmation dialog for photo deletion that will trigger video recompilation.
  ///
  /// [photoCount] - number of photos being deleted (1 for single, >1 for batch)
  /// Use this when remaining photos >= 2 (video can still be compiled).
  static Future<bool> showDeleteRecompile(
    BuildContext context, {
    required int photoCount,
  }) async {
    final bool isSingle = photoCount == 1;
    final String photoText = isSingle ? 'this photo' : '$photoCount photos';
    final String description =
        'Are you sure you want to delete $photoText? This cannot be undone.';

    return await _show(
      context,
      title: 'Delete ${isSingle ? 'Photo' : 'Photos'}?',
      description: description,
      warningIcon: Icons.movie_outlined,
      warningText:
          'Your video will be recompiled without the deleted ${isSingle ? 'photo' : 'photos'}.',
      titleIcon: Icons.delete_outline_rounded,
      confirmText: 'Delete',
    );
  }

  /// Shows a simple confirmation dialog for photo deletion without video warning.
  ///
  /// [photoCount] - number of photos being deleted (1 for single, >1 for batch)
  /// Use this when remaining photos < 2 (no video to recompile).
  static Future<bool> showDeleteSimple(
    BuildContext context, {
    required int photoCount,
  }) async {
    final bool isSingle = photoCount == 1;
    final String photoText = isSingle ? 'this photo' : '$photoCount photos';
    final String description =
        'Are you sure you want to delete $photoText? This cannot be undone.';

    return await _show(
      context,
      title: 'Delete ${isSingle ? 'Photo' : 'Photos'}?',
      description: description,
      titleIcon: Icons.delete_outline_rounded,
      confirmText: 'Delete',
    );
  }

  /// Internal method to show the dialog with the given parameters.
  static Future<bool> _show(
    BuildContext context, {
    required String title,
    required String description,
    IconData? warningIcon,
    String? warningText,
    IconData titleIcon = Icons.warning_amber_rounded,
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
              titleIcon: titleIcon,
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
            child: Icon(
              titleIcon,
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
          if (warningText != null && warningIcon != null) ...[
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
                      warningText!,
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
