import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/utils.dart';

import '../services/database_helper.dart';

class SettingsUtil {
  static const String fallbackWatermarkPosition = "Lower left";
  static const int fallbackFramerate = 14;
  static const String fallbackWatermarkOpacity = '0.7';

  static Future<String> loadTheme() async {
    return await DB.instance.getSettingValueByTitle('theme');
  }

  static Future<bool> loadFramerateIsDefault(String projectId) async {
    try {
      String settingValueStr = await DB.instance
          .getSettingValueByTitle('framerate_is_default', projectId);
      return bool.tryParse(settingValueStr) ?? true;
    } catch (e) {
      debugPrint('Failed to load watermark setting: $e');
      return true;
    }
  }

  static Future<bool> loadCameraMirror(String projectId) async {
    final value =
        await DB.instance.getSettingValueByTitle('camera_mirror', projectId);
    return value.toLowerCase() == 'true';
  }

  static Future<bool> lightThemeActive() async {
    final String activeTheme = await loadTheme();
    return activeTheme == 'light';
  }

  static Future<String> loadDailyNotificationTime(String projectId) async {
    final String result = await DB.instance
        .getSettingValueByTitle('daily_notification_time', projectId);
    return result;
  }

  static Future<bool> loadEnableGrid() async {
    try {
      String enableGridValueStr =
          await DB.instance.getSettingValueByTitle('enable_grid');
      return bool.tryParse(enableGridValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<String> loadCameraFlash(String projectId) async {
    try {
      String cameraFlashValueStr =
          await DB.instance.getSettingValueByTitle('camera_flash', projectId);
      return cameraFlashValueStr;
    } catch (e) {
      return "auto";
    }
  }

  static Future<bool> loadSaveToCameraRoll() async {
    try {
      String saveToCameraRollStr =
          await DB.instance.getSettingValueByTitle('save_to_camera_roll');
      return bool.tryParse(saveToCameraRollStr) ?? false;
    } catch (e) {
      debugPrint('Failed to load watermark setting: $e');
      return false;
    }
  }

  static Future<bool> loadWatermarkSetting(String projectId) async {
    try {
      String settingValueStr = await DB.instance
          .getSettingValueByTitle('enable_watermark', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> loadNotificationSetting() async {
    try {
      String settingValueStr =
          await DB.instance.getSettingValueByTitle('enable_notifications');
      return bool.tryParse(settingValueStr) ?? true;
    } catch (e) {
      return true;
    }
  }

  static Future<String> loadWatermarkPosition() async {
    try {
      return Utils.capitalizeFirstLetter(
          await DB.instance.getSettingValueByTitle('watermark_position'));
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
    return await DB.instance
        .getSettingValueByTitle('video_resolution', projectId);
  }

  static Future<String> loadSelectedGuidePhoto(String projectId) async {
    return await DB.instance
        .getSettingValueByTitle('selected_guide_photo', projectId);
  }

  static Future<String> loadProjectOrientation(String projectId) async {
    return (await DB.instance
            .getSettingValueByTitle('project_orientation', projectId))
        .toLowerCase();
  }

  static Future<String> loadOffsetXCurrentOrientation(String projectId) async {
    return await _loadOffsetCurrentOrientation(projectId, 'X');
  }

  static Future<String> loadOffsetYCurrentOrientation(String projectId) async {
    return await _loadOffsetCurrentOrientation(projectId, 'Y');
  }

  static Future<String> _loadOffsetCurrentOrientation(
      String projectId, String axis) async {
    final String activeProjectOrientation =
        await loadProjectOrientation(projectId);
    final String offsetColName = (activeProjectOrientation == 'landscape')
        ? "eyeOffset${axis}Landscape"
        : "eyeOffset${axis}Portrait";
    return await DB.instance
        .getSettingValueByTitle(offsetColName, projectId.toString());
  }

  static Future<String> loadGuideOffsetXCurrentOrientation(
      String projectId) async {
    return await _loadGuideOffsetCurrentOrientation(projectId, 'X');
  }

  static Future<String> loadGuideOffsetYCurrentOrientation(
      String projectId) async {
    return await _loadGuideOffsetCurrentOrientation(projectId, 'Y');
  }

  static Future<String> _loadGuideOffsetCurrentOrientation(
      String projectId, String axis) async {
    final String activeProjectOrientation =
        await loadProjectOrientation(projectId);
    final String offsetColName = (activeProjectOrientation == 'landscape')
        ? "guideOffset${axis}Landscape"
        : "guideOffset${axis}Portrait";
    return await DB.instance
        .getSettingValueByTitle(offsetColName, projectId.toString());
  }

  static Future<String> loadGuideOffsetXCustomOrientation(
      String projectId, String customOrientation) async {
    return await _loadGuideOffsetCustomOrientation(
        projectId, 'X', customOrientation);
  }

  static Future<String> loadGuideOffsetYCustomOrientation(
      String projectId, String customOrientation) async {
    return await _loadGuideOffsetCustomOrientation(
        projectId, 'Y', customOrientation);
  }

  static Future<String> _loadGuideOffsetCustomOrientation(
      String projectId, String axis, String customOrientation) async {
    final String offsetColName = (customOrientation == 'landscape')
        ? "guideOffset${axis}Landscape"
        : "guideOffset${axis}Portrait";

    return await DB.instance
        .getSettingValueByTitle(offsetColName, projectId.toString());
  }

  static Future<bool> hasOpenedNonEmptyGallery(String projectId) async {
    try {
      final String settingValueStr = await DB.instance
          .getSettingValueByTitle('opened_nonempty_gallery', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasOpenedNonEmptyGalleryToTrue(
      String projectIdStr) async {
    await DB.instance
        .setSettingByTitle('opened_nonempty_gallery', 'true', projectIdStr);
  }

  static Future<bool> hasTakenFirstPhoto(String projectId) async {
    try {
      final String settingValueStr = await DB.instance
          .getSettingValueByTitle('has_taken_first_photo', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasTakenFirstPhotoToTrue(String projectIdStr) async {
    await DB.instance
        .setSettingByTitle('has_taken_first_photo', 'true', projectIdStr);
  }

  static Future<bool> hasSeenFirstVideo(String projectId) async {
    try {
      final String settingValueStr = await DB.instance
          .getSettingValueByTitle('has_viewed_first_video', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasSeenFirstVideoToTrue(String projectIdStr) async {
    await DB.instance
        .setSettingByTitle('has_viewed_first_video', 'true', projectIdStr);
  }

  static Future<bool> hasOpenedNotifPage(String projectId) async {
    try {
      final String settingValueStr = await DB.instance
          .getSettingValueByTitle('has_opened_notif_page', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasOpenedNotifPageToTrue(String projectIdStr) async {
    await DB.instance
        .setSettingByTitle('has_opened_notif_page', 'true', projectIdStr);
  }

  static Future<bool> hasSeenGuideModeTut(String projectId) async {
    try {
      final String settingValueStr = await DB.instance
          .getSettingValueByTitle('has_seen_guide_mode_tut', projectId);
      return bool.tryParse(settingValueStr) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setHasSeenGuideModeTutToTrue(String projectIdStr) async {
    await DB.instance
        .setSettingByTitle('has_seen_guide_mode_tut', 'true', projectIdStr);
  }

  static Future<int> loadGridAxisCount(String projectId) async {
    try {
      final String s =
          await DB.instance.getSettingValueByTitle('gridAxisCount', projectId);
      final int parsed = int.tryParse(s) ?? 4;
      final bool isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      final int maxSteps = isDesktop ? 12 : 5;
      return parsed.clamp(1, maxSteps);
    } catch (_) {
      return 4;
    }
  }

  static Future<int> loadGridModeIndex(String projectId) async {
    final String gridModeIndexAsStr;
    gridModeIndexAsStr =
        await DB.instance.getSettingValueByTitle('grid_mode_index', projectId);
    return int.parse(gridModeIndexAsStr);
  }

  static Future<void> setGridModeIndex(
      String projectId, int gridModeIndex) async {
    await DB.instance.setSettingByTitle(
        'grid_mode_index', gridModeIndex.toString(), projectId);
  }

  static Future<String> loadStabilizationMode() async {
    try {
      return await DB.instance.getSettingValueByTitle('stabilization_mode');
    } catch (e) {
      return 'fast';
    }
  }

  static Future<void> saveStabilizationMode(String mode) async {
    await DB.instance.setSettingByTitle('stabilization_mode', mode);
  }
}
