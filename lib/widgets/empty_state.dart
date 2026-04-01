import 'package:flutter/material.dart';
import '../styles/styles.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: AppColors.textPrimary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: AppTypography.sm,
                color: AppColors.textPrimary.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
