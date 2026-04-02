import '../utils/capture_timezone.dart';

/// The tier of confidence for the date source of an imported file.
enum DateSourceTier {
  exif,
  filename,
  fileModified;

  /// Human-readable label for display in the import preview UI.
  String get sourceLabel {
    switch (this) {
      case DateSourceTier.exif:
        return 'EXIF';
      case DateSourceTier.filename:
        return 'Filename';
      case DateSourceTier.fileModified:
        return 'File Modified';
    }
  }
}

/// Represents a single file being previewed before import.
class ImportPreviewItem {
  final String filePath;
  final String filename;
  final int timestampMs;
  final int captureOffsetMinutes;
  final DateSourceTier sourceTier;

  const ImportPreviewItem({
    required this.filePath,
    required this.filename,
    required this.timestampMs,
    required this.captureOffsetMinutes,
    required this.sourceTier,
  });

  /// The capture-local DateTime for display, derived from [timestampMs] and
  /// [captureOffsetMinutes].
  DateTime get displayDate => CaptureTimezone.toLocalDateTime(timestampMs,
      offsetMinutes: captureOffsetMinutes);

  /// Human-readable label for the date source tier.
  String get sourceLabel => sourceTier.sourceLabel;
}
