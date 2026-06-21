import 'package:flutter/material.dart';

import '../services/face_thumbnail_service.dart';
import '../styles/styles.dart';

/// Renders a single cropped face thumbnail in a fixed rounded frame, with
/// loading / error / selected states. [result] is null while the crop is
/// still being generated.
class FaceCropThumbnail extends StatelessWidget {
  final FaceThumbnailResult? result;
  final double size;
  final bool selected;

  const FaceCropThumbnail({
    super.key,
    required this.result,
    this.size = 56,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? Border.all(color: AppColors.settingsAccent, width: 2)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: _content(),
    );
  }

  Widget _content() {
    final r = result;
    if (r == null) {
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.settingsTextSecondary,
          ),
        ),
      );
    }
    final bytes = r.bytes;
    if (bytes == null) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: size * 0.4,
          color: AppColors.settingsTextSecondary,
        ),
      );
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: size * 0.4,
          color: AppColors.settingsTextSecondary,
        ),
      ),
    );
  }
}
