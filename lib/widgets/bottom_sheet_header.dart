import 'package:flutter/material.dart';

import '../styles/styles.dart';

class BottomSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Color? titleColor;

  const BottomSheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: AppTypography.xl,
                fontWeight: FontWeight.w600,
                color: titleColor ?? AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.close,
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
