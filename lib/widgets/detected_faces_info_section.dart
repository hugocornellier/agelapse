import 'package:flutter/material.dart';

import '../models/detected_faces_snapshot.dart';
import '../services/face_thumbnail_service.dart';
import '../styles/styles.dart';
import 'face_crop_thumbnail.dart';

class _SectionData {
  final DetectedFacesSnapshot snapshot;
  final List<FaceThumbnailResult> thumbs;
  const _SectionData(this.snapshot, this.thumbs);
}

/// "Detected Faces" section for the image-info dialog: a count row plus a strip
/// of cropped face thumbnails with a checkmark on the stabilized face. Renders
/// nothing for unsupported project types; shows an explanatory line for
/// no-faces / legacy / unavailable states.
class DetectedFacesInfoSection extends StatefulWidget {
  final Future<DetectedFacesSnapshot> future;

  const DetectedFacesInfoSection({super.key, required this.future});

  @override
  State<DetectedFacesInfoSection> createState() =>
      _DetectedFacesInfoSectionState();
}

class _DetectedFacesInfoSectionState extends State<DetectedFacesInfoSection> {
  late Future<_SectionData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_SectionData> _load() async {
    final snap = await widget.future;
    if (!snap.isAvailable) return _SectionData(snap, const []);
    final thumbs = await FaceThumbnailService.instance.loadOrCreate(snap);
    return _SectionData(snap, thumbs);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SectionData>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _wrap(_loadingRow());
        }
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();

        final s = data.snapshot;
        if (s.availability ==
            DetectedFacesAvailability.unsupportedProjectType) {
          return const SizedBox.shrink();
        }

        if (s.isAvailable) {
          return _wrap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Count', '${s.count}'),
                const SizedBox(height: 8),
                _strip(data),
              ],
            ),
          );
        }

        // Known-zero or unavailable: show an explanatory line.
        return _wrap(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              s.message ?? 'No faces detected.',
              style: TextStyle(
                color: AppColors.settingsTextSecondary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _wrap(Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _sectionHeader('Detected Faces'),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _strip(_SectionData data) {
    final faces = data.snapshot.cache?.faces ?? const [];
    final selected = data.snapshot.selectedFaceIndex;
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: faces.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = i < data.thumbs.length ? data.thumbs[i] : null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaceCropThumbnail(result: r, size: 48, selected: i == selected),
              const SizedBox(height: 4),
              Text(
                'Face ${i + 1}',
                style: TextStyle(
                  color: i == selected
                      ? AppColors.settingsAccent
                      : AppColors.settingsTextSecondary,
                  fontSize: AppTypography.xs,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _loadingRow() {
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.settingsTextSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading…',
          style: TextStyle(
            color: AppColors.settingsTextSecondary,
            fontSize: AppTypography.sm,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.settingsTextSecondary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.settingsTextPrimary,
            fontSize: AppTypography.md,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: AppColors.settingsCardBorder, height: 1),
      ],
    );
  }
}
