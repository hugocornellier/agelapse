import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
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
    final File stabImageFile = File(stabilizedImagePath);
    final File stabThumbFile = File(stabThumbPath);
    if (await stabImageFile.exists()) {
      await stabImageFile.delete();
    }
    if (await stabThumbFile.exists()) {
      await stabThumbFile.delete();
    }

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
    // Get raw file path
    String oldRawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      oldTimestamp,
      projectId,
    );
    File oldRawFile = File(oldRawPhotoPath);
    if (!await oldRawFile.exists()) {
      throw Exception('Original file not found');
    }

    // Rename raw file
    String fileExtension = path.extension(oldRawPhotoPath);
    String newRawPhotoPath = path.join(
      path.dirname(oldRawPhotoPath),
      '$newTimestamp$fileExtension',
    );
    await oldRawFile.rename(newRawPhotoPath);

    // Rename raw thumbnail
    String oldRawThumbPath = oldRawPhotoPath.replaceAll(
      DirUtils.photosRawDirname,
      DirUtils.thumbnailDirname,
    );
    oldRawThumbPath = path.join(
      path.dirname(oldRawThumbPath),
      "${path.basenameWithoutExtension(oldRawPhotoPath)}.jpg",
    );
    File oldRawThumbFile = File(oldRawThumbPath);
    if (await oldRawThumbFile.exists()) {
      String newRawThumbPath = path.join(
        path.dirname(oldRawThumbPath),
        "$newTimestamp.jpg",
      );
      await oldRawThumbFile.rename(newRawThumbPath);
    }

    // Rename stabilized files in both orientations
    List<String> orientations = ['portrait', 'landscape'];
    for (String orientation in orientations) {
      try {
        String oldStabPath = await DirUtils
            .getStabilizedImagePathFromRawPathAndProjectOrientation(
          projectId,
          oldRawPhotoPath,
          orientation,
        );
        File oldStabFile = File(oldStabPath);
        if (await oldStabFile.exists()) {
          String newStabPath = path.join(
            path.dirname(oldStabPath),
            '$newTimestamp.png',
          );
          await oldStabFile.rename(newStabPath);

          // Rename stabilized thumbnail
          String oldStabThumbPath = FaceStabilizer.getStabThumbnailPath(
            oldStabPath,
          );
          File oldStabThumbFile = File(oldStabThumbPath);
          if (await oldStabThumbFile.exists()) {
            String newStabThumbPath = FaceStabilizer.getStabThumbnailPath(
              newStabPath,
            );
            await DirUtils.createDirectoryIfNotExists(newStabThumbPath);
            await oldStabThumbFile.rename(newStabThumbPath);
          }
        }
      } catch (e) {
        LogService.instance.log(
          'No stabilized file found for $orientation: $e',
        );
      }
    }

    // Update database
    final oldPhotoRecord = await DB.instance.getPhotoByTimestamp(
      oldTimestamp,
      projectId,
    );
    if (oldPhotoRecord == null) return;

    final int oldId = oldPhotoRecord['id'] as int;
    int? newId = await DB.instance.updatePhotoTimestamp(
      oldTimestamp,
      newTimestamp,
      projectId,
    );

    // Update guide photo reference if needed
    final String currentGuidePhoto =
        await SettingsUtil.loadSelectedGuidePhoto(projectId.toString());
    if (currentGuidePhoto == oldId.toString() && newId != null) {
      await DB.instance.setSettingByTitle(
        "selected_guide_photo",
        newId.toString(),
        projectId.toString(),
      );
    }

    // Update capture timezone offset
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

    // Mark video as needing regeneration
    await DB.instance.setNewVideoNeeded(projectId);
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
}
