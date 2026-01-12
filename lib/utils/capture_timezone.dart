import 'package:path/path.dart' as p;
import '../services/database_helper.dart';

/// Centralized utility for capture timezone offset handling.
///
/// All timezone offset logic flows through this class to ensure
/// consistent behavior across the app. Photos store their capture
/// timezone as an offset in minutes from UTC.
class CaptureTimezone {
  CaptureTimezone._();

  // ─────────────────────────────────────────────────────────────
  // Load offsets from file paths
  // ─────────────────────────────────────────────────────────────

  /// Load capture timezone offsets for a list of image file paths.
  /// Returns map of timestamp -> offset minutes.
  ///
  /// File paths are expected to have timestamp as filename (e.g., "1234567890.jpg").
  /// Deduplicates timestamps automatically.
  static Future<Map<String, int?>> loadOffsetsForFiles(
    List<String> filePaths,
    int projectId,
  ) async {
    if (filePaths.isEmpty) return {};

    final timestamps =
        filePaths.map((f) => p.basenameWithoutExtension(f)).toSet().toList();

    return DB.instance.getCaptureOffsetMinutesForTimestamps(
      timestamps,
      projectId,
    );
  }

  /// Load capture timezone offsets for multiple file lists.
  /// Useful when loading offsets for both raw and stabilized images.
  static Future<Map<String, int?>> loadOffsetsForMultipleLists(
    List<List<String>> fileLists,
    int projectId,
  ) async {
    final allPaths = fileLists.expand((list) => list).toList();
    return loadOffsetsForFiles(allPaths, projectId);
  }

  // ─────────────────────────────────────────────────────────────
  // Extract offset from photo data map
  // ─────────────────────────────────────────────────────────────

  /// Safely extract captureOffsetMinutes from a photo data map.
  /// Returns null if the map is null or doesn't contain a valid int offset.
  static int? extractOffset(Map<String, dynamic>? photoData) {
    if (photoData == null) return null;
    final value = photoData['captureOffsetMinutes'];
    return value is int ? value : null;
  }

  // ─────────────────────────────────────────────────────────────
  // Convert UTC timestamp to capture-local DateTime
  // ─────────────────────────────────────────────────────────────

  /// Convert a UTC millisecond timestamp to the capture-local DateTime.
  /// Falls back to device local time if offset is null.
  ///
  /// This ensures dates are displayed in the timezone where the photo
  /// was taken, not the device's current timezone.
  static DateTime toLocalDateTime(int timestampMs, {int? offsetMinutes}) {
    final utc = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
    return offsetMinutes != null
        ? utc.add(Duration(minutes: offsetMinutes))
        : utc.toLocal();
  }

  // ─────────────────────────────────────────────────────────────
  // Format offset as UTC string
  // ─────────────────────────────────────────────────────────────

  /// Format offset minutes as "UTC±HH:MM" string.
  /// If offsetMinutes is null, uses [fallbackDateTime]'s timezone offset,
  /// or current device timezone if fallbackDateTime is also null.
  static String formatOffsetLabel(
    int? offsetMinutes, {
    DateTime? fallbackDateTime,
  }) {
    final int minutes;
    if (offsetMinutes != null) {
      minutes = offsetMinutes;
    } else if (fallbackDateTime != null) {
      minutes = fallbackDateTime.timeZoneOffset.inMinutes;
    } else {
      minutes = DateTime.now().timeZoneOffset.inMinutes;
    }
    final sign = minutes >= 0 ? '+' : '−'; // Using proper minus sign (U+2212)
    final absMin = minutes.abs();
    final hh = (absMin ~/ 60).toString().padLeft(2, '0');
    final mm = (absMin % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hh:$mm';
  }
}
