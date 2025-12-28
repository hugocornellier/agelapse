import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';

import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../utils/dir_utils.dart';
import '../utils/project_utils.dart';
import '../utils/settings_utils.dart';
import 'stabilizer_utils/stabilizer_utils.dart';

class OutputImageLoader {
  final int projectId;
  String? projectOrientation;
  String? aspectRatio;
  double offsetX = 0.0;
  double offsetY = 0.0;
  double? ghostImageOffsetX;
  double? ghostImageOffsetY;
  ui.Image? guideImage;

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

    // Load placeholder
    guideImage = await ProjectUtils.loadImage('assets/images/person-grey.png');
    ghostImageOffsetX = 0.105;
    ghostImageOffsetY = 0.241;

    // Reload settings to get new orientation-specific offsets
    await _loadSettings();
  }

  /// Attempt to load a real stabilized guide image for current settings.
  ///
  /// Returns `true` if a new image was loaded, `false` if no image available
  /// or already showing the correct image. Safe to call repeatedly.
  Future<bool> tryLoadRealGuideImage() async {
    try {
      final Map<String, Object?>? guidePhoto =
          await DirUtils.getGuidePhoto(offsetX, projectId);

      if (guidePhoto == null) {
        // No stabilized image available for current orientation/offset
        return false;
      }

      final String guideImagePath =
          await DirUtils.getGuideImagePath(projectId, guidePhoto);

      // Check if file exists
      final file = File(guideImagePath);
      if (!await file.exists()) {
        return false;
      }

      // Get offset data from the photo
      final stabilizedColumn =
          DB.instance.getStabilizedColumn(projectOrientation!);
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

    projectOrientation =
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(projectId.toString());

    offsetX = double.parse(offsetXSettingVal);
    offsetY = double.parse(offsetYSettingVal);
  }

  Future<void> _initializeImageDirectory() async {
    try {
      final Map<String, Object?>? guidePhoto =
          await DirUtils.getGuidePhoto(offsetX, projectId);
      final String guideImagePath =
          await DirUtils.getGuideImagePath(projectId, guidePhoto);

      if (guidePhoto != null) {
        final stabilizedColumn =
            DB.instance.getStabilizedColumn(projectOrientation!);
        final stabColOffsetX = "${stabilizedColumn}OffsetX";
        final stabColOffsetY = "${stabilizedColumn}OffsetY";

        // Use values directly from guidePhoto instead of making another DB query
        // (the old DB query didn't filter by projectID, causing cross-project data leakage)
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

        try {
          guideImage = await StabUtils.loadImageFromFile(File(guideImagePath));
        } catch (e) {
          LogService.instance
              .log("Error caught $e, setting ghostImage to persongrey");
          guideImage =
              await ProjectUtils.loadImage('assets/images/person-grey.png');
          ghostImageOffsetX = 0.105;
          ghostImageOffsetY = 0.241;
        }
      } else {
        guideImage =
            await ProjectUtils.loadImage('assets/images/person-grey.png');
        ghostImageOffsetX = 0.105;
        ghostImageOffsetY = 0.241;
      }
    } catch (e) {
      debugPrint('Failed to initialize image directory: $e');
    }
  }
}
