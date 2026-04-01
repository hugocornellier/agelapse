import 'package:flutter/material.dart';
import '../styles/styles.dart';

class DialogTitleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBackgroundColor;

  const DialogTitleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.iconBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBackgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppTypography.xl,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
