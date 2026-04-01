import 'package:flutter/material.dart';
import '../styles/styles.dart';
import 'icon_badge.dart';

/// A tappable option tile with icon badge, title, subtitle, and trailing widget.
///
/// Shared across: gallery_bottom_sheets, project_select_sheet.
///
/// - [isDestructive]: Applies danger-red styling to icon/text (project_select_sheet style).
/// - [isSelected]: Applies accent highlight styling (gallery_bottom_sheets style).
/// - [trailing]: Optional trailing widget. Defaults to a chevron if null.
/// - [useMouseRegion]: Wrap in MouseRegion for desktop cursor. Defaults to true.
class OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isSelected;
  final Widget? trailing;
  final bool useMouseRegion;

  const OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.isSelected = false,
    this.trailing,
    this.useMouseRegion = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Color iconBg;
    final Color titleColor;
    final Color subtitleColor;
    final Color borderColor;
    final Color bgColor;

    if (isDestructive) {
      iconColor = AppColors.danger;
      iconBg = AppColors.danger.withValues(alpha: 0.15);
      titleColor = AppColors.danger;
      subtitleColor = AppColors.danger.withValues(alpha: 0.6);
      borderColor = AppColors.danger.withValues(alpha: 0.2);
      bgColor = AppColors.textPrimary.withValues(alpha: 0.05);
    } else if (isSelected) {
      iconColor = AppColors.settingsAccent;
      iconBg = AppColors.settingsAccent.withValues(alpha: 0.2);
      titleColor = AppColors.textPrimary;
      subtitleColor = AppColors.textPrimary.withValues(alpha: 0.5);
      borderColor = AppColors.settingsAccent.withValues(alpha: 0.5);
      bgColor = AppColors.textPrimary.withValues(alpha: 0.08);
    } else {
      iconColor = AppColors.textPrimary;
      iconBg = AppColors.textPrimary.withValues(alpha: 0.08);
      titleColor = AppColors.textPrimary;
      subtitleColor = AppColors.textPrimary.withValues(alpha: 0.5);
      borderColor = AppColors.textPrimary.withValues(alpha: 0.08);
      bgColor = AppColors.textPrimary.withValues(alpha: 0.05);
    }

    final trailingWidget = trailing ??
        Icon(
          Icons.chevron_right,
          color: titleColor.withValues(alpha: 0.3),
          size: 20,
        );

    final tile = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            IconBadge(
              icon: icon,
              iconSize: 20,
              iconColor: iconColor,
              backgroundColor: iconBg,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: AppTypography.lg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: AppTypography.sm,
                    ),
                  ),
                ],
              ),
            ),
            trailingWidget,
          ],
        ),
      ),
    );

    if (!useMouseRegion) return tile;
    return MouseRegion(cursor: SystemMouseCursors.click, child: tile);
  }
}
