import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A cancel + action button row used in bottom-sheet dialogs.
///
/// Shared across: project_select_sheet (rename popup), delete_project_dialog.
///
/// - [cancelLabel]: Label for the cancel button. Defaults to 'Cancel'.
/// - [actionLabel]: Label for the action button.
/// - [actionColor]: Background color of the action button.
/// - [actionTextColor]: Text color of the action button. Defaults to [AppColors.textPrimary].
/// - [onCancel]: Called when Cancel is tapped.
/// - [onAction]: Called when the action button is tapped (null = disabled).
/// - [useMouseRegion]: Wrap buttons in MouseRegion for desktop cursor. Defaults to true.
/// - [isAnimated]: Use AnimatedContainer for the action button (e.g., for enabling/disabling).
/// - [actionEnabled]: Whether the action button appears fully enabled (used with isAnimated).
class DialogButtonRow extends StatelessWidget {
  final String cancelLabel;
  final String actionLabel;
  final Color actionColor;
  final Color? actionTextColor;
  final VoidCallback? onCancel;
  final VoidCallback? onAction;
  final bool useMouseRegion;
  final bool isAnimated;
  final bool actionEnabled;

  const DialogButtonRow({
    super.key,
    this.cancelLabel = 'Cancel',
    required this.actionLabel,
    required this.actionColor,
    this.actionTextColor,
    required this.onCancel,
    required this.onAction,
    this.useMouseRegion = true,
    this.isAnimated = false,
    this.actionEnabled = true,
  });

  Widget _wrapWithMouseRegion({required Widget child}) {
    if (!useMouseRegion) return child;
    return MouseRegion(cursor: SystemMouseCursors.click, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveActionTextColor = actionTextColor ?? AppColors.textPrimary;

    return Row(
      children: [
        Expanded(
          child: _wrapWithMouseRegion(
            child: GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    cancelLabel,
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.7),
                      fontSize: AppTypography.lg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _wrapWithMouseRegion(
            child: GestureDetector(
              onTap: onAction,
              child: isAnimated
                  ? AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: actionEnabled
                            ? actionColor
                            : actionColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          actionLabel,
                          style: TextStyle(
                            color: actionEnabled
                                ? effectiveActionTextColor
                                : effectiveActionTextColor.withValues(
                                    alpha: 0.4,
                                  ),
                            fontSize: AppTypography.lg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: actionColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          actionLabel,
                          style: TextStyle(
                            color: effectiveActionTextColor,
                            fontSize: AppTypography.lg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
