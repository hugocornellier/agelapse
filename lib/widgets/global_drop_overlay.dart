import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A centered overlay that appears when files are dragged over the app window.
///
/// This is a minimal drop zone (no "Browse Files" button) that appears
/// globally when:
/// - Files are dragged over the app window
/// - The import sheet is NOT open
/// - User is inside a project (MainNavigation)
///
/// CRITICAL: Uses [IgnorePointer] so the [DropTarget] below can receive drops.
class GlobalDropOverlay extends StatelessWidget {
  final bool isDragging;

  const GlobalDropOverlay({super.key, required this.isDragging});

  @override
  Widget build(BuildContext context) {
    if (!isDragging) return const SizedBox.shrink();

    // CRITICAL: IgnorePointer so DropTarget below can receive drops
    return IgnorePointer(
      child: Container(
        color: AppColors.overlay.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.info.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.file_download_outlined,
                    size: 48,
                    color: AppColors.info.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'Drop files to import',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppTypography.xl,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle - clarify global scope
                Text(
                  'Release anywhere in window to add photos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                    fontSize: AppTypography.md,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
