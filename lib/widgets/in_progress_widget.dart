import 'package:flutter/material.dart';
import '../styles/styles.dart';

class InProgress extends StatelessWidget {
  final String message;
  final Function(int)? goToPage;

  const InProgress({super.key, required this.message, this.goToPage});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: goToPage != null
          ? () {
              // goToPage!(3);
            }
          : null,
      child: Container(
        width: double.infinity,
        color: message == "No storage space on device."
            ? AppColors.danger
            : AppColors.accentDarker,
        constraints: const BoxConstraints(maxHeight: 32.0),
        alignment: Alignment.center,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppTypography.sm,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
