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

  /// The relative path to write/remove as a linked-source tombstone for
  /// [originalInfo], or `null` when no tombstone is needed (non-linked source,
  /// missing path, or empty/whitespace path). Centralizes the
  /// `external_linked` + non-empty-path rule shared by [deleteImage],
  /// [restoreImage], and the rollback in [restoreImage].
  static String? _linkedSourceTombstonePath(
    Map<String, dynamic>? originalInfo,
  ) {
    if (originalInfo?['sourceLocationType'] != 'external_linked') return null;
    final raw = originalInfo?['sourceRelativePath'] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// Soft-deletes a photo: it disappears from the gallery and video pipeline
  /// but its row, files, and caches are kept so the user can restore it from
  /// Recently Deleted. Files are purged when the retention window expires
  /// (see [purgeExpiredDeletedImages]) or when the user picks
  /// "Delete Forever".
  ///
  /// **Source-file behaviour by type:**
  /// - `external_linked`: a tombstone is written to [deletedLinkedSourcesTable]
  ///   before the soft-delete so the sync service will not reimport the file.
  ///   The tombstone is removed again by [restoreImage] if the user restores.
  /// - `direct_import`: the external source file is NOT deleted at soft-delete
  ///   time. Deletion is deferred to [permanentlyDeleteImage]. If the user
  ///   re-imports the same file via the picker before the retention window
  ///   expires, the importer creates a fresh row (the soft-deleted row stays in
  ///   Recently Deleted until it ages out; fingerprint dedup is intentionally
  ///   skipped for picker imports to avoid confusing the user).
  ///
  /// The legacy hard-delete is preserved as [permanentlyDeleteImage] for
  /// callers that explicitly want it.
  static Future<bool> deleteImage(File image, int projectId) async {
    final String timestamp = path.basenameWithoutExtension(image.path);
    final int? parsedTs = int.tryParse(timestamp);
    if (parsedTs == null) {
      LogService.instance.log(
        "Failed to soft-delete: non-numeric timestamp in path ${image.path}",
      );
      return false;
    }

    Map<String, dynamic>? originalInfo;
    try {
      originalInfo = await DB.instance.getOriginalInfoByTimestamp(
        timestamp,
        projectId,
      );
    } catch (_) {}

    final String? linkedTombstonePath = _linkedSourceTombstonePath(
      originalInfo,
    );

    // Soft-delete and (for external_linked) tombstone insert are atomic in
    // [DB.softDeletePhoto] so the sync service can never observe a hidden
    // photo with a missing tombstone.
    try {
      final int rows = await DB.instance.softDeletePhoto(
        parsedTs,
        projectId,
        linkedSourceRelativePath: linkedTombstonePath,
      );
      if (rows == 0) {
        LogService.instance.log(
          "softDeletePhoto affected 0 rows: ${image.path}",
        );
        return false;
      }
    } catch (e) {
      LogService.instance.log(
        "Failed to soft-delete image: ${image.path}, Error: $e",
      );
      return false;
    }

    final rowId = originalInfo?['id'];
    if (rowId != null) {
      try {
        final guideSetting = await DB.instance.getSettingValueByTitle(
          'selected_guide_photo',
          projectId.toString(),
        );
        final guideId = int.tryParse(guideSetting);
        if (guideId != null && guideId == rowId) {
          await DB.instance.setSettingByTitle(
            'selected_guide_photo',
            'not set',
            projectId.toString(),
          );
        }
      } catch (e) {
        LogService.instance.log(
          "Failed to reset guide photo on soft-delete (non-fatal): $e",
        );
      }
    }

    // Mark the project's video stale so a subsequent stab/recompile cycle
    // rebuilds without the deleted frame. UI callers gate recompile on
    // `remaining >= 2`; the model layer must always set the flag so the
    // 2→1 transition (or any non-recompiling caller) doesn't leave a stale
    // video on disk.
    try {
      await DB.instance.setNewVideoNeeded(projectId);
    } catch (_) {}

    return true;
  }

  /// Restores a previously soft-deleted photo back to the active gallery.
  /// Invalidates any cached transform so the next video compile picks up
  /// the current settings, and marks the project's video as stale.
  ///
  /// Flips the soft-delete flag first, then verifies the raw file exists on
  /// disk. If the file is missing the DB update is rolled back via
  /// softDeletePhoto and [RestoreOutcome.rawFileMissing] is returned so
  /// callers can surface the error.
  ///
  /// [timestamp] is the photo's timestamp (ms-since-epoch as string).
  static Future<RestoreOutcome> restoreImage(
    String timestamp,
    int projectId,
  ) async {
    final int? parsedTs = int.tryParse(timestamp);
    if (parsedTs == null) return RestoreOutcome.dbFailure;

    Map<String, dynamic>? originalInfo;
    try {
      originalInfo = await DB.instance.getOriginalInfoByTimestamp(
        timestamp,
        projectId,
      );
    } catch (_) {}

    final String? fileExtension = originalInfo?['fileExtension'] as String?;
    final String? linkedTombstonePath = _linkedSourceTombstonePath(
      originalInfo,
    );
    final int? originalDeletedAt = originalInfo?['deletedAt'] as int?;

    try {
      final int rows = await DB.instance.restorePhotoFromTrash(
        parsedTs,
        projectId,
        linkedSourceRelativePath: linkedTombstonePath,
      );
      if (rows == 0) return RestoreOutcome.rowNotTrashed;
    } catch (e) {
      LogService.instance.log(
        "Failed to restore photo $timestamp in project $projectId: $e",
      );
      return RestoreOutcome.dbFailure;
    }

    if (fileExtension != null && fileExtension.isNotEmpty) {
      try {
        final String rawPath =
            await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp,
          projectId,
          fileExtension: fileExtension,
        );
        if (!await File(rawPath).exists()) {
          LogService.instance.log(
            "restoreImage: raw file missing after restore for $timestamp "
            "(project=$projectId path=$rawPath); rolling back",
          );
          try {
            await DB.instance.softDeletePhoto(
              parsedTs,
              projectId,
              linkedSourceRelativePath: linkedTombstonePath,
              deletedAt: originalDeletedAt,
            );
          } catch (e) {
            LogService.instance.log(
              "restoreImage: rollback softDelete also failed: $e",
            );
          }
          return RestoreOutcome.rawFileMissing;
        }
      } catch (e) {
        LogService.instance.log(
          "restoreImage: post-update file-existence check failed for $timestamp: $e",
        );
        // Fall through — same rationale as before: don't block on path-resolution oddities.
      }
    }

    // Invalidate transform cache so the photo re-stabilizes against current
    // settings. Face-detection cache is intentionally left intact (faces
    // don't change with settings; saves an expensive ML pass).
    try {
      final fingerprint = await DB.instance.getPhotoColumnValueByTimestamp(
        timestamp,
        'fingerprint',
        projectId,
      ) as String?;
      if (fingerprint != null && fingerprint.isNotEmpty) {
        await DB.instance
            .clearTransformCacheForFingerprint(projectId, fingerprint);
      }
    } catch (e) {
      LogService.instance.log(
        "Failed to clear transform cache on restore (non-fatal): $e",
      );
    }

    try {
      await DB.instance.setNewVideoNeeded(projectId);
    } catch (_) {}

    return RestoreOutcome.success;
  }

  /// Permanently removes a photo: hard-deletes the row and cascades file
  /// cleanup (raw, stabilized, thumbnails). Used by "Delete Forever" in the
  /// Recently Deleted screen and by the launch-time purge.
  ///
  /// Returns one of [PermDeleteOutcome]. The previous `bool` return type
  /// (always `true` on file-delete failure) silently leaked sensitive photo
  /// bytes when a file was locked or unlinkable.
  ///
  /// [imagePath] is the raw photo file path; it is used to derive the
  /// timestamp and stabilized companion paths even if the file no longer
  /// exists on disk.
  static Future<PermDeleteOutcome> permanentlyDeleteImage(
    File image,
    int projectId,
  ) async {
    final String timestamp = path.basenameWithoutExtension(image.path);
    final int? parsedTs = int.tryParse(timestamp);
    if (parsedTs == null) {
      LogService.instance.log(
        "permanentlyDeleteImage: non-numeric timestamp ${image.path}",
      );
      return PermDeleteOutcome.dbFailure;
    }

    Map<String, dynamic>? originalInfo;
    try {
      originalInfo = await DB.instance.getOriginalInfoByTimestamp(
        timestamp,
        projectId,
      );
    } catch (_) {}

    // Hard-delete only if the row is currently soft-deleted. Defends against
    // a stale "Delete Forever" tap (UI snapshot vs. concurrent restore) and
    // against a future caller wiring this method to an active photo.
    try {
      final int rowsDeleted =
          await DB.instance.hardDeletePhotoIfTrashed(parsedTs, projectId);
      if (rowsDeleted == 0) {
        LogService.instance.log(
          "permanentlyDeleteImage: no trashed row for ${image.path} "
          "(restored or already purged) — aborting file cleanup",
        );
        return PermDeleteOutcome.rowAlreadyGone;
      }
    } catch (e) {
      LogService.instance.log(
        "permanentlyDeleteImage DB failure: ${image.path}, Error: $e",
      );
      return PermDeleteOutcome.dbFailure;
    }

    // Cache cleanup. Done after the row is gone so we never clear caches for
    // a photo that survived the delete guard above.
    final fingerprint = originalInfo?['fingerprint'] as String?;
    try {
      await DB.instance.clearFaceDetectionCacheForPhoto(timestamp, projectId);
    } catch (e) {
      LogService.instance.log(
        "Failed to clear face-detection cache (non-fatal): $e",
      );
    }
    if (fingerprint != null && fingerprint.isNotEmpty) {
      try {
        await DB.instance
            .clearTransformCacheForFingerprint(projectId, fingerprint);
      } catch (e) {
        LogService.instance.log(
          "Failed to clear transform cache (non-fatal): $e",
        );
      }
    }

    // DB row is gone. Now delete the on-disk files. We track raw + source
    // file deletion explicitly because those hold the user's photo bytes —
    // silently failing them is a privacy regression on a "Delete Forever"
    // action. Thumbnail/stabilized leftovers are recoverable garbage and
    // do NOT taint the outcome (they get cleaned up during video export).
    bool sensitiveFilesAllGone = true;

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
      if (await image.exists()) {
        await deleteFile(image);
        if (await image.exists()) {
          sensitiveFilesAllGone = false;
          LogService.instance.log(
            "Raw image still on disk after delete: ${image.path}",
          );
        }
      }
    } catch (e) {
      sensitiveFilesAllGone = false;
      LogService.instance.log(
        "Failed to delete raw image file: ${image.path}, Error: $e",
      );
    }

    final sourceLocationType = originalInfo?['sourceLocationType'] as String?;
    final sourceRelativePath = originalInfo?['sourceRelativePath'] as String?;

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
            // Another active row in *this project* may still reference this
            // file (rare — happens after a re-import + timestamp bump). Skip
            // the file delete in that case so we don't orphan the surviving
            // row. Cross-project ref-counting was removed because two projects
            // can be linked to *different* external roots that happen to
            // share the same relative path — counting those would falsely
            // block deletion.
            final int otherRefs =
                await DB.instance.countActivePhotosBySourceRelativePath(
              projectId,
              sourceRelativePath,
            );
            if (otherRefs > 0) {
              LogService.instance.log(
                "Skipping linked source delete; $otherRefs active row(s) "
                "still reference $sourceRelativePath",
              );
            } else {
              try {
                final File externalFile = File(externalPath);
                if (await externalFile.exists()) {
                  await externalFile.delete();
                  if (await externalFile.exists()) {
                    sensitiveFilesAllGone = false;
                    LogService.instance.log(
                      "Linked source file still on disk after delete: $externalPath",
                    );
                  } else {
                    LogService.instance.log(
                      "Deleted linked source file: $externalPath",
                    );
                  }
                }
              } catch (e) {
                sensitiveFilesAllGone = false;
                LogService.instance.log(
                  "Failed to delete linked source file $externalPath: $e",
                );
              }
            }
          }
        }
      } catch (e) {
        LogService.instance.log(
          "Failed to delete linked source file (non-fatal): $e",
        );
      }
    }

    final String? linkedTombstonePath = _linkedSourceTombstonePath(
      originalInfo,
    );
    if (linkedTombstonePath != null) {
      try {
        await DB.instance.insertDeletedLinkedSource(
          projectId,
          linkedTombstonePath,
        );
      } catch (e) {
        LogService.instance.log(
          "Failed to insert deleted linked source tombstone (non-fatal): $e",
        );
      }
    }

    try {
      await DB.instance.setNewVideoNeeded(projectId);
    } catch (_) {}

    return sensitiveFilesAllGone
        ? PermDeleteOutcome.success
        : PermDeleteOutcome.filesPartiallyRemain;
  }

  /// Deletes any soft-deleted photos older than [retentionDays] across every
  /// project. Called once at app launch — the only "scheduler" that works
  /// uniformly across iOS/Android/macOS/Windows/Linux without OS-specific
  /// background-task wiring.
  ///
  /// Returns the number of photos permanently removed.
  static Future<int> purgeExpiredDeletedImages({
    int retentionDays = DB.recentlyDeletedRetentionDays,
  }) async {
    final int cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;

    List<Map<String, dynamic>> expired;
    try {
      expired = await DB.instance.getExpiredDeletedPhotos(cutoff);
    } catch (e) {
      LogService.instance.log('purgeExpiredDeletedImages: query failed: $e');
      return 0;
    }
    if (expired.isEmpty) return 0;

    int purged = 0;
    int leftoverFiles = 0;
    for (final row in expired) {
      final String? timestamp = row['timestamp'] as String?;
      final int? projectId = row['projectID'] as int?;
      final String? fileExtension = row['fileExtension'] as String?;
      if (timestamp == null || projectId == null || fileExtension == null) {
        continue;
      }
      try {
        final String rawPath =
            await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp,
          projectId,
          fileExtension: fileExtension,
        );
        final outcome = await permanentlyDeleteImage(File(rawPath), projectId);
        if (outcome == PermDeleteOutcome.success ||
            outcome == PermDeleteOutcome.filesPartiallyRemain) {
          // The DB row is gone in both cases. The purge counts both as
          // "purged" because we won't see this row again next launch.
          purged++;
          if (outcome == PermDeleteOutcome.filesPartiallyRemain) {
            leftoverFiles++;
          }
        }
      } catch (e) {
        LogService.instance.log(
          'purgeExpiredDeletedImages: failed for ts=$timestamp project=$projectId: $e',
        );
      }
    }

    if (purged > 0) {
      final tail = leftoverFiles > 0
          ? ' ($leftoverFiles photo(s) left bytes on disk — see prior logs)'
          : '';
      LogService.instance.log(
        'purgeExpiredDeletedImages: hard-deleted $purged photos '
        '(retention=${retentionDays}d)$tail',
      );
    }
    return purged;
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

/// Outcome of [ProjectUtils.restoreImage]. Distinguishes the "row no longer
/// trashed" case (already restored elsewhere) from the "raw file missing on
/// disk" case (the photo's bytes are gone, so restoring would resurrect a
/// broken row). UI callers should surface [rawFileMissing] to the user.
///
/// [success] also covers the no-op case (already active) — that is
/// indistinguishable from a successful restore in the storage layer.
enum RestoreOutcome { success, rowNotTrashed, rawFileMissing, dbFailure }

/// Outcome of [ProjectUtils.permanentlyDeleteImage]. The DB row is the source
/// of truth, so [success] / [filesPartiallyRemain] both mean the row is gone;
/// the difference is whether every on-disk file was successfully removed.
/// UI callers should treat [filesPartiallyRemain] as a partial failure and
/// surface it (the user explicitly asked for "Delete Forever" — files
/// silently lingering is a privacy violation).
enum PermDeleteOutcome {
  success,
  filesPartiallyRemain,
  rowAlreadyGone,
  dbFailure
}
