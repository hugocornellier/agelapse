import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// An icon + uppercase title row used to label settings/info sections.
///
/// Shared across: settings_sheet.dart, info_page.dart, project_page.dart.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? color;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.settingsTextSecondary;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: effectiveColor),
            const SizedBox(width: 8),
          ],
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: effectiveColor,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
