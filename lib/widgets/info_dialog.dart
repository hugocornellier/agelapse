import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// Shows a standardized styled info dialog with the given [content].
///
/// This helper ensures consistent dialog styling across the app.
///
/// [title] - Optional title text displayed below the icon
/// [icon] - Optional icon to display (defaults to info_outline_rounded)
/// [iconColor] - Optional icon/title color (defaults to settingsAccent)
/// [primaryActionLabel] - Optional label for a prominent primary action button
/// [onPrimaryAction] - Callback when primary action is tapped (dialog auto-closes)
/// [dismissLabel] - Label for the dismiss button (defaults to "Got it", or "Close" if primary action exists)
void showStyledInfoDialog(
  BuildContext context,
  String content, {
  String? title,
  IconData? icon,
  Color? iconColor,
  String? primaryActionLabel,
  VoidCallback? onPrimaryAction,
  String? dismissLabel,
}) {
  final displayIcon = icon ?? Icons.info_outline_rounded;
  final displayColor = iconColor ?? AppColors.settingsAccent;
  final hasPrimaryAction =
      primaryActionLabel != null && onPrimaryAction != null;
  final effectiveDismissLabel =
      dismissLabel ?? (hasPrimaryAction ? "Close" : "Got it");

  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: displayColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    displayIcon,
                    color: displayColor,
                    size: 24,
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: displayColor,
                      fontSize: AppTypography.lg,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                content,
                style: const TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.md,
                  height: 1.5,
                ),
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 20),
              if (hasPrimaryAction) ...[
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onPrimaryAction();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: displayColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      primaryActionLabel,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppTypography.lg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: hasPrimaryAction
                        ? Colors.transparent
                        : AppColors.textPrimary.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    effectiveDismissLabel,
                    style: TextStyle(
                      color: hasPrimaryAction
                          ? AppColors.textPrimary.withValues(alpha: 0.5)
                          : AppColors.textPrimary,
                      fontSize: AppTypography.md,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
