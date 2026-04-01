import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../styles/styles.dart';
import '../../widgets/bottom_sheet_container.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/option_tile.dart';

/// Bottom sheet and option tile builders for gallery import/export operations.
class GalleryBottomSheets {
  /// Builds the container wrapper for option bottom sheets.
  /// Includes drag handle, title with close button, and content area.
  static Widget buildOptionsSheet(
    BuildContext context,
    String title,
    List<Widget> content,
  ) {
    return BottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BottomSheetHeader(
              title: title,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 20),
            ...content,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Builds an import option tile with icon, title, subtitle, and chevron.
  /// Used for navigation-style options (pick from gallery, pick files).
  static Widget buildImportOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return OptionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      useMouseRegion: false,
    );
  }

  /// Builds an export option toggle with icon, title, subtitle, and checkbox.
  /// Used for toggle-style options (export raw, export stabilized).
  static Widget buildExportOptionToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required ValueChanged<bool> onChanged,
  }) {
    return OptionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      isSelected: isSelected,
      onTap: () => onChanged(!isSelected),
      useMouseRegion: false,
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.settingsAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppColors.settingsAccent
                : AppColors.textPrimary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, color: AppColors.textPrimary, size: 16)
            : null,
      ),
    );
  }

  static Widget _buildStatusCard({
    required Widget icon,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    List<Widget>? additionalContent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: icon,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.9),
              fontSize: AppTypography.lg,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.5),
                fontSize: AppTypography.md,
              ),
            ),
          ],
          if (additionalContent != null) ...additionalContent,
        ],
      ),
    );
  }

  /// Builds export progress indicator with spinner and percentage.
  static Widget buildExportProgressIndicator(double progressPercent) {
    return _buildStatusCard(
      icon: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.settingsAccent),
        ),
      ),
      iconBgColor: AppColors.textPrimary.withValues(alpha: 0.08),
      title: 'Exporting...',
      subtitle: '$progressPercent%',
    );
  }

  /// Builds export success state with checkmark and message.
  /// Shows platform-specific save location information.
  static Widget buildExportSuccessState({VoidCallback? onShare}) {
    // Determine platform-specific message
    final String platformSubtitle;
    if (Platform.isAndroid) {
      platformSubtitle = 'Saved to Downloads/AgeLapse Exports';
    } else {
      platformSubtitle = 'Your photos have been exported to a ZIP file';
    }

    return _buildStatusCard(
      icon: Icon(
        Icons.check_circle_outline,
        color: AppColors.success,
        size: 32,
      ),
      iconBgColor: AppColors.success.withValues(alpha: 0.15),
      title: 'Export Complete!',
      additionalContent: [
        const SizedBox(height: 12),
        // Android: Show save location prominently with folder icon
        if (Platform.isAndroid) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.textPrimary.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: AppColors.textPrimary.withValues(alpha: 0.7),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  platformSubtitle,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.8),
                    fontSize: AppTypography.md,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            platformSubtitle,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.5),
              fontSize: AppTypography.sm,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        // Show share button on Android (optional action after save)
        if (Platform.isAndroid && onShare != null) ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onShare,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.textPrimary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.share_outlined,
                    color: AppColors.textPrimary.withValues(alpha: 0.8),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Share',
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.8),
                      fontSize: AppTypography.md,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Builds an expandable info banner for photo date detection.
  /// Collapsed by default, expands to show summary + docs link.
  static Widget buildPhotoDateInfoBanner({
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.info.withValues(alpha: 0.9),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'How are photo dates determined?',
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.9),
                      fontSize: AppTypography.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.textPrimary.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoBullet('EXIF metadata (camera date/time)'),
                    const SizedBox(height: 6),
                    _buildInfoBullet('Filename (e.g. 2023-01-15_photo.jpg)'),
                    const SizedBox(height: 6),
                    _buildInfoBullet('File modification date (last resort)'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse(
                          'https://agelapse.com/docs/user-guide/photo-dates',
                        );
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Read full guide',
                            style: TextStyle(
                              color: AppColors.info.withValues(alpha: 0.9),
                              fontSize: AppTypography.sm,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new,
                            color: AppColors.info.withValues(alpha: 0.9),
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildInfoBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.7),
              fontSize: AppTypography.sm,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
