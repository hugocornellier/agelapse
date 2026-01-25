import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../utils/capture_timezone.dart';
import '../utils/date_stamp_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/project_utils.dart';
import '../utils/settings_utils.dart';
import 'stabilizer_utils/stabilizer_utils.dart';

class OutputImageLoader {
  final int projectId;
  String? projectOrientation;
  String? aspectRatio;
  String? resolution;
  double offsetX = 0.0;
  double offsetY = 0.0;
  double? ghostImageOffsetX;
  double? ghostImageOffsetY;
  ui.Image? guideImage;
  Color backgroundColor = Colors.black;

  // Date stamp preview settings
  bool dateStampEnabled = false;
  String dateStampPosition = 'lower right';
  String dateStampFormat = 'MMM dd, yyyy';
  int dateStampSizePercent = 3;
  double dateStampOpacity = 1.0;
  String dateStampFontFamily = 'Inter';

  // Watermark settings (for collision detection)
  bool watermarkEnabled = false;
  String? watermarkPosition;

  // Timestamp for preview (from guide photo)
  int? previewTimestampMs;
  int? captureOffsetMinutes;

  /// Track if we have loaded a real stabilized guide image (vs placeholder)
  bool hasRealGuideImage = false;

  /// Path to the current guide image file (to check if it still exists)
  String? _guideImagePath;

  OutputImageLoader(this.projectId);

  /// Dispose native resources. Call this when done with the loader.
  void dispose() {
    guideImage?.dispose();
    guideImage = null;
  }

  Future<void> initialize() async {
    await _loadSettings();
    await _initializeImageDirectory();
  }

  /// Reset to placeholder state when orientation changes.
  /// This clears the stale guide image and reloads orientation-specific settings.
  Future<void> resetToPlaceholder() async {
    // Dispose old image to free memory
    guideImage?.dispose();

    // Load placeholder SVG with eye holes aligned to stabilization guides
    guideImage = await ProjectUtils.loadSvgImage(
      'assets/images/person-grey.svg',
      width: 400,
      height: 480,
    );
    ghostImageOffsetX = 0.105;
    ghostImageOffsetY = 0.292;
    hasRealGuideImage = false;
    _guideImagePath = null;
    previewTimestampMs = null;
    captureOffsetMinutes = null;

    // Reload settings to get new orientation-specific offsets
    await _loadSettings();
  }

  /// Attempt to load a real stabilized guide image for current settings.
  ///
  /// Returns `true` if a new image was loaded, `false` if no image available
  /// or already showing the correct image. Safe to call repeatedly.
  Future<bool> tryLoadRealGuideImage() async {
    if (hasRealGuideImage) {
      if (_guideImagePath != null && await File(_guideImagePath!).exists()) {
        return false;
      }
      // File was deleted, need to reload
      hasRealGuideImage = false;
      _guideImagePath = null;
      previewTimestampMs = null;
      captureOffsetMinutes = null;
    }

    try {
      final Map<String, Object?>? guidePhoto = await DirUtils.getGuidePhoto(
        offsetX,
        projectId,
      );

      if (guidePhoto == null) {
        // No stabilized image available for current orientation/offset
        return false;
      }

      final String guideImagePath = await DirUtils.getGuideImagePath(
        projectId,
        guidePhoto,
      );

      // Check if file exists
      final file = File(guideImagePath);
      if (!await file.exists()) {
        return false;
      }

      // Get offset data from the photo
      final stabilizedColumn = DB.instance.getStabilizedColumn(
        projectOrientation!,
      );
      final stabColOffsetX = "${stabilizedColumn}OffsetX";
      final stabColOffsetY = "${stabilizedColumn}OffsetY";

      final rawOffsetX = guidePhoto[stabColOffsetX];
      final rawOffsetY = guidePhoto[stabColOffsetY];
      final newOffsetX = rawOffsetX is double
          ? rawOffsetX
          : double.tryParse(rawOffsetX?.toString() ?? '');
      final newOffsetY = rawOffsetY is double
          ? rawOffsetY
          : double.tryParse(rawOffsetY?.toString() ?? '');

      // Dispose old image before loading new one
      guideImage?.dispose();

      // Load the new guide image
      guideImage = await StabUtils.loadImageFromFile(file);
      ghostImageOffsetX = newOffsetX;
      ghostImageOffsetY = newOffsetY;
      hasRealGuideImage = true;
      _guideImagePath = guideImagePath;

      // Extract timestamp from guide photo for date preview
      final photoTimestamp = guidePhoto['timestamp'];
      if (photoTimestamp != null) {
        previewTimestampMs = photoTimestamp is int
            ? photoTimestamp
            : int.tryParse(photoTimestamp.toString());

        // Load timezone offset for this photo
        if (previewTimestampMs != null) {
          final offsets = await CaptureTimezone.loadOffsetsForFiles(
            [previewTimestampMs.toString()],
            projectId,
          );
          captureOffsetMinutes = offsets[previewTimestampMs.toString()];
        }
      }

      return true;
    } catch (e) {
      debugPrint('Failed to load real guide image: $e');
      return false;
    }
  }

  Future<void> _loadSettings() async {
    final String offsetXSettingVal =
        await SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString());
    final String offsetYSettingVal =
        await SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString());

    projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    aspectRatio = await SettingsUtil.loadAspectRatio(projectId.toString());
    resolution = await SettingsUtil.loadVideoResolution(projectId.toString());

    // Load background color
    final bgColorHex =
        await SettingsUtil.loadBackgroundColor(projectId.toString());
    backgroundColor = _hexToColor(bgColorHex);

    offsetX = double.parse(offsetXSettingVal);
    offsetY = double.parse(offsetYSettingVal);

    // Load date stamp settings
    await loadDateStampSettings();
  }

  /// Load date stamp settings for preview.
  Future<void> loadDateStampSettings() async {
    final projectIdStr = projectId.toString();

    final results = await Future.wait([
      SettingsUtil.loadExportDateStampEnabled(projectIdStr),
      SettingsUtil.loadExportDateStampPosition(projectIdStr),
      SettingsUtil.loadExportDateStampFormat(projectIdStr),
      SettingsUtil.loadExportDateStampSize(projectIdStr),
      SettingsUtil.loadExportDateStampOpacity(projectIdStr),
      SettingsUtil.loadExportDateStampFont(projectIdStr),
      SettingsUtil.loadGalleryDateStampFont(projectIdStr),
      SettingsUtil.loadWatermarkSetting(projectIdStr),
      SettingsUtil.loadWatermarkPosition(),
    ]);

    dateStampEnabled = results[0] as bool;
    dateStampPosition = results[1] as String;
    dateStampFormat = results[2] as String;
    dateStampSizePercent = results[3] as int;
    dateStampOpacity = results[4] as double;

    final exportFont = results[5] as String;
    final galleryFont = results[6] as String;

    // Handle "Same as thumbnail" option
    final resolvedFont =
        DateStampUtils.resolveExportFont(exportFont, galleryFont);

    // Resolve custom font if needed
    dateStampFontFamily = await DateStampUtils.resolveFontFamily(resolvedFont);

    watermarkEnabled = results[7] as bool;
    watermarkPosition = results[8] as String?;
  }

  /// Get formatted date stamp text for preview.
  /// Returns null if date stamp is disabled or no guide photo timestamp.
  String? getDateStampPreviewText() {
    if (!dateStampEnabled) return null;

    final timestamp = previewTimestampMs;
    if (timestamp == null) {
      // No guide photo loaded - don't show date stamp on placeholder
      return null;
    }

    return DateStampUtils.formatTimestamp(
      timestamp,
      dateStampFormat,
      captureOffsetMinutes: captureOffsetMinutes,
    );
  }

  /// Converts a hex string like '#FF0000' to a Flutter Color.
  Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Add full opacity
    }
    return Color(int.parse(hex, radix: 16));
  }

  /// Get the display aspect ratio (height/width) for fitting the output preview.
  /// Handles both custom WIDTHxHEIGHT resolutions and presets.
  double getDisplayAspectRatio() {
    if (resolution == null ||
        aspectRatio == null ||
        projectOrientation == null) {
      // Fallback to 16:9 landscape
      return 9 / 16;
    }

    final dims = StabUtils.getOutputDimensions(
      resolution!,
      aspectRatio!,
      projectOrientation!,
    );

    if (dims == null) {
      // Fallback to 16:9 based on orientation
      return projectOrientation == 'landscape' ? 9 / 16 : 16 / 9;
    }

    // Return height/width for display fitting
    return dims.$2 / dims.$1;
  }

  /// Get the output resolution as a formatted string (e.g., "1920 × 1080").
  /// Returns null if settings are not loaded.
  String? getResolutionString() {
    if (resolution == null ||
        aspectRatio == null ||
        projectOrientation == null) {
      return null;
    }

    final dims = StabUtils.getOutputDimensions(
      resolution!,
      aspectRatio!,
      projectOrientation!,
    );

    if (dims == null) return null;

    return '${dims.$1} × ${dims.$2}';
  }

  Future<void> _initializeImageDirectory() async {
    try {
      final Map<String, Object?>? guidePhoto = await DirUtils.getGuidePhoto(
        offsetX,
        projectId,
      );
      final String guideImagePath = await DirUtils.getGuideImagePath(
        projectId,
        guidePhoto,
      );

      if (guidePhoto != null) {
        final stabilizedColumn = DB.instance.getStabilizedColumn(
          projectOrientation!,
        );
        final stabColOffsetX = "${stabilizedColumn}OffsetX";
        final stabColOffsetY = "${stabilizedColumn}OffsetY";

        final rawOffsetX = guidePhoto[stabColOffsetX];
        final rawOffsetY = guidePhoto[stabColOffsetY];
        final offsetXData = rawOffsetX is double
            ? rawOffsetX
            : double.tryParse(rawOffsetX?.toString() ?? '');
        final offsetYData = rawOffsetY is double
            ? rawOffsetY
            : double.tryParse(rawOffsetY?.toString() ?? '');

        ghostImageOffsetX = offsetXData;
        ghostImageOffsetY = offsetYData;

        // Extract timestamp from guide photo for date preview
        final photoTimestamp = guidePhoto['timestamp'];
        if (photoTimestamp != null) {
          previewTimestampMs = photoTimestamp is int
              ? photoTimestamp
              : int.tryParse(photoTimestamp.toString());

          // Load timezone offset for this photo
          if (previewTimestampMs != null) {
            final offsets = await CaptureTimezone.loadOffsetsForFiles(
              [previewTimestampMs.toString()],
              projectId,
            );
            captureOffsetMinutes = offsets[previewTimestampMs.toString()];
          }
        }

        try {
          guideImage = await StabUtils.loadImageFromFile(File(guideImagePath));
          hasRealGuideImage = true;
          _guideImagePath = guideImagePath;
        } catch (e) {
          LogService.instance.log(
            "Error caught $e, setting ghostImage to SVG placeholder",
          );
          guideImage = await ProjectUtils.loadSvgImage(
            'assets/images/person-grey.svg',
            width: 400,
            height: 480,
          );
          ghostImageOffsetX = 0.105;
          ghostImageOffsetY = 0.292;
        }
      } else {
        guideImage = await ProjectUtils.loadSvgImage(
          'assets/images/person-grey.svg',
          width: 400,
          height: 480,
        );
        ghostImageOffsetX = 0.105;
        ghostImageOffsetY = 0.292;
      }
    } catch (e) {
      debugPrint('Failed to initialize image directory: $e');
    }
  }
}
