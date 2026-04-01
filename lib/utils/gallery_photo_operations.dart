import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import '../widgets/confirm_action_dialog.dart';
import 'date_stamp_utils.dart';
import 'dir_utils.dart';
import 'project_utils.dart';
import 'settings_utils.dart';

/// Shared photo operations used by gallery_page.dart and image_preview_navigator.dart.
/// Consolidates duplicate implementations for photo manipulation.
class GalleryPhotoOperations {
  /// Retries stabilization for a single photo by clearing caches, deleting
  /// existing stabilized files, and resetting the database entry.
  ///
  /// [imagePath] - Path to the raw or stabilized image
  /// [projectId] - The project ID
  /// [projectOrientation] - Optional orientation override; if null, loads from settings
  /// [onRetryStarted] - Optional callback invoked with the timestamp when retry begins
  ///
  /// Returns the timestamp of the photo being retried.
  static Future<String> retryStabilization({
    required String imagePath,
    required int projectId,
    String? projectOrientation,
    void Function(String timestamp)? onRetryStarted,
  }) async {
    final String timestamp = path.basenameWithoutExtension(imagePath);

    // Get paths
    final String rawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      projectId,
    );
    final String orientation = projectOrientation ??
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String stabilizedImagePath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      projectId,
      rawPhotoPath,
      orientation,
    );
    final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(
      stabilizedImagePath,
    );

    // Clear caches BEFORE deleting files
    ThumbnailService.instance.clearCache(stabThumbPath);

    // Evict specific images from Flutter's cache
    final stabImageProvider = FileImage(File(stabilizedImagePath));
    final stabThumbProvider = FileImage(File(stabThumbPath));
    stabImageProvider.evict();
    stabThumbProvider.evict();

    // Notify caller that retry is starting (for UI updates)
    onRetryStarted?.call(timestamp);

    // Delete files
    await DirUtils.deleteFileIfExists(stabilizedImagePath);
    await DirUtils.deleteFileIfExists(stabThumbPath);

    // Reset DB
    await DB.instance.resetStabilizedColumnByTimestamp(
      orientation,
      timestamp,
      projectId,
    );

    return timestamp;
  }

  /// Deletes a photo and all related files (raw, stabilized, thumbnails).
  ///
  /// This method handles resolving stabilized paths to raw paths automatically,
  /// delegates to [ProjectUtils.deleteImage] for the actual deletion, and
  /// clears the thumbnail cache.
  ///
  /// Returns true if deletion was successful, false otherwise.
  static Future<bool> deletePhoto({
    required File imageFile,
    required int projectId,
  }) async {
    // Resolve to raw file if this is a stabilized image
    File toDelete = imageFile;
    final bool isStabilizedImage = imageFile.path.toLowerCase().contains(
          "stabilized",
        );
    if (isStabilizedImage) {
      final String timestamp = path.basenameWithoutExtension(imageFile.path);
      final String rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
      );
      toDelete = File(rawPhotoPath);
    }

    // Use existing ProjectUtils for deletion
    final bool success = await ProjectUtils.deleteImage(toDelete, projectId);

    if (success) {
      // Clear thumbnail cache
      final String switched = toDelete.path.replaceAll(
        DirUtils.photosRawDirname,
        DirUtils.thumbnailDirname,
      );
      final String thumbnailPath = path.join(
        path.dirname(switched),
        "${path.basenameWithoutExtension(toDelete.path)}.jpg",
      );
      ThumbnailService.instance.clearCache(thumbnailPath);
    }

    return success;
  }

  /// Changes the date of a photo by renaming all associated files and updating
  /// the database records.
  ///
  /// This is the comprehensive implementation that handles:
  /// - Raw file and thumbnail renaming
  /// - Stabilized files in both orientations (portrait/landscape)
  /// - Database timestamp update
  /// - Guide photo reference update
  /// - Capture timezone offset update
  /// - Video regeneration flag
  ///
  /// [oldTimestamp] - Current timestamp (milliseconds since epoch as string)
  /// [newTimestamp] - New timestamp (milliseconds since epoch as string)
  /// [projectId] - The project ID
  ///
  /// Throws an exception if the original file is not found.
  static Future<void> changePhotoDate({
    required String oldTimestamp,
    required String newTimestamp,
    required int projectId,
  }) async {
    final String oldRawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      oldTimestamp,
      projectId,
    );
    if (!await File(oldRawPhotoPath).exists()) {
      throw Exception('Original file not found');
    }

    final String fileExtension = path.extension(oldRawPhotoPath);
    final String newRawPhotoPath = path.join(
      path.dirname(oldRawPhotoPath),
      '$newTimestamp$fileExtension',
    );
    final String thumbDir = path.dirname(
      oldRawPhotoPath.replaceAll(
        DirUtils.photosRawDirname,
        DirUtils.thumbnailDirname,
      ),
    );
    final String oldRawThumbPath = path.join(thumbDir, '$oldTimestamp.jpg');
    final String newRawThumbPath = path.join(thumbDir, '$newTimestamp.jpg');

    final renames = <({String from, String to})>[
      (from: oldRawPhotoPath, to: newRawPhotoPath),
    ];

    if (await File(oldRawThumbPath).exists()) {
      renames.add((from: oldRawThumbPath, to: newRawThumbPath));
    }

    for (final orientation in DirUtils.orientations) {
      final String oldStabPath =
          await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
        projectId,
        oldRawPhotoPath,
        orientation,
      );
      if (!await File(oldStabPath).exists()) continue;

      final String newStabPath = path.join(
        path.dirname(oldStabPath),
        '$newTimestamp.png',
      );
      renames.add((from: oldStabPath, to: newStabPath));

      final String oldStabThumbPath = FaceStabilizer.getStabThumbnailPath(
        oldStabPath,
      );
      if (await File(oldStabThumbPath).exists()) {
        renames.add((
          from: oldStabThumbPath,
          to: FaceStabilizer.getStabThumbnailPath(newStabPath),
        ));
      }
    }

    for (final rename in renames) {
      if (await File(rename.to).exists()) {
        throw FileSystemException(
          'Target path already exists during date change',
          rename.to,
        );
      }
    }

    final completedRenames = <({String from, String to})>[];
    try {
      for (final rename in renames) {
        await DirUtils.createDirectoryIfNotExists(rename.to);
        await File(rename.from).rename(rename.to);
        completedRenames.add(rename);
      }

      final oldPhotoRecord = await DB.instance.getPhotoByTimestamp(
        oldTimestamp,
        projectId,
      );
      if (oldPhotoRecord == null) {
        throw StateError('Photo record not found for timestamp $oldTimestamp');
      }

      final int oldId = oldPhotoRecord['id'] as int;
      final int? newId = await DB.instance.updatePhotoTimestamp(
        oldTimestamp,
        newTimestamp,
        projectId,
      );
      if (newId == null) {
        throw StateError('Failed to update photo timestamp in database');
      }

      final String currentGuidePhoto =
          await SettingsUtil.loadSelectedGuidePhoto(
        projectId.toString(),
      );
      if (currentGuidePhoto == oldId.toString()) {
        await DB.instance.setSettingByTitle(
          "selected_guide_photo",
          newId.toString(),
          projectId.toString(),
        );
      }

      final int newTsInt = int.parse(newTimestamp);
      final int newOffsetMin = DateTime.fromMillisecondsSinceEpoch(
        newTsInt,
        isUtc: true,
      ).toLocal().timeZoneOffset.inMinutes;
      await DB.instance.setCaptureOffsetMinutesByTimestamp(
        newTimestamp,
        projectId,
        newOffsetMin,
      );

      await DB.instance.setNewVideoNeeded(projectId);
    } catch (e) {
      for (final rename in completedRenames.reversed) {
        try {
          final revertedFile = File(rename.to);
          if (await revertedFile.exists()) {
            await DirUtils.createDirectoryIfNotExists(rename.from);
            await revertedFile.rename(rename.from);
          }
        } catch (rollbackError) {
          LogService.instance.log(
            'Rollback failed for ${rename.to} -> ${rename.from}: $rollbackError',
          );
        }
      }
      rethrow;
    }
  }

  /// Convenience wrapper: changes the photo date then triggers a gallery reload
  /// and optional video recompilation.
  ///
  /// Callers supply [loadImages] and [recompileCallback] so that UI-layer
  /// concerns (snackbars, navigation) stay in the calling widget.
  static Future<void> changeDateAndReload({
    required String oldTimestamp,
    required String newTimestamp,
    required int projectId,
    required Future<void> Function() loadImages,
    required Future<void> Function() recompileCallback,
    required bool needsRecompile,
  }) async {
    await changePhotoDate(
      oldTimestamp: oldTimestamp,
      newTimestamp: newTimestamp,
      projectId: projectId,
    );
    await loadImages();
    if (needsRecompile) await recompileCallback();
  }

  /// Sets a photo as the guide photo for face stabilization.
  ///
  /// [timestamp] - The timestamp of the photo to set as guide
  /// [projectId] - The project ID
  ///
  /// Returns true if successful, false if the photo was not found.
  static Future<bool> setAsGuidePhoto({
    required String timestamp,
    required int projectId,
  }) async {
    final photoRecord = await DB.instance.getPhotoByTimestamp(
      timestamp,
      projectId,
    );
    if (photoRecord == null) return false;

    await DB.instance.setSettingByTitle(
      "selected_guide_photo",
      photoRecord['id'].toString(),
      projectId.toString(),
    );
    return true;
  }

  /// Checks if changing a photo's timestamp would change its position in the
  /// sorted list.
  ///
  /// [oldTimestamp] - Current timestamp string (ms since epoch)
  /// [newTimestamp] - Proposed new timestamp string (ms since epoch)
  /// [allImageFilenames] - Basenames (without extension) of all images in the
  ///   project, used to determine current sort order.
  static bool wouldChangeOrder(
    String oldTimestamp,
    String newTimestamp,
    List<String> allImageFilenames,
  ) {
    if (allImageFilenames.length <= 1) return false;

    final oldIndex = allImageFilenames.indexOf(oldTimestamp);

    final timestamps =
        allImageFilenames.where((t) => t != oldTimestamp).toList();
    timestamps.add(newTimestamp);
    timestamps.sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return ai.compareTo(bi);
      return a.compareTo(b);
    });
    final newIndex = timestamps.indexOf(newTimestamp);

    return oldIndex != newIndex;
  }

  /// Shows the date-picker → time-picker flow and computes whether the change
  /// would affect the video.
  ///
  /// Returns a record `(newTimestamp, wouldChangeOrder, dateStampTextChanged)`
  /// if the user completed the flow, or `null` if they cancelled at any step.
  /// Also shows a confirmation dialog when a recompile would be needed.
  ///
  /// [currentTimestamp] - Existing timestamp string (ms since epoch)
  /// [projectIdStr] - Project ID as string (for settings lookup)
  /// [allImageFilenames] - Basenames without extension for all project images
  static Future<(String, bool, bool)?> showChangeDateFlow({
    required BuildContext context,
    required String currentTimestamp,
    required String projectIdStr,
    required List<String> allImageFilenames,
  }) async {
    final initialDate = DateTime.fromMillisecondsSinceEpoch(
      int.parse(currentTimestamp),
    );

    final newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (newDate == null) return null;
    // ignore: use_build_context_synchronously — caller must check mounted after
    if (!context.mounted) return null;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (newTime == null) return null;
    if (!context.mounted) return null;

    final newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );
    final newTimestamp = newDateTime.millisecondsSinceEpoch.toString();

    final orderChanged = wouldChangeOrder(
      currentTimestamp,
      newTimestamp,
      allImageFilenames,
    );

    bool dateStampTextChanged = false;
    final exportStampsEnabled = await SettingsUtil.loadExportDateStampEnabled(
      projectIdStr,
    );

    if (exportStampsEnabled && !orderChanged) {
      final format = await SettingsUtil.loadExportDateStampFormat(projectIdStr);
      final oldText = DateStampUtils.formatTimestamp(
        int.parse(currentTimestamp),
        format,
      );
      final newText = DateStampUtils.formatTimestamp(
        int.parse(newTimestamp),
        format,
      );
      dateStampTextChanged = oldText != newText;
    }

    final needsRecompile = orderChanged || dateStampTextChanged;

    if (needsRecompile) {
      if (!context.mounted) return null;
      final confirmed = await ConfirmActionDialog.showDateChangeRecompile(
        context,
        orderChanged: orderChanged,
      );
      if (!confirmed) return null;
    }

    return (newTimestamp, orderChanged, dateStampTextChanged);
  }

  /// Shows the appropriate delete-confirmation dialog (with or without
  /// recompile warning) based on the remaining photo count.
  ///
  /// Returns `true` if the user confirmed the deletion, `false` otherwise.
  static Future<bool> confirmDeletePhoto({
    required BuildContext context,
    required int totalPhotos,
  }) async {
    final int remainingAfterDelete = totalPhotos - 1;
    final bool shouldRecompile = remainingAfterDelete >= 2;

    final bool confirmed;
    if (shouldRecompile) {
      confirmed = await ConfirmActionDialog.showDeleteRecompile(
        context,
        photoCount: 1,
      );
    } else {
      confirmed = await ConfirmActionDialog.showDeleteSimple(
        context,
        photoCount: 1,
      );
    }

    return confirmed;
  }
}
