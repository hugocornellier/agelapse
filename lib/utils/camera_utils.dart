import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:fast_thumbnail/fast_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:vibration/vibration.dart';

import '../services/async_mutex.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import 'dir_utils.dart';
import 'format_decode_utils.dart';
import 'image_processing_isolate.dart';
import 'linked_source_utils.dart';
import 'photo_fingerprint.dart';
import 'settings_utils.dart';
import 'windows_file_time.dart';

class CameraUtils {
  static final AsyncMutex _savePhotoMutex = AsyncMutex();

  /// Runs [entryPoint] in a new isolate, passes [params] (plus a SendPort),
  /// waits for the single reply, then kills the isolate and returns the result.
  static Future<T?> _executeInIsolate<T>(
    Future<void> Function(Map<String, dynamic>) entryPoint,
    Map<String, dynamic> params,
  ) async {
    final receivePort = ReceivePort();
    try {
      final isolate = await Isolate.spawn(entryPoint, {
        'sendPort': receivePort.sendPort,
        ...params,
      });
      final result = await receivePort.first as T?;
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
      return result;
    } catch (_) {
      receivePort.close();
      return null;
    }
  }

  static Future<Uint8List?> readBytesInIsolate(String filePath) async {
    Future<void> operation(Map<String, dynamic> params) async {
      final SendPort sendPort = params['sendPort'];
      Uint8List? bytes;
      try {
        bytes = await XFile(params['filePath'] as String).readAsBytes();
      } catch (_) {
        sendPort.send(null);
        return;
      }
      sendPort.send(bytes);
    }

    return _executeInIsolate<Uint8List>(operation, {'filePath': filePath});
  }

  static Future<String> saveImageToFileSystem(
    XFile image,
    String timestamp,
    int projectId,
  ) async {
    final String rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
    final String imagePath = path.join(
      rawPhotoDirPath,
      "$timestamp${path.extension(image.path)}",
    );
    await DirUtils.createDirectoryIfNotExists(imagePath);
    await image.saveTo(imagePath);
    return imagePath;
  }

  static Future<void> saveToGallery(XFile image) async {
    await saveImageToGallery(image.path);
  }

  static Future<void> saveImageToGallery(String filePath) async {
    try {
      final SaveResult result = await SaverGallery.saveFile(
        fileName: path.basename(filePath),
        filePath: filePath,
        skipIfExists: false,
        albumPath: "AgeLapse Exports",
      );

      if (result.isSuccess) {
        LogService.instance.log('Image saved to gallery: $result');
      } else {
        LogService.instance.log('Failed to save image to gallery');
      }
    } catch (e) {
      LogService.instance.log('Error saving image to gallery: $e');
    }
  }

  /// Triggers haptic feedback after successful photo capture.
  /// Only triggers on mobile platforms (iOS/Android).
  /// Uses a short, strong vibration pattern for clear feedback.
  static Future<void> triggerCaptureHaptic() async {
    // Only vibrate on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Short, strong vibration for capture feedback
        await Vibration.vibrate(duration: 100, amplitude: 200);
      }
    } catch (e) {
      // Vibration not available, continue silently
      LogService.instance.log('Vibration error: $e');
    }
  }

  static Future<bool> savePhoto(
    XFile? image,
    int projectId,
    bool import,
    int? imageTimestampFromExif, {
    Uint8List? bytes,
    VoidCallback? increaseSuccessfulImportCount,
    VoidCallback? refreshSettings,
    bool applyMirroring = false,
    String? deviceOrientation,
    String? originalFilePath,
    String? sourceFilename,
    String? sourceRelativePath,
    String? sourceLocationType,
  }) async {
    // --- Pre-process outside the mutex ---
    // CPU-intensive operations (rotation, mirroring, format decode, OpenCV
    // thumbnail) don't touch shared state (DB, file paths). Running them
    // before acquiring the lock keeps mutex hold time minimal (~50-100ms
    // vs ~2-4s).
    Uint8List? captureProcessedBytes;
    Uint8List? captureThumbnailBytes;
    int? captureWidth;
    int? captureHeight;
    String? captureImgPath;
    String? captureExtension;
    int? capturePhotoLength;

    // Pre-processed import state (moved outside mutex for performance)
    int? importPhotoLength;
    ImageProcessingOutput? importProcessingOutput;
    Uint8List? importPreDecodedBytes;
    String? importFingerprint;

    if (!import && image != null) {
      // --- Camera capture pre-processing ---
      captureImgPath = image.path;
      captureExtension = path.extension(captureImgPath).toLowerCase();
      capturePhotoLength = await image.length();

      // Rotation/mirroring via OpenCV isolate (~500ms-2s for high-res).
      final bool needsProcessing = (deviceOrientation == "Landscape Left" ||
              deviceOrientation == "Landscape Right") ||
          applyMirroring;
      if (needsProcessing) {
        final rawBytes = await File(captureImgPath).readAsBytes();
        final input = ImageProcessingInput(
          bytes: rawBytes,
          rotation: deviceOrientation,
          applyMirroring: applyMirroring,
          extension: captureExtension,
        );
        final output = await processImageSafely(input);
        if (output.success && output.processedBytes != null) {
          captureProcessedBytes = output.processedBytes;
          captureThumbnailBytes = output.thumbnailBytes;
          captureWidth = output.width;
          captureHeight = output.height;
        }
      }
    } else if (import && image != null) {
      // --- Import pre-processing (CPU-heavy, no shared state) ---
      importPhotoLength = await image.length();

      String imgPath = image.path;
      String extension = path.extension(imgPath).toLowerCase();

      // Read bytes if not already provided. These same source bytes feed the
      // fingerprint, the format pre-decode, and OpenCV processing below, so the
      // source file is read once here instead of also being re-read for the
      // hash (Finding #7, variant C: dedupe reads, keep File.copy placement).
      if (bytes == null || imgPath != image.path) {
        bytes = await CameraUtils.readBytesInIsolate(imgPath);
      }

      if (bytes != null) {
        // Content-based dedup fingerprint, computed from the bytes already in
        // memory. Byte-identical to hashing the file (same size + sha256),
        // minus a second full read of the source.
        try {
          importFingerprint = PhotoFingerprint.fromBytes(bytes);
        } catch (e) {
          LogService.instance.log('[Import] fingerprint error: $e');
        }

        // Pre-decode non-native formats (HEIC, AVIF, RAW, etc.)
        if (FormatDecodeUtils.needsConversion(extension)) {
          final tempDir = await DirUtils.getTemporaryDirPath();
          importPreDecodedBytes =
              await FormatDecodeUtils.decodeToCvCompatibleBytes(
            imgPath,
            extension,
            tempDir,
          );
        }

        // Process image in isolate (decode, rotate, flip, create thumbnail)
        final processingInput = ImageProcessingInput(
          bytes: bytes,
          rotation: deviceOrientation,
          applyMirroring: applyMirroring,
          extension: extension,
          preDecodedBytes: importPreDecodedBytes,
        );
        importProcessingOutput = await processImageSafely(processingInput);
      }
    }

    return _savePhotoMutex.protect(() async {
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filename = path.basename(image?.path ?? 'unknown');
      try {
        // --- CAMERA CAPTURE FAST PATH ---
        // Heavy processing already done above; mutex only covers fast I/O + DB.
        if (!import) {
          final String imgPath = captureImgPath!;
          final String extension = captureExtension!;
          final int? newPhotoLength = capturePhotoLength;
          if (newPhotoLength == null) return false;

          sourceLocationType ??= 'camera_capture';
          sourceFilename ??= 'capture_$timestamp$extension';

          // Write to photos_raw/: pre-processed bytes or raw XFile copy
          final rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
          final rawPhotoPath = path.join(
            rawPhotoDirPath,
            "$timestamp$extension",
          );
          await DirUtils.createDirectoryIfNotExists(rawPhotoPath);
          if (captureProcessedBytes != null) {
            await File(rawPhotoPath).writeAsBytes(captureProcessedBytes);
          } else {
            await XFile(imgPath).saveTo(rawPhotoPath);
          }
          await _preserveModifiedTime(
            sourcePath: originalFilePath ?? imgPath,
            targetPath: rawPhotoPath,
          );

          // Generate thumbnail
          final String thumbnailPath = path.join(
            await DirUtils.getThumbnailDirPath(projectId),
            "$timestamp.jpg",
          );
          await DirUtils.createDirectoryIfNotExists(thumbnailPath);

          String orientation;
          if (captureThumbnailBytes != null &&
              captureWidth != null &&
              captureHeight != null) {
            // Thumbnail already created in isolate during rotation/mirroring,
            // write bytes directly, skip disk round-trip through
            // FastThumbnail.
            await File(thumbnailPath).writeAsBytes(captureThumbnailBytes);
            orientation = captureHeight > captureWidth
                ? "portrait"
                : captureHeight < captureWidth
                    ? "landscape"
                    : "square";
          } else {
            // No processing done (portrait, no mirror): use native
            // FastThumbnail which reads from disk with subsampled decode.
            final ThumbnailResult? thumbnailResult =
                await FastThumbnail.generate(
              inputPath: rawPhotoPath,
              outputPath: thumbnailPath,
            );
            if (thumbnailResult == null) return false;
            orientation = thumbnailResult.originalHeight >
                    thumbnailResult.originalWidth
                ? "portrait"
                : thumbnailResult.originalHeight < thumbnailResult.originalWidth
                    ? "landscape"
                    : "square";
          }

          final linkedPlacement = await _maybePlaceSourceInLinkedFolder(
            projectId: projectId,
            sourceFilePath: imgPath,
            sourceFilename: sourceFilename!,
            sourceRelativePath: sourceRelativePath,
            sourceLocationType: sourceLocationType,
          );
          sourceRelativePath ??= linkedPlacement?.relativePath;
          sourceFilename = linkedPlacement?.filename ?? sourceFilename;

          String? captureFingerprint;
          try {
            captureFingerprint = await PhotoFingerprint.compute(rawPhotoPath);
          } catch (e) {
            LogService.instance.log('[Capture] fingerprint error: $e');
          }

          // DB insert after files are safely on disk
          final inserted = await DB.instance.addPhoto(
            timestamp,
            projectId,
            extension,
            newPhotoLength,
            path.basename(imgPath),
            orientation,
            sourceFilename: sourceFilename,
            sourceRelativePath: sourceRelativePath,
            sourceLocationType: sourceLocationType,
            fingerprint: captureFingerprint,
          );
          if (!inserted) return false;

          final int tsInt = int.parse(timestamp);
          final int captureOffsetMin = DateTime.fromMillisecondsSinceEpoch(
            tsInt,
            isUtc: true,
          ).toLocal().timeZoneOffset.inMinutes;
          await DB.instance.setCaptureOffsetMinutesByTimestamp(
            timestamp,
            projectId,
            captureOffsetMin,
          );

          if (refreshSettings != null) refreshSettings();

          ThumbnailService.instance.emit(
            ThumbnailEvent(
              thumbnailPath: thumbnailPath,
              status: ThumbnailStatus.success,
              projectId: projectId,
              timestamp: timestamp.toString(),
            ),
          );

          if (await SettingsUtil.loadSaveToCameraRoll()) {
            CameraUtils.saveImageToGallery(rawPhotoPath);
          }

          try {
            await File(image!.path).delete();
          } catch (_) {}
          if (imgPath != image!.path) {
            try {
              await File(imgPath).delete();
            } catch (_) {}
          }

          if (increaseSuccessfulImportCount != null) {
            increaseSuccessfulImportCount();
          }

          LogService.instance.log('[Capture] $filename');
          return true;
        }

        // --- IMPORT PATH ---
        // Heavy processing (format decode, OpenCV, thumbnail creation)
        // already done above before the mutex was acquired.

        final int? newPhotoLength = importPhotoLength;
        if (newPhotoLength == null) {
          return false;
        }

        if (bytes == null ||
            importProcessingOutput == null ||
            !importProcessingOutput.success) {
          return false;
        }

        // Content-based dedup: fingerprint the *source* file (before we
        // potentially rewrite it with processed bytes below). Catches EXIF-less
        // imports and size-collision false positives that the legacy
        // timestamp+size check would miss.
        if (importFingerprint != null) {
          final match = await DB.instance.findPhotoByFingerprint(
            projectId,
            importFingerprint,
          );
          if (match != null) {
            LogService.instance.log(
              '[Import] duplicate by fingerprint, skipping '
              '(matched timestamp=${match['timestamp']})',
            );
            return false;
          }
        }

        if (imageTimestampFromExif != null) {
          timestamp = imageTimestampFromExif.toString();
          // doesPhotoExistByTimestamp / getPhotosByTimestamp include trashed
          // rows because the (timestamp, projectID) pair is the raw-file
          // slot identifier on disk; a soft-deleted file at raw/{ts}.{ext}
          // still occupies that slot.
          bool photoExists = await DB.instance.doesPhotoExistByTimestamp(
            timestamp,
            projectId,
          );
          while (photoExists) {
            final Map<String, dynamic> existingPhoto =
                (await DB.instance.getPhotosByTimestamp(
              timestamp,
              projectId,
            ))
                    .first;
            final bool existingIsTrashed = existingPhoto['deletedAt'] != null;
            // Only dedup against ACTIVE rows. A soft-deleted match at this
            // slot must not block the import; that would be a silent failure
            // for a user re-importing a file they previously trashed. Bump
            // the timestamp instead, so the new row gets its own files and
            // the old soft-deleted row ages out of Recently Deleted.
            if (!existingIsTrashed) {
              final existingFingerprint =
                  existingPhoto['fingerprint'] as String?;
              final bothFingerprinted =
                  importFingerprint != null && existingFingerprint != null;
              if (bothFingerprinted) {
                if (importFingerprint == existingFingerprint) {
                  return false; // Duplicate
                }
              } else if (newPhotoLength == existingPhoto['imageLength']) {
                return false; // Duplicate
              }
            }

            final int timestampPlusPlus = int.parse(timestamp) + 1;
            timestamp = timestampPlusPlus.toString();
            photoExists = await DB.instance.doesPhotoExistByTimestamp(
              timestamp,
              projectId,
            );
          }
        }

        String imgPath = image!.path;
        String extension = path.extension(imgPath).toLowerCase();
        sourceLocationType ??= 'direct_import';

        sourceFilename ??= path.basename(originalFilePath ?? imgPath);

        // Write processed image if rotation/mirroring was applied
        if (importProcessingOutput.processedBytes != null) {
          await File(
            imgPath,
          ).writeAsBytes(importProcessingOutput.processedBytes!);
        }

        int importedImageWidth = importProcessingOutput.width;
        int importedImageHeight = importProcessingOutput.height;

        String orientation = importedImageHeight > importedImageWidth
            ? "portrait"
            : importedImageHeight < importedImageWidth
                ? "landscape"
                : "square";

        // Write files to disk BEFORE DB insert to avoid orphaned DB rows
        await CameraUtils.saveImageToFileSystem(
          XFile(imgPath),
          timestamp,
          projectId,
        );
        final rawPhotoPath =
            await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp,
          projectId,
          fileExtension: extension,
        );
        await _preserveModifiedTime(
          sourcePath: originalFilePath ?? imgPath,
          targetPath: rawPhotoPath,
        );

        final String thumbnailPath = path.join(
          await DirUtils.getThumbnailDirPath(projectId),
          "$timestamp.jpg",
        );
        await DirUtils.createDirectoryIfNotExists(thumbnailPath);

        // Write thumbnail (already created in isolate)
        if (importProcessingOutput.thumbnailBytes == null) {
          return false;
        }
        await File(
          thumbnailPath,
        ).writeAsBytes(importProcessingOutput.thumbnailBytes!);

        final linkedPlacement = await _maybePlaceSourceInLinkedFolder(
          projectId: projectId,
          sourceFilePath: imgPath,
          sourceFilename: sourceFilename!,
          sourceRelativePath: sourceRelativePath,
          sourceLocationType: sourceLocationType,
        );
        sourceRelativePath ??= linkedPlacement?.relativePath;
        sourceFilename = linkedPlacement?.filename ?? sourceFilename;

        // DB insert after files are safely on disk
        final inserted = await DB.instance.addPhoto(
          timestamp,
          projectId,
          extension,
          newPhotoLength,
          path.basename(imgPath),
          orientation,
          sourceFilename: sourceFilename,
          sourceRelativePath: sourceRelativePath,
          sourceLocationType: sourceLocationType,
          fingerprint: importFingerprint,
        );
        if (!inserted) return false;

        // Set capture timezone offset so streak/date calculations stay
        // correct across DST transitions instead of falling back to
        // the device's current offset at query time.
        final int tsInt = int.parse(timestamp);
        final int captureOffsetMin = DateTime.fromMillisecondsSinceEpoch(
          tsInt,
          isUtc: true,
        ).toLocal().timeZoneOffset.inMinutes;
        await DB.instance.setCaptureOffsetMinutesByTimestamp(
          timestamp,
          projectId,
          captureOffsetMin,
        );

        if (refreshSettings != null) {
          refreshSettings();
        }

        ThumbnailService.instance.emit(
          ThumbnailEvent(
            thumbnailPath: thumbnailPath,
            status: ThumbnailStatus.success,
            projectId: projectId,
            timestamp: timestamp.toString(),
          ),
        );

        bytes = null;

        if (increaseSuccessfulImportCount != null) {
          increaseSuccessfulImportCount();
        }

        LogService.instance.log('[Import] $filename');
        return true;
      } catch (_) {
        return false;
      } finally {
        bytes = null;
      }
    });
  }

  /// Copies file timestamps (modified time + creation time) from [sourcePath]
  /// to [targetPath].
  ///
  /// - macOS: `setLastModified` to an earlier date also moves birthtime.
  /// - Windows: copies CreationTime via the Win32 API (CreateFileW/GetFileTime/
  ///   SetFileTime) through dart:ffi — see [copyWindowsCreationTime].
  /// - Linux: Creation time (btime) cannot be set from userspace; only
  ///   modification time is preserved.
  static Future<void> _preserveModifiedTime({
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);
      if (!await sourceFile.exists() || !await targetFile.exists()) return;
      final sourceModified = await sourceFile.lastModified();
      await targetFile.setLastModified(sourceModified);

      if (Platform.isWindows) {
        copyWindowsCreationTime(sourcePath, targetPath);
      }
    } catch (_) {}
  }

  static Future<LinkedSourcePlacement?> _maybePlaceSourceInLinkedFolder({
    required int projectId,
    required String sourceFilePath,
    required String sourceFilename,
    String? sourceRelativePath,
    String? sourceLocationType,
  }) async {
    if (sourceRelativePath != null && sourceRelativePath.trim().isNotEmpty) {
      return LinkedSourcePlacement(
        absolutePath: sourceFilePath,
        relativePath: sourceRelativePath,
        filename: sourceFilename,
      );
    }

    if (sourceLocationType == 'external_linked') {
      return null;
    }

    return LinkedSourceUtils.placeSourceFile(
      projectId: projectId,
      sourceFilePath: sourceFilePath,
      preferredFilename: sourceFilename,
    );
  }
}
