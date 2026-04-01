import 'package:flutter/material.dart';
import '../styles/styles.dart';
import '../widgets/desktop_page_scaffold.dart';

/// A square icon button used in desktop toolbar/app-bar actions.
///
/// Wraps MouseRegion + GestureDetector + Container + Icon with
/// app-consistent sizing, border, and cursor.
///
/// Shared across: manual_stab_page, set_eye_position_page.
class DesktopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  final bool isLoading;
  final Color? loadingColor;

  const DesktopIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.margin,
    this.isLoading = false,
    this.loadingColor,
  });

  @override
  Widget build(BuildContext context) {
    const size = DesktopPageScaffold.navButtonSize;
    const iconSize = DesktopPageScaffold.navIconSize;
    const radius = DesktopPageScaffold.navButtonRadius;

    final bgColor =
        backgroundColor ?? AppColors.settingsCardBorder.withValues(alpha: 0.5);
    final bColor = borderColor ?? AppColors.settingsCardBorder;
    final iColor = iconColor ?? AppColors.settingsTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          margin: margin ?? const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: bColor, width: 1),
          ),
          child: isLoading
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: loadingColor ?? iColor,
                  ),
                )
              : Icon(icon, color: iColor, size: iconSize),
        ),
      ),
    );
  }
}
