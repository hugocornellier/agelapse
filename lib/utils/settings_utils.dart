import '../models/video_background.dart';
import '../models/video_codec.dart';
import '../services/custom_font_manager.dart';
import '../services/log_service.dart';
import '../utils/platform_utils.dart';
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
  static const int fallbackGallerySizeLevel =
      DateStampUtils.defaultGallerySizeLevel;
  static const String fallbackDateStampOpacity = '1.0';
  static const int fallbackDateStampMargin = 2;
  static const double fallbackDateStampMarginH = 2.0;
  static const double fallbackDateStampMarginV = 2.0;

  static Future<String> loadTheme() async {
    return await DB.instance.getSettingValueByTitle('theme');
  }

  static Future<bool> loadFramerateIsDefault(String projectId) async =>
      _loadBoolSetting('framerate_is_default', projectId, true);

  static Future<bool> loadCameraMirror(String projectId) async =>
      _loadBoolSetting('camera_mirror', projectId, false);

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

  static Future<bool> loadEnableGrid() async =>
      _loadBoolSetting('enable_grid', null, false);

  static Future<String> loadCameraFlash(String projectId) async =>
      _loadStringSetting('camera_flash', projectId, "auto");

  static Future<bool> loadSaveToCameraRoll() =>
      _loadBoolSetting('save_to_camera_roll', null, false);

  static Future<bool> loadWatermarkSetting(String projectId) async =>
      _loadBoolSetting('enable_watermark', projectId, false);

  static Future<bool> loadNotificationSetting() async =>
      _loadBoolSetting('enable_notifications', null, true);

  static Future<String> loadWatermarkPosition() async {
    try {
      return Utils.capitalizeFirstLetter(
        await DB.instance.getSettingValueByTitle('watermark_position'),
      );
    } catch (e) {
      return fallbackWatermarkPosition;
    }
  }

  static Future<String> loadWatermarkOpacity() async =>
      _loadStringSetting('watermark_opacity', null, fallbackWatermarkOpacity);

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
  static Future<bool> loadAutoCompileVideo(String projectId) async =>
      _loadBoolSetting('auto_compile_video', projectId, true);

  /// Save auto-compile video setting (per-project).
  static Future<void> setAutoCompileVideo(
    String projectId,
    bool enabled,
  ) async {
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
  ) async =>
      _loadOffsetAxis(projectId, axis, 'eye', null);

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
  ) async =>
      _loadOffsetAxis(projectId, axis, 'guide', null);

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
  ) async =>
      _loadOffsetAxis(projectId, axis, 'guide', customOrientation);

  static Future<bool> hasOpenedNonEmptyGallery(String projectId) async =>
      _loadBoolSetting('opened_nonempty_gallery', projectId, false);

  static Future<void> setHasOpenedNonEmptyGalleryToTrue(
          String projectIdStr) async =>
      _setBoolToTrue('opened_nonempty_gallery', projectIdStr);

  static Future<bool> hasTakenFirstPhoto(String projectId) async =>
      _loadBoolSetting('has_taken_first_photo', projectId, false);

  static Future<void> setHasTakenFirstPhotoToTrue(String projectIdStr) async =>
      _setBoolToTrue('has_taken_first_photo', projectIdStr);

  static Future<bool> hasSeenFirstVideo(String projectId) async =>
      _loadBoolSetting('has_viewed_first_video', projectId, false);

  static Future<void> setHasSeenFirstVideoToTrue(String projectIdStr) async =>
      _setBoolToTrue('has_viewed_first_video', projectIdStr);

  static Future<bool> hasOpenedNotifPage(String projectId) async =>
      _loadBoolSetting('has_opened_notif_page', projectId, false);

  static Future<void> setHasOpenedNotifPageToTrue(String projectIdStr) async =>
      _setBoolToTrue('has_opened_notif_page', projectIdStr);

  static Future<bool> hasSeenGuideModeTut(String projectId) async =>
      _loadBoolSetting('has_seen_guide_mode_tut', projectId, false);

  static Future<void> setHasSeenGuideModeTutToTrue(String projectIdStr) async =>
      _setBoolToTrue('has_seen_guide_mode_tut', projectIdStr);

  static Future<int> loadGridAxisCount(String projectId) async {
    try {
      final String s = await DB.instance.getSettingValueByTitle(
        'gridAxisCount',
        projectId,
      );
      final int parsed = int.tryParse(s) ?? 4;
      final int maxSteps = isDesktop ? 12 : 6;
      return parsed.clamp(1, maxSteps);
    } catch (_) {
      return 4;
    }
  }

  /// Load gallery grid mode: 'auto' or 'manual'
  static Future<String> loadGalleryGridMode(String projectId) async =>
      _loadStringSetting('gallery_grid_mode', projectId, 'auto');

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

  static Future<String> loadStabilizationMode() async =>
      _loadStringSetting('stabilization_mode', null, 'slow');

  static Future<void> saveStabilizationMode(String mode) async {
    await DB.instance.setSettingByTitle('stabilization_mode', mode);
  }

  // ==================== Background Color ====================

  /// Default background color for stabilization (black)
  static const String fallbackBackgroundColor = '#000000';

  /// Special value indicating transparent background
  static const String transparentBackgroundValue = '#TRANSPARENT';

  /// Check if the given color value represents a transparent background
  static bool isTransparent(String hexColor) =>
      hexColor.toUpperCase() == transparentBackgroundValue;

  /// Load background color setting (per-project).
  /// Returns hex string like '#FF0000' for red, or '#TRANSPARENT' for transparent.
  static Future<String> loadBackgroundColor(String projectId) async {
    try {
      final value = await DB.instance.getSettingValueByTitle(
        'background_color',
        projectId,
      );
      // Check for transparent value
      if (isTransparent(value)) {
        return transparentBackgroundValue;
      }
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

  // ==================== Lossless Storage ====================

  /// Load lossless storage setting (per-project).
  /// When enabled, stabilized frames preserve source bit depth (up to 16-bit).
  /// 'auto' resolves to true on desktop, false on mobile.
  static Future<bool> loadLosslessStorage(String projectId) async {
    try {
      final value = await DB.instance.getSettingValueByTitle(
        'lossless_storage',
        projectId,
      );
      if (value == 'auto') {
        return isDesktop;
      }
      return value.toLowerCase() == 'true';
    } catch (e) {
      return isDesktop;
    }
  }

  /// Save lossless storage setting (per-project).
  static Future<void> setLosslessStorage(String projectId, bool enabled) async {
    await DB.instance.setSettingByTitle(
      'lossless_storage',
      enabled.toString(),
      projectId,
    );
  }

  // ==================== Video Codec ====================

  /// Default codec setting value.
  static const String fallbackVideoCodec = 'h264';

  /// Load video codec setting (per-project).
  /// If the stored codec is not available on this platform, returns h264
  /// without overwriting the DB (preserves the setting for other platforms).
  static Future<VideoCodec> loadVideoCodec(String projectId) async {
    try {
      final value = await DB.instance.getSettingValueByTitle(
        'video_codec',
        projectId,
      );
      final codec = VideoCodec.fromString(value);
      if (!VideoCodec.availableCodecs(
        isTransparentVideo: false,
      ).contains(codec)) {
        return VideoCodec.h264;
      }
      return codec;
    } catch (e) {
      return VideoCodec.h264;
    }
  }

  /// Save video codec setting (per-project).
  static Future<void> saveVideoCodec(String projectId, VideoCodec codec) async {
    await DB.instance.setSettingByTitle('video_codec', codec.name, projectId);
  }

  // ==================== Video Background ====================

  /// Default video background setting value.
  static const String fallbackVideoBackground = 'TRANSPARENT';

  /// Load video background setting (per-project).
  /// Only relevant when stabilized PNGs have alpha channel.
  static Future<VideoBackground> loadVideoBackground(String projectId) async {
    try {
      final value = await DB.instance.getSettingValueByTitle(
        'video_background',
        projectId,
      );
      return VideoBackground.fromString(value);
    } catch (e) {
      return const VideoBackground.transparent();
    }
  }

  /// Save video background setting (per-project).
  static Future<void> saveVideoBackground(
    String projectId,
    VideoBackground videoBg,
  ) async {
    await DB.instance.setSettingByTitle(
      'video_background',
      videoBg.toDbValue(),
      projectId,
    );
  }

  // ==================== Camera Timer ====================

  /// Load camera timer duration (per-project): 0 = off, 3 = 3s, 10 = 10s
  static Future<int> loadCameraTimer(String projectId) =>
      _loadIntSetting('camera_timer_duration', projectId, 0);

  // ==================== Date Stamp Settings ====================

  /// Load whether gallery date labels are enabled for stabilized thumbnails (per-project)
  static Future<bool> loadGalleryDateLabelsEnabled(String projectId) async =>
      _loadBoolSetting('gallery_date_labels_enabled', projectId, false);

  /// Load whether gallery date labels are enabled for raw thumbnails (per-project)
  static Future<bool> loadGalleryRawDateLabelsEnabled(String projectId) async =>
      _loadBoolSetting('gallery_raw_date_labels_enabled', projectId, false);

  /// Load gallery date format (per-project)
  static Future<String> loadGalleryDateFormat(String projectId) async =>
      _loadNonEmptyStringSetting(
          'gallery_date_format', projectId, fallbackGalleryDateFormat);

  /// Load whether export date stamp is enabled (per-project)
  static Future<bool> loadExportDateStampEnabled(String projectId) async =>
      _loadBoolSetting('export_date_stamp_enabled', projectId, false);

  /// Load export date stamp position (per-project)
  static Future<String> loadExportDateStampPosition(String projectId) async =>
      _loadNonEmptyStringSetting(
          'export_date_stamp_position', projectId, fallbackDateStampPosition);

  /// Load export date stamp format (per-project)
  static Future<String> loadExportDateStampFormat(String projectId) async =>
      _loadNonEmptyStringSetting(
          'export_date_stamp_format', projectId, fallbackExportDateFormat);

  /// Load export date stamp size percentage (per-project)
  static Future<int> loadExportDateStampSize(String projectId) =>
      _loadIntSetting(
          'export_date_stamp_size', projectId, fallbackDateStampSizePercent);

  /// Load export date stamp opacity (per-project)
  static Future<double> loadExportDateStampOpacity(String projectId) =>
      _loadDoubleSetting('export_date_stamp_opacity', projectId, 1.0);

  /// Load gallery date stamp font (per-project)
  /// Validates that the font exists (bundled or custom) and returns default if not.
  static Future<String> loadGalleryDateStampFont(String projectId) =>
      _loadFontWithValidation(
        projectId,
        'gallery_date_stamp_font',
        DateStampUtils.defaultFont,
      );

  /// Load export date stamp font (per-project)
  /// Returns "_same_as_gallery" or a specific font name
  /// Validates that custom fonts still exist.
  static Future<String> loadExportDateStampFont(String projectId) =>
      _loadFontWithValidation(
        projectId,
        'export_date_stamp_font',
        DateStampUtils.fontSameAsGallery,
        extraSpecialValue: DateStampUtils.fontSameAsGallery,
      );

  /// Loads and validates a font setting from DB.
  /// Returns [defaultValue] if the font is missing, invalid, or unavailable.
  /// [extraSpecialValue] is returned directly if the DB value matches it
  /// (used for the export font's "same as gallery" token).
  static Future<String> _loadFontWithValidation(
    String projectId,
    String settingKey,
    String defaultValue, {
    String? extraSpecialValue,
  }) async {
    try {
      String font = await DB.instance.getSettingValueByTitle(
        settingKey,
        projectId,
      );

      if (font.isEmpty) return defaultValue;

      if (extraSpecialValue != null && font == extraSpecialValue) return font;

      if (DateStampUtils.isBundledFont(font)) return font;

      if (DateStampUtils.isCustomFont(font)) {
        final isAvailable = await CustomFontManager.instance.isFontAvailable(
          font,
        );
        if (isAvailable) return font;
        LogService.instance.log(
          'Custom font $font no longer available, resetting to $defaultValue',
        );
        await DB.instance
            .setSettingByTitle(settingKey, defaultValue, projectId);
        return defaultValue;
      }

      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Save gallery date stamp font (per-project)
  static Future<void> setGalleryDateStampFont(
    String projectId,
    String font,
  ) async {
    await DB.instance.setSettingByTitle(
      'gallery_date_stamp_font',
      font,
      projectId,
    );
  }

  /// Save export date stamp font (per-project)
  static Future<void> setExportDateStampFont(
    String projectId,
    String font,
  ) async {
    await DB.instance.setSettingByTitle(
      'export_date_stamp_font',
      font,
      projectId,
    );
  }

  /// Load gallery date stamp size level (per-project)
  static Future<int> loadGalleryDateStampSize(String projectId) async =>
      _loadIntSettingClamped(
        'gallery_date_stamp_size',
        projectId,
        fallbackGallerySizeLevel,
        1,
        6,
      );

  /// Load export date stamp margin percentage (per-project, 1-6)
  static Future<int> loadExportDateStampMargin(String projectId) =>
      _loadIntSettingClamped(
          'export_date_stamp_margin', projectId, fallbackDateStampMargin, 1, 6);

  /// Load custom export date stamp horizontal margin % (per-project)
  static Future<double> loadExportDateStampMarginH(String projectId) =>
      _loadDoubleSetting(
          'export_date_stamp_margin_h', projectId, fallbackDateStampMarginH);

  /// Load custom export date stamp vertical margin % (per-project)
  static Future<double> loadExportDateStampMarginV(String projectId) =>
      _loadDoubleSetting(
          'export_date_stamp_margin_v', projectId, fallbackDateStampMarginV);

  /// Resolve margin: preset (1-6) uses uniform %, custom (0) uses independent H/V.
  static (double h, double v) resolveMargin(
    int marginSetting,
    double customH,
    double customV,
  ) {
    if (marginSetting == DateStampUtils.marginCustom) {
      return (customH.clamp(0.5, 15.0), customV.clamp(0.5, 15.0));
    }
    final uniform = marginSetting.toDouble().clamp(1.0, 6.0);
    return (uniform, uniform);
  }

  /// Load resolved margin (convenience for callers that load directly from DB).
  static Future<(double h, double v)> loadResolvedMargin(
      String projectId) async {
    final results = await Future.wait([
      loadExportDateStampMargin(projectId),
      loadExportDateStampMarginH(projectId),
      loadExportDateStampMarginV(projectId),
    ]);
    return resolveMargin(
      results[0] as int,
      results[1] as double,
      results[2] as double,
    );
  }

  // ==================== Private Helpers ====================

  static Future<bool> _loadBoolSetting(
      String key, String? projectId, bool defaultValue) async {
    try {
      final s = await DB.instance.getSettingValueByTitle(key, projectId);
      return bool.tryParse(s) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<String> _loadStringSetting(
      String key, String? projectId, String defaultValue) async {
    try {
      return await DB.instance.getSettingValueByTitle(key, projectId);
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<String> _loadNonEmptyStringSetting(
      String key, String? projectId, String defaultValue) async {
    try {
      final s = await DB.instance.getSettingValueByTitle(key, projectId);
      return s.isNotEmpty ? s : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<void> _setBoolToTrue(String key, String projectIdStr) async {
    await DB.instance.setSettingByTitle(key, 'true', projectIdStr);
  }

  static Future<int> _loadIntSetting(
      String key, String? projectId, int defaultValue) async {
    try {
      final s = await DB.instance.getSettingValueByTitle(key, projectId);
      return int.tryParse(s) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<double> _loadDoubleSetting(
      String key, String? projectId, double defaultValue) async {
    try {
      final s = await DB.instance.getSettingValueByTitle(key, projectId);
      return double.tryParse(s) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<int> _loadIntSettingClamped(
      String key, String projectId, int defaultValue, int min, int max) async {
    try {
      final s = await DB.instance.getSettingValueByTitle(key, projectId);
      return (int.tryParse(s) ?? defaultValue).clamp(min, max);
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<String> _loadOffsetAxis(
    String projectId,
    String axis,
    String prefix,
    String? customOrientation,
  ) async {
    final String orientation =
        customOrientation ?? await loadProjectOrientation(projectId);
    final String colName = (orientation == 'landscape')
        ? "${prefix}Offset${axis}Landscape"
        : "${prefix}Offset${axis}Portrait";
    return await DB.instance
        .getSettingValueByTitle(colName, projectId.toString());
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
      loadGalleryDateStampSize(projectId),
      loadExportDateStampMargin(projectId),
      loadExportDateStampMarginH(projectId),
      loadExportDateStampMarginV(projectId),
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
      gallerySizeLevel: results[10] as int,
      exportMarginPercent: results[11] as int,
      exportMarginH: results[12] as double,
      exportMarginV: results[13] as double,
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
  final int gallerySizeLevel;
  final int exportMarginPercent;
  final double exportMarginH;
  final double exportMarginV;

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
    required this.gallerySizeLevel,
    required this.exportMarginPercent,
    required this.exportMarginH,
    required this.exportMarginV,
  });

  /// Get resolved export font (handles "same as gallery" logic)
  String get resolvedExportFont =>
      DateStampUtils.resolveExportFont(exportFont, galleryFont);

  /// Get resolved export size (handles "same as gallery" logic)
  int get resolvedExportSize =>
      DateStampUtils.resolveExportSize(exportSizePercent, gallerySizeLevel);

  /// Get resolved margin (handles preset vs custom).
  (double h, double v) get resolvedMargin => SettingsUtil.resolveMargin(
      exportMarginPercent, exportMarginH, exportMarginV);

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
    gallerySizeLevel: DateStampUtils.defaultGallerySizeLevel,
    exportMarginPercent: 2,
    exportMarginH: 2.0,
    exportMarginV: 2.0,
  );
}
