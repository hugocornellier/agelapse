import 'package:intl/intl.dart';

/// Centralized utility for generating standardized export filenames.
///
/// Format: {SanitizedProjectName}_AgeLapse_{YYYY-MM-DD}_{HHmmss}.{ext}
/// Example: Wedding_Timelapse_AgeLapse_2026-01-24_143052.mp4
class ExportNamingUtils {
  /// Maximum length for the project name portion (before truncation)
  static const int maxProjectNameLength = 50;

  /// Brand identifier included in all exports
  static const String brandIdentifier = 'AgeLapse';

  /// Default project name when none provided
  static const String defaultProjectName = 'Untitled';

  /// Generates a standardized export filename.
  ///
  /// [projectName] - The project name (will be sanitized)
  /// [extension] - File extension without dot (e.g., 'mp4', 'zip')
  /// [timestamp] - Optional custom timestamp; defaults to current time
  ///
  /// Returns filename in format: {SanitizedName}_AgeLapse_{YYYY-MM-DD}_{HHmmss}.{ext}
  static String generateExportFilename({
    required String projectName,
    required String extension,
    DateTime? timestamp,
  }) {
    final DateTime dt = timestamp ?? DateTime.now();
    final String sanitizedName = sanitizeProjectName(projectName);
    final String formattedDate = formatTimestamp(dt);
    final String cleanExt =
        extension.startsWith('.') ? extension.substring(1) : extension;

    return '${sanitizedName}_${brandIdentifier}_$formattedDate.$cleanExt';
  }

  /// Generates export filename for video files.
  static String generateVideoFilename({
    required String projectName,
    DateTime? timestamp,
  }) {
    return generateExportFilename(
      projectName: projectName,
      extension: 'mp4',
      timestamp: timestamp,
    );
  }

  /// Generates export filename for ZIP archives.
  static String generateZipFilename({
    required String projectName,
    DateTime? timestamp,
  }) {
    return generateExportFilename(
      projectName: projectName,
      extension: 'zip',
      timestamp: timestamp,
    );
  }

  /// Sanitizes project name for cross-platform filesystem compatibility.
  ///
  /// - Replaces filesystem-unsafe characters with underscores
  /// - Collapses multiple spaces/underscores into single underscore
  /// - Trims leading/trailing whitespace and underscores
  /// - Truncates to [maxProjectNameLength] characters
  /// - Returns [defaultProjectName] if result is empty
  static String sanitizeProjectName(String name) {
    if (name.trim().isEmpty) {
      return defaultProjectName;
    }

    String sanitized = name
        // Replace filesystem-unsafe characters with underscore
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        // Replace other non-word characters (except spaces and hyphens)
        .replaceAll(RegExp(r"[^\w\s-]"), '_')
        // Collapse whitespace and multiple underscores to single underscore
        .replaceAll(RegExp(r'[\s_]+'), '_')
        // Trim leading/trailing underscores
        .replaceAll(RegExp(r'^_+|_+$'), '');

    // Truncate if necessary
    if (sanitized.length > maxProjectNameLength) {
      sanitized = sanitized.substring(0, maxProjectNameLength);
      // Remove trailing underscore after truncation
      sanitized = sanitized.replaceAll(RegExp(r'_+$'), '');
    }

    return sanitized.isEmpty ? defaultProjectName : sanitized;
  }

  /// Formats timestamp for filename inclusion.
  /// Format: YYYY-MM-DD_HHmmss
  static String formatTimestamp(DateTime dt) {
    return DateFormat('yyyy-MM-dd_HHmmss').format(dt);
  }
}
