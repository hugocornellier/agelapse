import 'package:flutter/material.dart';

import '../styles/styles.dart';
import '../widgets/info_dialog.dart';

/// Common dialog builders for gallery operations.
/// Consolidates duplicate dialog patterns from gallery_page.dart and image_preview_navigator.dart.
class GalleryDialogUtils {
  /// Shows a delete confirmation dialog.
  ///
  /// Returns true if user confirmed deletion, false if cancelled, null if dismissed.
  ///
  /// [useAppColors] - If true, uses AppColors styling (for image_preview_navigator).
  ///                  If false, uses default theme styling (for gallery_page).
  static Future<bool?> showDeleteConfirmation(
    BuildContext context, {
    String title = 'Delete Image?',
    String content = 'Do you want to delete this image?',
    bool useAppColors = false,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        if (useAppColors) {
          return AlertDialog(
            backgroundColor: AppColors.settingsCardBackground,
            title: Text(
              title,
              style: TextStyle(color: AppColors.settingsTextPrimary),
            ),
            content: Text(
              content,
              style: TextStyle(color: AppColors.settingsTextSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        }
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Shows an import complete dialog.
  ///
  /// [imported] - Number of photos successfully imported
  /// [skipped] - Number of photos skipped (already imported)
  static void showImportComplete(
    BuildContext context, {
    required int imported,
    required int skipped,
  }) {
    showStyledInfoDialog(
      context,
      'Imported: $imported\nSkipped (already imported): $skipped',
      title: 'Import Complete',
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
    );
  }

  /// Shows an importing in progress dialog with live status updates.
  ///
  /// [processingNotifier] - ValueNotifier that updates with current processing status
  /// [onDialogOpened] - Callback that receives a function to close the dialog
  ///
  /// Returns a function that closes the dialog and marks it as inactive.
  static void showImportingDialog(
    BuildContext context, {
    required ValueNotifier<String> processingNotifier,
    required void Function(VoidCallback closeDialog) onDialogOpened,
    VoidCallback? onDismiss,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        void closeMe() {
          Navigator.of(dialogContext).pop();
          onDismiss?.call();
        }

        // Provide close callback to caller
        onDialogOpened(closeMe);

        return AlertDialog(
          title: const Text("Importing Active"),
          content: ValueListenableBuilder<String>(
            valueListenable: processingNotifier,
            builder: (context, value, child) {
              return Text("Currently processing image taken $value...");
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: closeMe,
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  /// Shows a simple info dialog.
  ///
  /// [title] - Dialog title
  /// [content] - Dialog content text
  static void showInfoDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Shows a snackbar with a message.
  static void showSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
      ),
    );
  }

  /// Shows an error snackbar.
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: duration,
      ),
    );
  }
}
