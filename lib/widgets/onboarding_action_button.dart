import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A full-width (or fractional-width) action button used on onboarding screens.
///
/// Shared across: projects_page, create_first_video_page,
/// set_up_notifications_page, took_first_photo_page, tips_page,
/// import_page, guide_mode_tutorial_page.
class OnboardingActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? textColor;
  final Color? backgroundColor;
  final double widthFactor;
  final double verticalPadding;
  final bool useRoundedCorners;

  const OnboardingActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.textColor,
    this.backgroundColor,
    this.widthFactor = 1.0,
    this.verticalPadding = 18.0,
    this.useRoundedCorners = true,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.accentDark;
    final fgColor = textColor ?? AppColors.textPrimary;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          minimumSize: const Size(double.infinity, 50),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: useRoundedCorners
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0))
              : null,
        ),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: AppTypography.lg,
            color: fgColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
