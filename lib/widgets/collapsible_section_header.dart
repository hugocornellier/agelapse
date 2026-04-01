import 'package:flutter/material.dart';
import '../styles/styles.dart';

class CollapsibleSectionHeader extends StatelessWidget {
  final String label;
  final bool isExpanded;
  final VoidCallback onTap;

  const CollapsibleSectionHeader({
    super.key,
    required this.label,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.settingsTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
