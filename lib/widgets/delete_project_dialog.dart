import 'package:flutter/material.dart';

const Color _dangerRed = Color(0xffFF453A);

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
      child: Container(
        padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0),
        decoration: const BoxDecoration(
          color: Color(0xff1a1a1a),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20.0),
            topRight: Radius.circular(20.0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delete Project',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _dangerRed,
                    letterSpacing: -0.3,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
              ],
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
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
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
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            // Text field
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isNameCorrect
                      ? _dangerRed.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Project name',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _isNameCorrect
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _isNameCorrect
                            ? _dangerRed
                            : _dangerRed.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            color: _isNameCorrect
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
