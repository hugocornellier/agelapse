import 'dart:io';
import '../services/custom_font_manager.dart';
import '../services/log_service.dart';
import '../utils/utils.dart';
import '../utils/date_stamp_utils.dart';

import '../services/database_helper.dart';

class SettingsUtil {
  static const String fallbackWatermarkPosition = "Lower left";
  static const int fallbackFramerate = 14;
  static const String fallbackWatermarkOpacity = '0.7';

  // Date stamp default values
  static const String fallbackDateStampPosition =
      DateStampUtils.positionLowerRight;
  static const String fallbackGalleryDateFormat =
      DateStampUtils.galleryFormatMMYY;
  static const String fallbackExportDateFormat =
      DateStampUtils.exportFormatLong;
  static const int fallbackDateStampSizePercent = 3;
  static const String fallbackDateStampOpacity = '1.0';

  static Future<String> loadTheme() async {
    return await DB.instance.getSettingValueByTitle('theme');
  }

  static Future<bool> loadFramerateIsDefault(String projectId) async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'framerate_is_default',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? true;
    } catch (e) {
      LogService.instance.log('Failed to load watermark setting: $e');
      return true;
    }
  }

  static Future<bool> loadCameraMirror(String projectId) async {
    final value = await DB.instance.getSettingValueByTitle(
      'camera_mirror',
      projectId,
    );
    return value.toLowerCase() == 'true';
  }

  static Future<bool> lightThemeActive() async {
    final String activeTheme = await loadTheme();
    return activeTheme == 'light';
  }

  static Future<String> loadDailyNotificationTime(String projectId) async {
    final String result = await DB.instance.getSettingValueByTitle(
      'daily_notification_time',
      projectId,
    );
    return result;
  }

  static Future<bool> loadEnableGrid() async {
    try {
      String enableGridValueStr = await DB.instance.getSettingValueByTitle(
        'enable_grid',
      );
      return bool.tryParse(enableGridValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<String> loadCameraFlash(String projectId) async {
    try {
      String cameraFlashValueStr = await DB.instance.getSettingValueByTitle(
        'camera_flash',
        projectId,
      );
      return cameraFlashValueStr;
    } catch (e) {
      return "auto";
    }
  }

  static Future<bool> loadSaveToCameraRoll() async {
    try {
      String saveToCameraRollStr = await DB.instance.getSettingValueByTitle(
        'save_to_camera_roll',
      );
      return bool.tryParse(saveToCameraRollStr) ?? false;
    } catch (e) {
      LogService.instance.log('Failed to load save to camera roll setting: $e');
      return false;
    }
  }

  static Future<bool> loadWatermarkSetting(String projectId) async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'enable_watermark',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> loadNotificationSetting() async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'enable_notifications',
      );
      return bool.tryParse(settingValueStr) ?? true;
    } catch (e) {
      return true;
    }
  }

  static Future<String> loadWatermarkPosition() async {
    try {
      return Utils.capitalizeFirstLetter(
        await DB.instance.getSettingValueByTitle('watermark_position'),
      );
    } catch (e) {
      return fallbackWatermarkPosition;
    }
  }

  static Future<String> loadWatermarkOpacity() async {
    try {
      return await DB.instance.getSettingValueByTitle('watermark_opacity');
    } catch (e) {
      return fallbackWatermarkOpacity;
    }
  }

  static Future<int> loadFramerate(String projectId) async {
    try {
      var data = await DB.instance.getSettingByTitle('framerate', projectId);
      return int.tryParse(data?['value']) ?? fallbackFramerate;
    } catch (e) {
      return fallbackFramerate;
    }
  }

  static Future<String> loadAspectRatio(String projectId) async {
    return await DB.instance.getSettingValueByTitle('aspect_ratio', projectId);
  }

  static Future<String> loadVideoResolution(String projectId) async {
    return await DB.instance.getSettingValueByTitle(
      'video_resolution',
      projectId,
    );
  }

  /// Load auto-compile video setting (per-project).
  /// When enabled, video is automatically compiled after stabilization.
  /// When disabled, user must manually trigger compilation from Create page.
  static Future<bool> loadAutoCompileVideo(String projectId) async {
    try {
      String value = await DB.instance.getSettingValueByTitle(
        'auto_compile_video',
        projectId,
      );
      return value.toLowerCase() == 'true';
    } catch (e) {
      return true; // Default to enabled for backwards compatibility
    }
  }

  /// Save auto-compile video setting (per-project).
  static Future<void> setAutoCompileVideo(
      String projectId, bool enabled) async {
    await DB.instance.setSettingByTitle(
      'auto_compile_video',
      enabled.toString(),
      projectId,
    );
  }

  static Future<String> loadSelectedGuidePhoto(String projectId) async {
    return await DB.instance.getSettingValueByTitle(
      'selected_guide_photo',
      projectId,
    );
  }

  static Future<String> loadProjectOrientation(String projectId) async {
    return (await DB.instance.getSettingValueByTitle(
      'project_orientation',
      projectId,
    ))
        .toLowerCase();
  }

  static Future<String> loadOffsetXCurrentOrientation(String projectId) async {
    return await _loadOffsetCurrentOrientation(projectId, 'X');
  }

  static Future<String> loadOffsetYCurrentOrientation(String projectId) async {
    return await _loadOffsetCurrentOrientation(projectId, 'Y');
  }

  static Future<String> _loadOffsetCurrentOrientation(
    String projectId,
    String axis,
  ) async {
    final String activeProjectOrientation = await loadProjectOrientation(
      projectId,
    );
    final String offsetColName = (activeProjectOrientation == 'landscape')
        ? "eyeOffset${axis}Landscape"
        : "eyeOffset${axis}Portrait";
    return await DB.instance.getSettingValueByTitle(
      offsetColName,
      projectId.toString(),
    );
  }

  static Future<String> loadGuideOffsetXCurrentOrientation(
    String projectId,
  ) async {
    return await _loadGuideOffsetCurrentOrientation(projectId, 'X');
  }

  static Future<String> loadGuideOffsetYCurrentOrientation(
    String projectId,
  ) async {
    return await _loadGuideOffsetCurrentOrientation(projectId, 'Y');
  }

  static Future<String> _loadGuideOffsetCurrentOrientation(
    String projectId,
    String axis,
  ) async {
    final String activeProjectOrientation = await loadProjectOrientation(
      projectId,
    );
    final String offsetColName = (activeProjectOrientation == 'landscape')
        ? "guideOffset${axis}Landscape"
        : "guideOffset${axis}Portrait";
    return await DB.instance.getSettingValueByTitle(
      offsetColName,
      projectId.toString(),
    );
  }

  static Future<String> loadGuideOffsetXCustomOrientation(
    String projectId,
    String customOrientation,
  ) async {
    return await _loadGuideOffsetCustomOrientation(
      projectId,
      'X',
      customOrientation,
    );
  }

  static Future<String> loadGuideOffsetYCustomOrientation(
    String projectId,
    String customOrientation,
  ) async {
    return await _loadGuideOffsetCustomOrientation(
      projectId,
      'Y',
      customOrientation,
    );
  }

  static Future<String> _loadGuideOffsetCustomOrientation(
    String projectId,
    String axis,
    String customOrientation,
  ) async {
    final String offsetColName = (customOrientation == 'landscape')
        ? "guideOffset${axis}Landscape"
        : "guideOffset${axis}Portrait";

    return await DB.instance.getSettingValueByTitle(
      offsetColName,
      projectId.toString(),
    );
  }

  static Future<bool> hasOpenedNonEmptyGallery(String projectId) async {
    try {
      final String settingValueStr = await DB.instance.getSettingValueByTitle(
        'opened_nonempty_gallery',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasOpenedNonEmptyGalleryToTrue(
    String projectIdStr,
  ) async {
    await DB.instance.setSettingByTitle(
      'opened_nonempty_gallery',
      'true',
      projectIdStr,
    );
  }

  static Future<bool> hasTakenFirstPhoto(String projectId) async {
    try {
      final String settingValueStr = await DB.instance.getSettingValueByTitle(
        'has_taken_first_photo',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasTakenFirstPhotoToTrue(String projectIdStr) async {
    await DB.instance.setSettingByTitle(
      'has_taken_first_photo',
      'true',
      projectIdStr,
    );
  }

  static Future<bool> hasSeenFirstVideo(String projectId) async {
    try {
      final String settingValueStr = await DB.instance.getSettingValueByTitle(
        'has_viewed_first_video',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasSeenFirstVideoToTrue(String projectIdStr) async {
    await DB.instance.setSettingByTitle(
      'has_viewed_first_video',
      'true',
      projectIdStr,
    );
  }

  static Future<bool> hasOpenedNotifPage(String projectId) async {
    try {
      final String settingValueStr = await DB.instance.getSettingValueByTitle(
        'has_opened_notif_page',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasOpenedNotifPageToTrue(String projectIdStr) async {
    await DB.instance.setSettingByTitle(
      'has_opened_notif_page',
      'true',
      projectIdStr,
    );
  }

  static Future<bool> hasSeenGuideModeTut(String projectId) async {
    try {
      final String settingValueStr = await DB.instance.getSettingValueByTitle(
        'has_seen_guide_mode_tut',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasSeenGuideModeTutToTrue(String projectIdStr) async {
    await DB.instance.setSettingByTitle(
      'has_seen_guide_mode_tut',
      'true',
      projectIdStr,
    );
  }

  static Future<int> loadGridAxisCount(String projectId) async {
    try {
      final String s = await DB.instance.getSettingValueByTitle(
        'gridAxisCount',
        projectId,
      );
      final int parsed = int.tryParse(s) ?? 4;
      final bool isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      final int maxSteps = isDesktop ? 12 : 6;
      return parsed.clamp(1, maxSteps);
    } catch (_) {
      return 4;
    }
  }

  /// Load gallery grid mode: 'auto' or 'manual'
  static Future<String> loadGalleryGridMode(String projectId) async {
    try {
      return await DB.instance.getSettingValueByTitle(
        'gallery_grid_mode',
        projectId,
      );
    } catch (_) {
      return 'auto';
    }
  }

  /// Save gallery grid mode
  static Future<void> setGalleryGridMode(String projectId, String mode) async {
    await DB.instance.setSettingByTitle('gallery_grid_mode', mode, projectId);
  }

  static Future<int> loadGridModeIndex(String projectId) async {
    final String gridModeIndexAsStr;
    gridModeIndexAsStr = await DB.instance.getSettingValueByTitle(
      'grid_mode_index',
      projectId,
    );
    return int.parse(gridModeIndexAsStr);
  }

  static Future<void> setGridModeIndex(
    String projectId,
    int gridModeIndex,
  ) async {
    await DB.instance.setSettingByTitle(
      'grid_mode_index',
      gridModeIndex.toString(),
      projectId,
    );
  }

  static Future<String> loadStabilizationMode() async {
    try {
      return await DB.instance.getSettingValueByTitle('stabilization_mode');
    } catch (e) {
      return 'slow';
    }
  }

  static Future<void> saveStabilizationMode(String mode) async {
    await DB.instance.setSettingByTitle('stabilization_mode', mode);
  }

  // ==================== Background Color ====================

  /// Default background color for stabilization (black)
  static const String fallbackBackgroundColor = '#000000';

  /// Load background color setting (per-project).
  /// Returns hex string like '#FF0000' for red.
  static Future<String> loadBackgroundColor(String projectId) async {
    try {
      final value = await DB.instance.getSettingValueByTitle(
        'background_color',
        projectId,
      );
      // Validate hex format
      if (value.startsWith('#') && (value.length == 7 || value.length == 9)) {
        return value.toUpperCase();
      }
      return fallbackBackgroundColor;
    } catch (e) {
      return fallbackBackgroundColor;
    }
  }

  /// Save background color setting (per-project).
  /// Expects hex string like '#FF0000' for red.
  static Future<void> saveBackgroundColor(
    String projectId,
    String hexColor,
  ) async {
    await DB.instance.setSettingByTitle(
      'background_color',
      hexColor.toUpperCase(),
      projectId,
    );
  }

  // ==================== Camera Timer ====================

  /// Load camera timer duration (per-project): 0 = off, 3 = 3s, 10 = 10s
  static Future<int> loadCameraTimer(String projectId) async {
    try {
      String timerValue = await DB.instance.getSettingValueByTitle(
        'camera_timer_duration',
        projectId,
      );
      return int.tryParse(timerValue) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ==================== Date Stamp Settings ====================

  /// Load whether gallery date labels are enabled for stabilized thumbnails (per-project)
  static Future<bool> loadGalleryDateLabelsEnabled(String projectId) async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'gallery_date_labels_enabled',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Load whether gallery date labels are enabled for raw thumbnails (per-project)
  static Future<bool> loadGalleryRawDateLabelsEnabled(String projectId) async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'gallery_raw_date_labels_enabled',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Load gallery date format (per-project)
  static Future<String> loadGalleryDateFormat(String projectId) async {
    try {
      String format = await DB.instance.getSettingValueByTitle(
        'gallery_date_format',
        projectId,
      );
      return format.isNotEmpty ? format : fallbackGalleryDateFormat;
    } catch (e) {
      return fallbackGalleryDateFormat;
    }
  }

  /// Load whether export date stamp is enabled (per-project)
  static Future<bool> loadExportDateStampEnabled(String projectId) async {
    try {
      String settingValueStr = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_enabled',
        projectId,
      );
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Load export date stamp position (per-project)
  static Future<String> loadExportDateStampPosition(String projectId) async {
    try {
      String position = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_position',
        projectId,
      );
      return position.isNotEmpty ? position : fallbackDateStampPosition;
    } catch (e) {
      return fallbackDateStampPosition;
    }
  }

  /// Load export date stamp format (per-project)
  static Future<String> loadExportDateStampFormat(String projectId) async {
    try {
      String format = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_format',
        projectId,
      );
      return format.isNotEmpty ? format : fallbackExportDateFormat;
    } catch (e) {
      return fallbackExportDateFormat;
    }
  }

  /// Load export date stamp size percentage (per-project)
  static Future<int> loadExportDateStampSize(String projectId) async {
    try {
      String sizeStr = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_size',
        projectId,
      );
      return int.tryParse(sizeStr) ?? fallbackDateStampSizePercent;
    } catch (e) {
      return fallbackDateStampSizePercent;
    }
  }

  /// Load export date stamp opacity (per-project)
  static Future<double> loadExportDateStampOpacity(String projectId) async {
    try {
      String opacityStr = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_opacity',
        projectId,
      );
      return double.tryParse(opacityStr) ?? 1.0;
    } catch (e) {
      return 1.0;
    }
  }

  /// Load gallery date stamp font (per-project)
  /// Validates that the font exists (bundled or custom) and returns default if not.
  static Future<String> loadGalleryDateStampFont(String projectId) async {
    try {
      String font = await DB.instance.getSettingValueByTitle(
        'gallery_date_stamp_font',
        projectId,
      );

      if (font.isEmpty) {
        return DateStampUtils.defaultFont;
      }

      // Check if it's a bundled font
      if (DateStampUtils.isBundledFont(font)) {
        return font;
      }

      // Check if it's a custom font that still exists
      if (DateStampUtils.isCustomFont(font)) {
        final isAvailable =
            await CustomFontManager.instance.isFontAvailable(font);
        if (isAvailable) {
          return font;
        }
        // Custom font no longer exists, reset to default
        LogService.instance
            .log('Custom font $font no longer available, using default');
        await DB.instance.setSettingByTitle(
          'gallery_date_stamp_font',
          DateStampUtils.defaultFont,
          projectId,
        );
        return DateStampUtils.defaultFont;
      }

      return DateStampUtils.defaultFont;
    } catch (e) {
      return DateStampUtils.defaultFont;
    }
  }

  /// Load export date stamp font (per-project)
  /// Returns "_same_as_gallery" or a specific font name
  /// Validates that custom fonts still exist.
  static Future<String> loadExportDateStampFont(String projectId) async {
    try {
      String font = await DB.instance.getSettingValueByTitle(
        'export_date_stamp_font',
        projectId,
      );

      if (font.isEmpty) {
        return DateStampUtils.fontSameAsGallery;
      }

      // Check special values
      if (font == DateStampUtils.fontSameAsGallery) {
        return font;
      }

      // Check if it's a bundled font
      if (DateStampUtils.isBundledFont(font)) {
        return font;
      }

      // Check if it's a custom font that still exists
      if (DateStampUtils.isCustomFont(font)) {
        final isAvailable =
            await CustomFontManager.instance.isFontAvailable(font);
        if (isAvailable) {
          return font;
        }
        // Custom font no longer exists, reset to "same as gallery"
        LogService.instance.log(
            'Custom font $font no longer available, using same as gallery');
        await DB.instance.setSettingByTitle(
          'export_date_stamp_font',
          DateStampUtils.fontSameAsGallery,
          projectId,
        );
        return DateStampUtils.fontSameAsGallery;
      }

      return DateStampUtils.fontSameAsGallery;
    } catch (e) {
      return DateStampUtils.fontSameAsGallery;
    }
  }

  /// Save gallery date stamp font (per-project)
  static Future<void> setGalleryDateStampFont(
      String projectId, String font) async {
    await DB.instance
        .setSettingByTitle('gallery_date_stamp_font', font, projectId);
  }

  /// Save export date stamp font (per-project)
  static Future<void> setExportDateStampFont(
      String projectId, String font) async {
    await DB.instance
        .setSettingByTitle('export_date_stamp_font', font, projectId);
  }

  /// Load all date stamp settings at once for efficiency
  static Future<DateStampSettings> loadAllDateStampSettings(
    String projectId,
  ) async {
    final results = await Future.wait([
      loadGalleryDateLabelsEnabled(projectId),
      loadGalleryRawDateLabelsEnabled(projectId),
      loadGalleryDateFormat(projectId),
      loadExportDateStampEnabled(projectId),
      loadExportDateStampPosition(projectId),
      loadExportDateStampFormat(projectId),
      loadExportDateStampSize(projectId),
      loadExportDateStampOpacity(projectId),
      loadGalleryDateStampFont(projectId),
      loadExportDateStampFont(projectId),
    ]);

    return DateStampSettings(
      galleryLabelsEnabled: results[0] as bool,
      galleryRawLabelsEnabled: results[1] as bool,
      galleryFormat: results[2] as String,
      exportEnabled: results[3] as bool,
      exportPosition: results[4] as String,
      exportFormat: results[5] as String,
      exportSizePercent: results[6] as int,
      exportOpacity: results[7] as double,
      galleryFont: results[8] as String,
      exportFont: results[9] as String,
    );
  }
}

/// Data class to hold all date stamp settings
class DateStampSettings {
  final bool galleryLabelsEnabled;
  final bool galleryRawLabelsEnabled;
  final String galleryFormat;
  final bool exportEnabled;
  final String exportPosition;
  final String exportFormat;
  final int exportSizePercent;
  final double exportOpacity;
  final String galleryFont;
  final String exportFont;

  const DateStampSettings({
    required this.galleryLabelsEnabled,
    required this.galleryRawLabelsEnabled,
    required this.galleryFormat,
    required this.exportEnabled,
    required this.exportPosition,
    required this.exportFormat,
    required this.exportSizePercent,
    required this.exportOpacity,
    required this.galleryFont,
    required this.exportFont,
  });

  /// Get resolved export font (handles "same as gallery" logic)
  String get resolvedExportFont =>
      DateStampUtils.resolveExportFont(exportFont, galleryFont);

  /// Default settings
  static const DateStampSettings defaults = DateStampSettings(
    galleryLabelsEnabled: false,
    galleryRawLabelsEnabled: false,
    galleryFormat: DateStampUtils.galleryFormatMMYY,
    exportEnabled: false,
    exportPosition: DateStampUtils.positionLowerRight,
    exportFormat: DateStampUtils.exportFormatLong,
    exportSizePercent: 3,
    exportOpacity: 1.0,
    galleryFont: DateStampUtils.defaultFont,
    exportFont: DateStampUtils.fontSameAsGallery,
  );
}
