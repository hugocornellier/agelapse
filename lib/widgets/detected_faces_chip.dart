import 'package:flutter/material.dart';

import '../models/detected_faces_snapshot.dart';
import '../styles/styles.dart';

/// Compact header indicator showing the number of detected faces, sitting just
/// left of the info button in the image preview. Tapping it (when there are
/// faces) opens the standalone faces dialog.
///
/// Visibility policy: shown only when the count is known (available or an
/// explicit no-faces result). Unknown/unavailable states render nothing rather
/// than a misleading "0".
class DetectedFacesChip extends StatelessWidget {
  final Future<DetectedFacesSnapshot>? future;
  final VoidCallback? onTap;

  const DetectedFacesChip({
    super.key,
    required this.future,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<DetectedFacesSnapshot>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _chip(
            child: _spinner(),
            tappable: false,
          );
        }
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();

        final count = data.count;
        if (count == null) {
          // Unknown (legacy / not stabilized / missing). Hide rather than lie.
          return const SizedBox.shrink();
        }

        final bool tappable = data.hasFaces && onTap != null;
        return _chip(
          tappable: tappable,
          onTap: tappable ? onTap : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.face_retouching_natural,
                size: 14,
                color: AppColors.settingsTextSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: AppTypography.sm,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _spinner() {
    return SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.settingsTextSecondary,
      ),
    );
  }

  Widget _chip({
    required Widget child,
    required bool tappable,
    VoidCallback? onTap,
  }) {
    final content = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );

    if (!tappable) return content;

    return Semantics(
      button: true,
      label: 'Detected faces',
      child: Tooltip(
        message: 'Detected faces',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: content,
          ),
        ),
      ),
    );
  }
}
