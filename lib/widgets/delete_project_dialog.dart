import 'package:flutter/material.dart';

import '../styles/styles.dart';
import 'bottom_sheet_container.dart';
import 'bottom_sheet_header.dart';
import 'dialog_button_row.dart';
import 'styled_text_field.dart';

Color get _dangerRed => AppColors.danger;

/// Shows a type-to-confirm delete dialog for a project.
/// Returns `true` if the user confirmed deletion, `false` otherwise.
Future<bool?> showDeleteProjectDialog({
  required BuildContext context,
  required String projectName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _DeleteProjectDialogContent(projectName: projectName),
  );
}

class _DeleteProjectDialogContent extends StatefulWidget {
  final String projectName;

  const _DeleteProjectDialogContent({required this.projectName});

  @override
  State<_DeleteProjectDialogContent> createState() =>
      _DeleteProjectDialogContentState();
}

class _DeleteProjectDialogContentState
    extends State<_DeleteProjectDialogContent> {
  final TextEditingController _controller = TextEditingController();
  bool _isNameCorrect = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validateName);
  }

  void _validateName() {
    setState(() {
      _isNameCorrect = _controller.text.trim() == widget.projectName;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_validateName);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: BottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BottomSheetHeader(
              title: 'Delete Project',
              titleColor: _dangerRed,
              onClose: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 16),
            // Warning message
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _dangerRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dangerRed.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: _dangerRed.withValues(alpha: 0.8),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This will permanently delete "${widget.projectName}" and all its photos. This action cannot be undone.',
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(alpha: 0.8),
                        fontSize: AppTypography.md,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Confirmation text
            Text(
              'To confirm, type "${widget.projectName}" below:',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.7),
                fontSize: AppTypography.md,
              ),
            ),
            const SizedBox(height: 12),
            // Text field
            StyledTextField(
              controller: _controller,
              hintText: 'Project name',
              borderColor: _isNameCorrect
                  ? _dangerRed.withValues(alpha: 0.5)
                  : AppColors.textPrimary.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 20),
            // Buttons
            DialogButtonRow(
              actionLabel: 'Delete',
              actionColor: _dangerRed,
              onCancel: () => Navigator.pop(context, false),
              onAction:
                  _isNameCorrect ? () => Navigator.pop(context, true) : null,
              useMouseRegion: false,
              isAnimated: true,
              actionEnabled: _isNameCorrect,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
