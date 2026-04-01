import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A styled text field with a rounded container and app-consistent decorations.
///
/// Shared across: project_select_sheet (rename popup), delete_project_dialog.
class StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final Color? borderColor;

  const StyledTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.autofocus = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? AppColors.textPrimary.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: AppTypography.lg,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.3),
            fontSize: AppTypography.lg,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: InputBorder.none,
        ),
        autofocus: autofocus,
      ),
    );
  }
}
