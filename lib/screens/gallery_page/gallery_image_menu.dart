import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../services/database_helper.dart';
import '../../styles/styles.dart';
import '../../utils/capture_timezone.dart';
import '../../utils/utils.dart';

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
  /// [onImageInfo] - Callback when "Image Info" is tapped (optional)
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
    VoidCallback? onImageInfo,
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
              if (onImageInfo != null) ...[
                _buildDivider(useAppColors),
                _buildMenuItem(
                  icon: Icons.info_outline,
                  title: 'Image Info',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    onImageInfo();
                  },
                  useAppColors: useAppColors,
                ),
              ],
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
            fontSize: AppTypography.md,
            color: AppColors.settingsTextPrimary,
          ),
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
        style: TextStyle(
          fontSize: AppTypography.sm,
          color: AppColors.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }

  static Widget _buildDivider(bool useAppColors) {
    if (useAppColors) {
      return Divider(height: 1, color: AppColors.settingsDivider);
    }
    return const Divider();
  }

  /// Shows the Image Info dialog with raw and stabilized dimensions.
  ///
  /// [timestamp] - The photo timestamp (filename without extension)
  /// [projectId] - The project ID
  /// [rawPath] - Full path to the raw image (can be empty)
  /// [stabPath] - Full path to the stabilized image (can be empty)
  /// [isInspectionMode] - Whether inspection mode is active
  /// [isRaw] - Whether currently viewing raw
  /// [getDimensions] - Optional callback to get cached dimensions; falls back to file-based extraction
  static void showImageInfo({
    required BuildContext context,
    required String timestamp,
    required int projectId,
    String rawPath = '',
    String stabPath = '',
    bool isInspectionMode = false,
    bool isRaw = true,
    Future<Size> Function(String path)? getDimensions,
  }) {
    if (timestamp.isEmpty) return;

    final dimsFn = getDimensions ?? _extractDimensions;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<dynamic>>(
        future: Future.wait([
          DB.instance.getPhotoByTimestamp(timestamp, projectId),
          rawPath.isNotEmpty ? dimsFn(rawPath) : Future.value(const Size(0, 0)),
          stabPath.isNotEmpty
              ? dimsFn(stabPath)
              : Future.value(const Size(0, 0)),
        ]),
        builder: (context, snap) {
          final photoData = snap.data?[0] as Map<String, dynamic>?;
          final rawDims = snap.data?[1] as Size? ?? const Size(0, 0);
          final stabDims = snap.data?[2] as Size? ?? const Size(0, 0);

          final originalFilename =
              photoData?['originalFilename'] as String? ?? '';
          final fileExtension = photoData?['fileExtension'] as String? ?? '';
          final captureOffset = CaptureTimezone.extractOffset(photoData);
          final formattedDate = Utils.formatUnixTimestampPlatformAware(
            int.parse(timestamp),
            captureOffsetMinutes: captureOffset,
          );

          return Dialog(
            backgroundColor: AppColors.settingsBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppColors.settingsTextPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Image Info',
                          style: TextStyle(
                            fontSize: AppTypography.lg,
                            fontWeight: FontWeight.w600,
                            color: AppColors.settingsTextPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (isInspectionMode && !isRaw)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF4CAF50,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(
                                  0xFF4CAF50,
                                ).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Inspection Mode',
                              style: TextStyle(
                                color: const Color(0xFF4CAF50),
                                fontSize: AppTypography.sm,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _infoRow('Date', formattedDate),
                    if (originalFilename.isNotEmpty)
                      _infoRow(
                        'Original file',
                        '$originalFilename$fileExtension',
                      ),
                    const SizedBox(height: 16),
                    _infoSectionHeader('Raw'),
                    const SizedBox(height: 8),
                    _infoRow(
                      'Resolution',
                      rawDims.width > 0
                          ? '${rawDims.width.toInt()} × ${rawDims.height.toInt()}'
                          : 'Not available',
                    ),
                    if (rawPath.isNotEmpty)
                      _infoRow(
                        'Format',
                        fileExtension.isNotEmpty
                            ? fileExtension.toUpperCase().replaceFirst('.', '')
                            : path
                                .extension(rawPath)
                                .toUpperCase()
                                .replaceFirst('.', ''),
                      ),
                    const SizedBox(height: 16),
                    _infoSectionHeader('Stabilized'),
                    const SizedBox(height: 8),
                    _infoRow(
                      'Resolution',
                      stabDims.width > 0
                          ? '${stabDims.width.toInt()} × ${stabDims.height.toInt()}'
                          : stabPath.isEmpty
                              ? 'Not stabilized'
                              : 'Not available',
                    ),
                    if (stabPath.isNotEmpty)
                      _infoRow(
                        'Format',
                        path
                            .extension(stabPath)
                            .toUpperCase()
                            .replaceFirst('.', ''),
                      ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            color: AppColors.settingsTextPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<Size> _extractDimensions(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return const Size(0, 0);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return const Size(0, 0);
    }
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.settingsTextSecondary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.settingsTextPrimary,
            fontSize: AppTypography.md,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: AppColors.settingsCardBorder, height: 1),
      ],
    );
  }
}
