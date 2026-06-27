import 'package:flutter/material.dart';

import '../models/detected_faces_snapshot.dart';
import '../services/face_thumbnail_service.dart';
import '../styles/styles.dart';
import 'face_crop_thumbnail.dart';

/// Shows the standalone "Detected Faces" dialog: every detected face with its
/// crop, a checkmark on the face that was stabilized on, and a "stabilize on
/// this face" action for the others.
///
/// [onSelectFace] (re-)stabilizes the photo onto the tapped face and returns
/// true on success. [reload] returns a fresh snapshot afterwards so the
/// checkmark moves in place without reopening the dialog.
Future<void> showDetectedFacesDialog({
  required BuildContext context,
  required DetectedFacesSnapshot snapshot,
  required bool stabilizationRunningInMain,
  Future<bool> Function(int faceIndex)? onSelectFace,
  Future<DetectedFacesSnapshot> Function()? reload,
}) {
  return showDialog(
    context: context,
    builder: (_) => DetectedFacesDialog(
      initialSnapshot: snapshot,
      stabilizationRunningInMain: stabilizationRunningInMain,
      onSelectFace: onSelectFace,
      reload: reload,
    ),
  );
}

class DetectedFacesDialog extends StatefulWidget {
  final DetectedFacesSnapshot initialSnapshot;
  final bool stabilizationRunningInMain;
  final Future<bool> Function(int faceIndex)? onSelectFace;
  final Future<DetectedFacesSnapshot> Function()? reload;

  const DetectedFacesDialog({
    super.key,
    required this.initialSnapshot,
    required this.stabilizationRunningInMain,
    this.onSelectFace,
    this.reload,
  });

  @override
  State<DetectedFacesDialog> createState() => _DetectedFacesDialogState();
}

class _DetectedFacesDialogState extends State<DetectedFacesDialog> {
  late DetectedFacesSnapshot _snapshot;
  late Future<List<FaceThumbnailResult>> _thumbs;
  bool _busy = false;
  int? _busyIndex;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _thumbs = FaceThumbnailService.instance.loadOrCreate(_snapshot);
  }

  bool get _orientationSupportsSelect => _snapshot.orientation == 'original';

  bool _canSelect(int index) {
    return widget.onSelectFace != null &&
        !_busy &&
        !widget.stabilizationRunningInMain &&
        _orientationSupportsSelect &&
        index != _snapshot.selectedFaceIndex;
  }

  Future<void> _select(int index) async {
    if (!_canSelect(index)) return;
    setState(() {
      _busy = true;
      _busyIndex = index;
    });
    bool success = false;
    try {
      success = await widget.onSelectFace!(index);
      if (success && widget.reload != null) {
        final fresh = await widget.reload!();
        if (!mounted) return;
        setState(() {
          _snapshot = fresh;
          _thumbs = FaceThumbnailService.instance.loadOrCreate(fresh);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyIndex = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final faces = _snapshot.cache?.faces ?? const [];
    final media = MediaQuery.of(context);
    final double maxW = media.size.width * 0.92;
    final double width = maxW > 460 ? 460 : maxW;
    final double maxH = media.size.height * 0.85;

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: AppColors.settingsBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(faces.length),
                if (_noticeText() != null) ...[
                  const SizedBox(height: 8),
                  _notice(_noticeText()!),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: faces.length,
                    itemBuilder: (context, i) => _faceRow(i),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(color: AppColors.settingsTextPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int count) {
    return Row(
      children: [
        Icon(
          Icons.face_retouching_natural,
          size: 20,
          color: AppColors.settingsTextPrimary,
        ),
        const SizedBox(width: 8),
        Text(
          'Detected Faces',
          style: TextStyle(
            fontSize: AppTypography.lg,
            fontWeight: FontWeight.w600,
            color: AppColors.settingsTextPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: TextStyle(
            fontSize: AppTypography.md,
            color: AppColors.settingsTextSecondary,
          ),
        ),
      ],
    );
  }

  String? _noticeText() {
    if (widget.stabilizationRunningInMain) {
      return 'Wait for the current stabilization to finish before changing the '
          'selected face.';
    }
    if (!_orientationSupportsSelect && widget.onSelectFace != null) {
      return 'This photo was detected in a rotated orientation; choosing a '
          'different face here isn\'t supported yet.';
    }
    return null;
  }

  Widget _notice(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.settingsTextSecondary,
          fontSize: AppTypography.sm,
        ),
      ),
    );
  }

  Widget _faceRow(int index) {
    final bool isSelected = index == _snapshot.selectedFaceIndex;
    final bool isBusyRow = _busy && _busyIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          FutureBuilder<List<FaceThumbnailResult>>(
            future: _thumbs,
            builder: (context, snap) {
              FaceThumbnailResult? r;
              // Only `null` while genuinely loading -> spinner. Once the future
              // settles (data or error), always produce a non-null result so
              // the thumbnail shows an image or a broken-image icon, never an
              // endless spinner.
              if (snap.connectionState == ConnectionState.done) {
                final list = snap.data;
                if (snap.hasError) {
                  r = FaceThumbnailResult(
                    faceIndex: index,
                    error: snap.error.toString(),
                  );
                } else if (list != null && index < list.length) {
                  r = list[index];
                } else {
                  r = FaceThumbnailResult(
                    faceIndex: index,
                    error: 'No crop',
                  );
                }
              }
              return FaceCropThumbnail(
                result: r,
                size: 56,
                selected: isSelected,
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Face ${index + 1}',
                  style: TextStyle(
                    color: AppColors.settingsTextPrimary,
                    fontSize: AppTypography.md,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isSelected)
                  Text(
                    'Stabilized on this face',
                    style: TextStyle(
                      color: AppColors.settingsAccent,
                      fontSize: AppTypography.sm,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _trailing(index, isSelected, isBusyRow),
        ],
      ),
    );
  }

  Widget _trailing(int index, bool isSelected, bool isBusyRow) {
    if (isBusyRow) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isSelected) {
      return Icon(
        Icons.check_circle_rounded,
        color: AppColors.settingsAccent,
        size: 24,
      );
    }
    final bool enabled = _canSelect(index);
    return TextButton(
      onPressed: enabled ? () => _select(index) : null,
      child: Text(
        'Stabilize',
        style: TextStyle(
          color: enabled
              ? AppColors.settingsAccent
              : AppColors.settingsTextSecondary,
          fontSize: AppTypography.sm,
        ),
      ),
    );
  }
}
