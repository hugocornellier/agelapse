import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'dart:ui' as ui;

import '../services/database_helper.dart';
import '../services/log_service.dart';
import 'dir_utils.dart';
import 'notification_util.dart';

class ProjectUtils {
  static Future<int?> calculateStreak(int projectId) async {
    final photos = await DB.instance.getPhotosByProjectIDNewestFirst(projectId);
    if (photos.isEmpty) return 0;
    return _calculatePhotoStreak(photos);
  }

  static String convertExtensionToPng(String path) =>
      path.replaceAll(RegExp(r'\.jpg$'), '.png');

  static int getTimeDiff(DateTime startTime, DateTime endTime) =>
      endTime.difference(startTime).inDays;

  static int parseTimestampFromFilename(String filepath) =>
      int.tryParse(path.basenameWithoutExtension(filepath)) ?? 0;

  static Future<bool> isDefaultProject(int projectId) async {
    final data = await DB.instance.getSettingByTitle('default_project');
    final defaultProject = data?['value'];

    if (defaultProject == null || defaultProject == "none") {
      return false;
    } else {
      return int.tryParse(defaultProject) == projectId;
    }
  }

  /// Deletes a project and all associated data.
  /// This includes: database record, notifications, and all project files.
  static Future<void> deleteProject(int projectId) async {
    // 1. Reset default project if this was the default
    final String defaultProject =
        await DB.instance.getSettingValueByTitle('default_project');
    if (defaultProject == projectId.toString()) {
      DB.instance.setSettingByTitle('default_project', 'none');
    }

    // 2. Delete from database
    final int result = await DB.instance.deleteProject(projectId);
    if (result > 0) {
      await NotificationUtil.cancelNotification(projectId);
    }

    // 3. Delete project directory and all files
    final String projectDirPath = await DirUtils.getProjectDirPath(projectId);
    await DirUtils.deleteDirectoryContents(Directory(projectDirPath));
  }

  static Future<void> deleteFile(File file) async => await file.delete();

  static Future<bool> deleteImage(File image, int projectId) async {
    // Delete from database FIRST - this is the source of truth.
    // If DB deletion fails, return false so the image stays in the gallery
    // and the user can retry the deletion.
    try {
      final int rowsDeleted =
          await deletePhotoFromDatabaseAndReturnCount(image.path);
      if (rowsDeleted == 0) {
        LogService.instance.log(
            "Failed to delete image from database (no rows affected): ${image.path}");
        return false;
      }
    } catch (e) {
      LogService.instance.log(
          "Failed to delete image from database: ${image.path}, Error: $e");
      return false;
    }

    // DB deletion succeeded. Now try to delete files.
    // If file deletion fails, that's OK - orphaned files will be cleaned up
    // during video export when we validate against the database.
    try {
      await deletePngFileIfExists(image);
    } catch (e) {
      LogService.instance.log(
          "Failed to delete PNG file (will be cleaned up later): ${image.path}, Error: $e");
    }

    try {
      await deleteStabilizedFileIfExists(image, projectId);
    } catch (e) {
      LogService.instance.log(
          "Failed to delete stabilized files (will be cleaned up later): ${image.path}, Error: $e");
    }

    try {
      await deleteFile(image);
    } catch (e) {
      LogService.instance.log(
          "Failed to delete raw image file (will be cleaned up later): ${image.path}, Error: $e");
    }

    return true;
  }

  static Future<void> deletePngFileIfExists(File image) async {
    if (image.path.endsWith('.jpg')) {
      String newPath = convertExtensionToPng(image.path);

      File newImage = File(newPath);
      if (await newImage.exists()) {
        await deleteFile(newImage);
      }
    }
  }

  static Future<ui.Image> loadImage(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  /// Loads an SVG asset and converts it to a ui.Image at the specified size.
  static Future<ui.Image> loadSvgImage(
    String assetPath, {
    required int width,
    required int height,
  }) async {
    final pictureInfo = await vg.loadPicture(SvgAssetLoader(assetPath), null);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Scale SVG to fit the target dimensions
    final scaleX = width / pictureInfo.size.width;
    final scaleY = height / pictureInfo.size.height;
    canvas.scale(scaleX, scaleY);
    canvas.drawPicture(pictureInfo.picture);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);

    pictureInfo.picture.dispose();
    return image;
  }

  static Duration calculateDateDifference(int startDate, int endDate) {
    final start = DateTime.fromMillisecondsSinceEpoch(startDate, isUtc: true);
    final end = DateTime.fromMillisecondsSinceEpoch(endDate, isUtc: true);
    return end.difference(start);
  }

  static Future<void> deleteStabilizedFileIfExists(
      File image, int projectId) async {
    final String stabilizedDirPath =
        await DirUtils.getStabilizedDirPath(projectId);
    final String stabilizedPngPath =
        "${path.basenameWithoutExtension(image.path)}.png";

    final String stabilizedImagePathPngPortrait =
        path.join(stabilizedDirPath, 'portrait', stabilizedPngPath);
    final String stabilizedImagePathPngLandscape =
        path.join(stabilizedDirPath, 'landscape', stabilizedPngPath);

    final File stabilizedImagePngPortrait =
        File(stabilizedImagePathPngPortrait);
    final File stabilizedImagePngLandscape =
        File(stabilizedImagePathPngLandscape);

    if (await stabilizedImagePngPortrait.exists()) {
      await deleteFile(stabilizedImagePngPortrait);
    }
    if (await stabilizedImagePngLandscape.exists()) {
      await deleteFile(stabilizedImagePngLandscape);
    }
  }

  static Future<void> deletePhotoFromDatabase(String path) async {
    final timestamp = parseTimestampFromFilename(path);
    await DB.instance.deletePhoto(timestamp);
  }

  static Future<int> deletePhotoFromDatabaseAndReturnCount(String path) async {
    final timestamp = parseTimestampFromFilename(path);
    return await DB.instance.deletePhoto(timestamp);
  }

  /// Returns unique photo dates in descending order (newest first).
  ///
  /// PRECONDITION: [photos] must be sorted by timestamp descending
  /// (as returned by [DB.getPhotosByProjectIDNewestFirst]).
  ///
  /// Complexity: O(n) time, O(unique_days) space - avoids O(d log d) sort
  /// by preserving encounter order from pre-sorted input.
  static List<String> getUniquePhotoDates(List<Map<String, dynamic>> photos) {
    if (photos.isEmpty) return [];

    // Debug assertion to catch misuse - validates descending timestamp order
    assert(() {
      for (int i = 1; i < photos.length; i++) {
        final prev = int.tryParse(photos[i - 1]['timestamp'] ?? '0') ?? 0;
        final curr = int.tryParse(photos[i]['timestamp'] ?? '0') ?? 0;
        if (curr > prev) {
          throw StateError(
              'getUniquePhotoDates requires timestamp-descending input. '
              'Found timestamp $curr after $prev at index $i.');
        }
      }
      return true;
    }());

    final List<DateTime> days = [];
    DateTime? lastDay;

    for (final photo in photos) {
      final int ts = int.tryParse(photo['timestamp'] ?? '0') ?? 0;
      final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      final int? offsetMin = photo['captureOffsetMinutes'] is int
          ? photo['captureOffsetMinutes'] as int
          : null;
      final DateTime localLike = offsetMin != null
          ? utc.add(Duration(minutes: offsetMin))
          : utc.toLocal();
      final DateTime dayOnly =
          DateTime(localLike.year, localLike.month, localLike.day);

      // Only add if different from last day (preserves descending order)
      if (lastDay == null || dayOnly != lastDay) {
        days.add(dayOnly);
        lastDay = dayOnly;
      }
    }

    return days.map((d) => d.toString()).toList();
  }

  static int _calculatePhotoStreak(List<Map<String, dynamic>> photos) {
    final List<String> uniqueDates = getUniquePhotoDates(photos);
    if (uniqueDates.isEmpty) return 0;

    int streak = 1;

    final DateTime latestPhotoDate = DateTime.parse(uniqueDates[0]);

    int? latestOffset;
    for (final p in photos) {
      final int ts = int.tryParse(p['timestamp'] ?? '0') ?? 0;
      final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      final int? off = p['captureOffsetMinutes'] is int
          ? p['captureOffsetMinutes'] as int
          : null;
      final DateTime captureLocal =
          off != null ? utc.add(Duration(minutes: off)) : utc.toLocal();
      final DateTime capDay =
          DateTime(captureLocal.year, captureLocal.month, captureLocal.day);
      if (capDay.year == latestPhotoDate.year &&
          capDay.month == latestPhotoDate.month &&
          capDay.day == latestPhotoDate.day) {
        latestOffset = off;
        break;
      }
    }

    DateTime nowRef;
    if (latestOffset != null) {
      final DateTime nowUtc = DateTime.now().toUtc();
      nowRef = nowUtc.add(Duration(minutes: latestOffset));
    } else {
      nowRef = DateTime.now();
    }
    final DateTime todayLocalLike =
        DateTime(nowRef.year, nowRef.month, nowRef.day);

    final int headDiff = getTimeDiff(latestPhotoDate, todayLocalLike);
    if (headDiff > 1) return 0;

    for (int i = 1; i < uniqueDates.length; i++) {
      final DateTime currentDate = DateTime.parse(uniqueDates[i]);
      final DateTime previousDate = DateTime.parse(uniqueDates[i - 1]);

      final int diff = getTimeDiff(currentDate, previousDate);
      if (diff != 1) {
        return streak;
      }
      streak++;
    }

    return streak;
  }

  static Future<ui.Image> loadImageData(String imagePath) async {
    final data = await rootBundle.load(imagePath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}
