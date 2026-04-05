import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'dart:ui' as ui;

import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/log_service.dart';
import '../services/stabilization_service.dart';
import '../services/thumbnail_service.dart';
import 'dir_utils.dart';
import 'linked_source_utils.dart';
import 'notification_util.dart';
import 'capture_timezone.dart';
import 'utils.dart';

class ProjectUtils {
  static Future<int?> calculateStreak(int projectId) async {
    final photos = await DB.instance.getPhotosByProjectIDNewestFirst(projectId);
    if (photos.isEmpty) return 0;
    final streak = _calculatePhotoStreak(photos);
    LogService.instance.log(
      '[Streak] projectId=$projectId photos=${photos.length} result=$streak',
    );
    return streak;
  }

  /// Returns the difference in whole calendar days, ignoring DST hour shifts.
  static int getTimeDiff(DateTime startTime, DateTime endTime) {
    final DateTime startDay = _dateOnlyUtc(startTime);
    final DateTime endDay = _dateOnlyUtc(endTime);
    return endDay.difference(startDay).inDays;
  }

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
  /// This includes: database records (Photos, Videos, Settings, Project),
  /// notifications, and all project files.
  static Future<void> deleteProject(int projectId) async {
    // 1. Cancel any active stabilization FIRST (prevents race condition/crash)
    await StabilizationService.instance.cancelAndWait();

    // 2. Clear caches for this project
    ThumbnailService.instance.clearAllCache();
    Utils.clearFlutterImageCache();

    // 3. Reset default project if this was the default (before cascade delete)
    final String defaultProject = await DB.instance.getSettingValueByTitle(
      'default_project',
    );
    if (defaultProject == projectId.toString()) {
      await DB.instance.setSettingByTitle('default_project', 'none');
    }

    // 4. Delete all database records (Photos, Videos, Settings, Project) atomically
    final bool dbSuccess = await DB.instance.deleteProjectCascade(projectId);
    if (dbSuccess) {
      await NotificationUtil.cancelNotification(projectId);
    }

    // 5. Delete project directory and all files (now safe - stabilization stopped)
    // Done AFTER DB deletion so if this fails, at least DB is clean.
    // Orphaned files are less problematic than orphaned DB records.
    final String projectDirPath = await DirUtils.getProjectDirPath(projectId);
    try {
      await DirUtils.deleteDirectoryContents(Directory(projectDirPath));
      final projectDir = Directory(projectDirPath);
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
    } catch (e) {
      LogService.instance.log('Failed to delete project directory: $e');
      // Non-fatal: orphaned files will be ignored
    }
  }

  static Future<void> deleteFile(File file) async => await file.delete();

  static Future<bool> deleteImage(File image, int projectId) async {
    // Query original file info BEFORE deleting from DB
    final String timestamp = path.basenameWithoutExtension(image.path);
    Map<String, dynamic>? originalInfo;
    try {
      originalInfo = await DB.instance.getOriginalInfoByTimestamp(
        timestamp,
        projectId,
      );
    } catch (_) {}

    // Delete from database FIRST - this is the source of truth.
    // If DB deletion fails, return false so the image stays in the gallery
    // and the user can retry the deletion.
    try {
      final int rowsDeleted = await deletePhotoFromDatabaseAndReturnCount(
        image.path,
        projectId,
      );
      if (rowsDeleted == 0) {
        LogService.instance.log(
          "Failed to delete image from database (no rows affected): ${image.path}",
        );
        return false;
      }
    } catch (e) {
      LogService.instance.log(
        "Failed to delete image from database: ${image.path}, Error: $e",
      );
      return false;
    }

    // DB deletion succeeded. Now try to delete files.
    // If file deletion fails, that's OK - orphaned files will be cleaned up
    // during video export when we validate against the database.

    // Delete raw thumbnail
    try {
      final String thumbnailDir = await DirUtils.getThumbnailDirPath(projectId);
      final String rawThumbPath = path.join(thumbnailDir, '$timestamp.jpg');
      await DirUtils.deleteFileIfExists(rawThumbPath);
    } catch (e) {
      LogService.instance.log(
        "Failed to delete raw thumbnail (will be cleaned up later): ${image.path}, Error: $e",
      );
    }

    try {
      await deleteStabilizedFileIfExists(image, projectId);
    } catch (e) {
      LogService.instance.log(
        "Failed to delete stabilized files (will be cleaned up later): ${image.path}, Error: $e",
      );
    }

    // Delete stabilized thumbnails (both orientations)
    try {
      final String stabDirPath = await DirUtils.getStabilizedDirPath(projectId);
      for (final orientation in DirUtils.orientations) {
        final String stabPath = path.join(
          stabDirPath,
          orientation,
          '$timestamp.png',
        );
        final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(
          stabPath,
        );
        await DirUtils.deleteFileIfExists(stabThumbPath);
      }
    } catch (e) {
      LogService.instance.log(
        "Failed to delete stabilized thumbnails (will be cleaned up later): ${image.path}, Error: $e",
      );
    }

    try {
      await deleteFile(image);
    } catch (e) {
      LogService.instance.log(
        "Failed to delete raw image file (will be cleaned up later): ${image.path}, Error: $e",
      );
    }

    final sourceLocationType = originalInfo?['sourceLocationType'] as String?;
    final sourceRelativePath = originalInfo?['sourceRelativePath'] as String?;

    // For direct_import photos with a known source path, delete the source file.
    if (sourceLocationType == 'direct_import' &&
        sourceRelativePath != null &&
        sourceRelativePath.trim().isNotEmpty) {
      try {
        final linkedConfig = await LinkedSourceUtils.loadConfig(projectId);
        if (linkedConfig.hasUsableDesktopRoot) {
          final externalPath = path.normalize(
            path.join(linkedConfig.rootPath, sourceRelativePath),
          );
          if (!path.isWithin(linkedConfig.rootPath, externalPath)) {
            LogService.instance.log(
              "Blocked external file deletion outside linked root: $externalPath",
            );
          } else {
            try {
              final File externalFile = File(externalPath);
              if (await externalFile.exists()) {
                await externalFile.delete();
                LogService.instance.log(
                  "Deleted linked source file: $externalPath",
                );
              }
            } catch (e) {
              LogService.instance.log(
                "Failed to delete linked source file $externalPath: $e",
              );
            }
          }
        }
      } catch (e) {
        LogService.instance.log(
          "Failed to delete linked source file (non-fatal): $e",
        );
      }
    }

    // For external_linked photos, record a tombstone so the sync service
    // does not reimport this file the next time the folder is scanned.
    if (sourceLocationType == 'external_linked' &&
        sourceRelativePath != null &&
        sourceRelativePath.trim().isNotEmpty) {
      try {
        await DB.instance.insertDeletedLinkedSource(
          projectId,
          sourceRelativePath,
        );
      } catch (e) {
        LogService.instance.log(
          "Failed to insert deleted linked source tombstone (non-fatal): $e",
        );
      }
    }

    return true;
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
    File image,
    int projectId,
  ) async {
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(
      projectId,
    );

    for (final orientation in DirUtils.orientations) {
      final stabPath = DirUtils.buildStabilizedImagePath(
        stabilizedDirPath,
        orientation,
        image.path,
      );
      await DirUtils.deleteFileIfExists(stabPath);
    }
  }

  static Future<void> deletePhotoFromDatabase(
    String filePath,
    int projectId,
  ) async {
    final timestamp = parseTimestampFromFilename(filePath);
    await DB.instance.deletePhoto(timestamp, projectId);
  }

  static Future<int> deletePhotoFromDatabaseAndReturnCount(
    String filePath,
    int projectId,
  ) async {
    final timestamp = parseTimestampFromFilename(filePath);
    return await DB.instance.deletePhoto(timestamp, projectId);
  }

  /// Returns unique photo dates in descending order (newest first).
  ///
  /// PRECONDITION: [photos] must be sorted by timestamp descending
  /// (as returned by [DB.getPhotosByProjectIDNewestFirst]).
  ///
  /// Complexity: O(n) time, O(unique_days) space - avoids O(d log d) sort
  /// by preserving encounter order from pre-sorted input.
  static List<String> getUniquePhotoDates(List<Map<String, dynamic>> photos) {
    final uniqueDays = _getUniquePhotoDays(photos);
    return uniqueDays
        .map((d) => DateTime(d.year, d.month, d.day).toString())
        .toList();
  }

  @visibleForTesting
  static int calculatePhotoStreakFromPhotos(
    List<Map<String, dynamic>> photos, {
    DateTime? now,
  }) {
    return _calculatePhotoStreak(photos, now: now);
  }

  @visibleForTesting
  static bool photoWasTakenTodayForPhotos(
    List<Map<String, dynamic>> photos, {
    DateTime? now,
  }) {
    final DateTime today = _dateOnlyUtc(now ?? DateTime.now());
    return photos.any((photo) => _photoCaptureDayUtc(photo) == today);
  }

  static List<DateTime> _getUniquePhotoDays(List<Map<String, dynamic>> photos) {
    if (photos.isEmpty) return [];

    // Debug assertion to catch misuse - validates descending timestamp order
    assert(() {
      for (int i = 1; i < photos.length; i++) {
        final prev = _parsePhotoTimestamp(photos[i - 1]);
        final curr = _parsePhotoTimestamp(photos[i]);
        if (curr > prev) {
          throw StateError(
            'getUniquePhotoDates requires timestamp-descending input. '
            'Found timestamp $curr after $prev at index $i.',
          );
        }
      }
      return true;
    }());

    final List<DateTime> days = [];
    DateTime? lastDay;

    for (final photo in photos) {
      final DateTime dayOnly = _photoCaptureDayUtc(photo);

      // Only add if different from last day (preserves descending order)
      if (lastDay == null || dayOnly != lastDay) {
        days.add(dayOnly);
        lastDay = dayOnly;
      }
    }

    return days;
  }

  static int _calculatePhotoStreak(
    List<Map<String, dynamic>> photos, {
    DateTime? now,
  }) {
    final List<DateTime> uniqueDates = _getUniquePhotoDays(photos);
    if (uniqueDates.isEmpty) return 0;

    int streak = 1;

    final DateTime latestPhotoDate = uniqueDates[0];
    final DateTime todayLocalLike = _dateOnlyUtc(now ?? DateTime.now());
    final int headDiff = getTimeDiff(latestPhotoDate, todayLocalLike);

    // Log all unique days so we can diagnose gaps anywhere in the streak
    final allDays = uniqueDates.map((d) => d.toIso8601String()).toList();
    LogService.instance.log(
      '[Streak] today=$todayLocalLike latest=$latestPhotoDate headDiff=$headDiff '
      'deviceOffset=${DateTime.now().timeZoneOffset.inMinutes}min '
      'uniqueDays=${uniqueDates.length} days=$allDays',
    );

    if (headDiff > 1) {
      LogService.instance.log('[Streak] headDiff>1, returning 0');
      return 0;
    }

    for (int i = 1; i < uniqueDates.length; i++) {
      final DateTime currentDate = uniqueDates[i];
      final DateTime previousDate = uniqueDates[i - 1];

      final int diff = getTimeDiff(currentDate, previousDate);
      if (diff != 1) {
        // Log raw photo data around the gap for diagnosis
        _logPhotosAroundGap(photos, previousDate, currentDate);
        LogService.instance.log(
          '[Streak] gap at i=$i: $currentDate→$previousDate diff=$diff, '
          'returning streak=$streak',
        );
        return streak;
      }
      streak++;
    }

    return streak;
  }

  /// Logs raw timestamps and offsets for photos on the two days surrounding
  /// a streak gap, so we can diagnose timezone/offset issues from exported logs.
  static void _logPhotosAroundGap(
    List<Map<String, dynamic>> photos,
    DateTime dayBefore,
    DateTime dayAfter,
  ) {
    for (final photo in photos) {
      final day = _photoCaptureDayUtc(photo);
      if (day == dayBefore || day == dayAfter) {
        final ts = _parsePhotoTimestamp(photo);
        final offset = CaptureTimezone.extractOffset(photo);
        LogService.instance.log(
          '[Streak] gap-adjacent photo: ts=$ts offset=$offset day=$day',
        );
      }
    }
  }

  static Future<ui.Image> loadImageData(String imagePath) async {
    final data = await rootBundle.load(imagePath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  static Future<bool> photoWasTakenToday(int projectId) async {
    final photos = await DB.instance.getPhotosByProjectID(projectId);
    return photoWasTakenTodayForPhotos(photos);
  }

  static int _parsePhotoTimestamp(Map<String, dynamic> photo) =>
      int.tryParse(photo['timestamp']?.toString() ?? '0') ?? 0;

  static DateTime _photoCaptureDayUtc(Map<String, dynamic> photo) {
    final int ts = _parsePhotoTimestamp(photo);
    final int? offsetMin = CaptureTimezone.extractOffset(photo);
    final DateTime localLike = CaptureTimezone.toLocalDateTime(
      ts,
      offsetMinutes: offsetMin,
    );
    return _dateOnlyUtc(localLike);
  }

  static DateTime _dateOnlyUtc(DateTime dateTime) =>
      DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
}
