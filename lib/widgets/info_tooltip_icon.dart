import 'package:flutter/material.dart';
import '../styles/styles.dart';
import 'info_dialog.dart';

/// A tappable info icon that displays a dialog with the provided [content].
///
/// This widget provides a consistent tooltip/info pattern across the app.
/// Tap the icon to show an informational dialog.
class InfoTooltipIcon extends StatelessWidget {
  /// The text content to display in the info dialog.
  final String content;

  /// Whether the icon should appear disabled (greyed out).
  final bool disabled;

  const InfoTooltipIcon({
    super.key,
    required this.content,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showStyledInfoDialog(context, content),
        child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: disabled
                ? AppColors.settingsTextTertiary
                : AppColors.settingsTextSecondary,
          ),
        ),
      ),
    );
  }
}
