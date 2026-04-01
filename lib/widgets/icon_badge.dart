import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A small icon wrapped in a rounded container — used throughout list tiles and
/// option rows.  Defaults: padding 10, size 22, textPrimary icon on a
/// textPrimary(alpha 0.08) background.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final double padding;
  final Color? iconColor;
  final Color? backgroundColor;

  const IconBadge({
    super.key,
    required this.icon,
    this.iconSize = 22,
    this.padding = 10,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AppColors.textPrimary;
    final bgColor =
        backgroundColor ?? effectiveIconColor.withValues(alpha: 0.08);
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: iconSize, color: effectiveIconColor),
    );
  }
}
