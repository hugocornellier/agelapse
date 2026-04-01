import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:heic2png/heic2png.dart';
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
import 'settings_utils.dart';

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
      final isolate = await Isolate.spawn(
        entryPoint,
        {'sendPort': receivePort.sendPort, ...params},
      );
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

  static Future<String> saveImageToFileSystemInIsolate(
    String saveToPath,
    String xFilePath,
  ) async {
    Future<void> operation(Map<String, dynamic> params) async {
      final SendPort sendPort = params['sendPort'];
      await XFile(params['xFilePath'] as String).saveTo(
        params['saveToPath'] as String,
      );
      sendPort.send("Success");
    }

    final result = await _executeInIsolate<String>(operation, {
      'saveToPath': saveToPath,
      'xFilePath': xFilePath,
    });
    return result ?? '';
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

    await saveImageToFileSystemInIsolate(imagePath, image.path);

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
        androidRelativePath: "Pictures/AgeLapse Exports",
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
    return _savePhotoMutex.protect(() async {
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filename = path.basename(image?.path ?? 'unknown');
      String?
          heicPathToDelete; // Track original HEIC for cleanup after conversion
      try {
        int? newPhotoLength = await image?.length();
        if (newPhotoLength == null) {
          return false;
        }

        if (imageTimestampFromExif != null) {
          timestamp = imageTimestampFromExif.toString();
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
            if (newPhotoLength == existingPhoto['imageLength']) {
              return false; // Duplicate
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
        sourceLocationType ??= import ? 'direct_import' : 'camera_capture';

        // HEIC/HEIF conversion only for camera captures.
        // Imports store the original file byte-for-byte in photos_raw/.
        if (!import && (extension == ".heic" || extension == ".heif")) {
          final String heicPath = imgPath;
          final String pngPath = path.setExtension(heicPath, ".png");

          final success = await Heic2png.convert(heicPath, pngPath);
          if (!success || !await File(pngPath).exists()) {
            return false;
          }

          heicPathToDelete = heicPath; // Mark original for cleanup
          imgPath = pngPath;
          extension = ".png";
          newPhotoLength = await File(pngPath).length();
        }

        sourceFilename ??= import
            ? path.basename(originalFilePath ?? imgPath)
            : 'capture_$timestamp$extension';

        // Only re-read if bytes weren't provided OR if conversion changed the file path
        if (bytes == null || imgPath != image.path) {
          bytes = await CameraUtils.readBytesInIsolate(imgPath);
        }
        if (bytes == null) {
          return false;
        }

        // Pre-decode non-native formats for thumbnail generation.
        // When importing HEIC, AVIF, RAW, etc., cv.imdecode can't handle
        // these formats directly, so we decode to JPEG bytes as a fallback.
        Uint8List? preDecodedBytes;
        if (import && FormatDecodeUtils.needsConversion(extension)) {
          final tempDir = await DirUtils.getTemporaryDirPath();
          preDecodedBytes = await FormatDecodeUtils.decodeToCvCompatibleBytes(
            imgPath,
            extension,
            tempDir,
          );
        }

        // Process image in isolate (decode, rotate, flip, create thumbnail)
        // This moves CPU-intensive OpenCV operations off the main thread
        final processingInput = ImageProcessingInput(
          bytes: bytes!,
          rotation: deviceOrientation,
          applyMirroring: applyMirroring,
          extension: extension,
          preDecodedBytes: preDecodedBytes,
        );

        final processingOutput = await processImageSafely(processingInput);

        if (!processingOutput.success) {
          return false;
        }

        // Write processed image if rotation/mirroring was applied
        if (processingOutput.processedBytes != null) {
          await File(
            imgPath,
          ).writeAsBytes(processingOutput.processedBytes!, flush: true);
        }

        int importedImageWidth = processingOutput.width;
        int importedImageHeight = processingOutput.height;

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
        if (processingOutput.thumbnailBytes == null) {
          return false;
        }
        await File(thumbnailPath)
            .writeAsBytes(processingOutput.thumbnailBytes!);

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
        await DB.instance.addPhoto(
          timestamp,
          projectId,
          extension,
          newPhotoLength,
          path.basename(imgPath),
          orientation,
          sourceFilename: sourceFilename,
          sourceRelativePath: sourceRelativePath,
          sourceLocationType: sourceLocationType,
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

        // Save to gallery if setting is enabled
        if (!import && await SettingsUtil.loadSaveToCameraRoll()) {
          await CameraUtils.saveToGallery(image);
        }

        if (increaseSuccessfulImportCount != null) {
          increaseSuccessfulImportCount();
        }

        LogService.instance.log('[Import] $filename');
        return true;
      } catch (_) {
        return false;
      } finally {
        bytes = null;

        // Clean up original HEIC file after successful conversion (camera captures only).
        // For imports, there's no converted file to clean up.
        if (!import && heicPathToDelete != null) {
          await DirUtils.deleteFileIfExists(heicPathToDelete);
        }
      }
    });
  }

  /// Copies file timestamps (modified time + creation time) from [sourcePath]
  /// to [targetPath].
  ///
  /// - macOS: `setLastModified` to an earlier date also moves birthtime.
  /// - Windows: Uses PowerShell to copy CreationTime since Dart has no API.
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
        await _preserveCreationTimeWindows(sourcePath, targetPath);
      }
    } catch (_) {}
  }

  /// Uses PowerShell to copy the creation time from one file to another.
  static Future<void> _preserveCreationTimeWindows(
    String sourcePath,
    String targetPath,
  ) async {
    try {
      final escaped = targetPath.replaceAll("'", "''");
      final srcEscaped = sourcePath.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-Item '$escaped').CreationTime = "
            "(Get-Item '$srcEscaped').CreationTime",
      ]);
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
