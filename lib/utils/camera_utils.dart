import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path/path.dart' as path;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:vibration/vibration.dart';

import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import 'dir_utils.dart';
import 'heic_utils.dart';
import 'image_processing_isolate.dart';

class CameraUtils {
  static Future<bool> loadSaveToCameraRollSetting() async {
    try {
      String saveToCameraRollStr = await DB.instance.getSettingValueByTitle(
        'save_to_camera_roll',
      );
      return bool.tryParse(saveToCameraRollStr) ?? false;
    } catch (e) {
      LogService.instance.log('Failed to load save to camera roll setting: $e');
      return false;
    }
  }

  static Future<Uint8List?> readBytesInIsolate(String filePath) async {
    Future<void> galleryIsolateOperation(Map<String, dynamic> params) async {
      SendPort sendPort = params['sendPort'];
      String filePath = params['filePath'];
      Uint8List? bytes;
      try {
        bytes = await XFile(filePath).readAsBytes();
      } catch (_) {
        sendPort.send(null);
      }
      sendPort.send(bytes);
      bytes = null;
    }

    ReceivePort receivePort = ReceivePort();
    var params = {'sendPort': receivePort.sendPort, 'filePath': filePath};

    Uint8List? bytes;
    try {
      Isolate isolate = await Isolate.spawn(galleryIsolateOperation, params);
      bytes = await receivePort.first;
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      bytes = null;
    }
  }

  static Future<String> saveImageToFileSystemInIsolate(
    String saveToPath,
    String xFilePath,
  ) async {
    Future<void> saveImageIsolateOperation(Map<String, dynamic> params) async {
      SendPort sendPort = params['sendPort'];
      String saveToPath = params['saveToPath'];
      String xFilePath = params['xFilePath'];

      XFile xFile = XFile(xFilePath);
      await xFile.saveTo(saveToPath);

      sendPort.send("Success");
    }

    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'saveToPath': saveToPath,
      'xFilePath': xFilePath,
    };

    Isolate isolate = await Isolate.spawn(saveImageIsolateOperation, params);
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result;
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

  /// @deprecated Use [triggerCaptureHaptic] instead.
  /// Kept for backwards compatibility.
  static Future<void> flashAndVibrate() async {
    await triggerCaptureHaptic();
  }

  static Future<bool> savePhoto(
    XFile? image,
    int projectId,
    bool import,
    int? imageTimestampFromExif,
    bool failedToParseDateMetadata, {
    Uint8List? bytes,
    VoidCallback? increaseSuccessfulImportCount,
    VoidCallback? refreshSettings,
    bool applyMirroring = false,
    String? deviceOrientation,
  }) async {
    String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String filename = path.basename(image?.path ?? 'unknown');
    String?
        heicPathToDelete; // Track original HEIC for cleanup after conversion
    try {
      final int? newPhotoLength = await image?.length();
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

      if (extension == ".heic" || extension == ".heif") {
        final String heicPath = imgPath;
        final String jpgPath = path.setExtension(heicPath, ".jpg");

        if (Platform.isMacOS) {
          // macOS: use built-in sips command
          final result = await Process.run('sips', [
            '-s',
            'format',
            'jpeg',
            heicPath,
            '--out',
            jpgPath,
          ]);
          if (result.exitCode != 0 || !await File(jpgPath).exists()) {
            return false;
          }
        } else if (Platform.isWindows) {
          // Windows: use bundled HeicConverter.exe
          final success = await HeicUtils.convertHeicToJpgAt(heicPath, jpgPath);
          if (!success) {
            return false;
          }
        } else if (Platform.isLinux) {
          // Linux: use heif_converter package
          try {
            await HeifConverter.convert(
              heicPath,
              output: jpgPath,
              format: 'jpeg',
            );
            if (!await File(jpgPath).exists()) {
              return false;
            }
          } catch (_) {
            return false;
          }
        } else {
          // iOS/Android - use heif_converter package
          try {
            await HeifConverter.convert(
              heicPath,
              output: jpgPath,
              format: 'jpeg',
            );
            if (!await File(jpgPath).exists()) {
              return false;
            }
          } catch (_) {
            return false;
          }
        }
        heicPathToDelete = heicPath; // Mark original for cleanup
        imgPath = jpgPath;
        extension = ".jpg";
      }

      // Only re-read if bytes weren't provided OR if conversion changed the file path
      if (bytes == null || imgPath != image.path) {
        bytes = await CameraUtils.readBytesInIsolate(imgPath);
      }
      if (bytes == null) {
        return false;
      }

      // Process image in isolate (decode, rotate, flip, create thumbnail)
      // This moves CPU-intensive OpenCV operations off the main thread
      final processingInput = ImageProcessingInput(
        bytes: bytes,
        rotation: deviceOrientation,
        applyMirroring: applyMirroring,
        extension: extension,
      );

      final processingOutput = await processImageSafely(processingInput);

      if (!processingOutput.success) {
        return false;
      }

      // Write processed image if rotation/mirroring was applied
      if (processingOutput.processedBytes != null) {
        await File(imgPath)
            .writeAsBytes(processingOutput.processedBytes!, flush: true);
      }

      int importedImageWidth = processingOutput.width;
      int importedImageHeight = processingOutput.height;

      String orientation = importedImageHeight > importedImageWidth
          ? "portrait"
          : importedImageHeight < importedImageWidth
              ? "landscape"
              : "square";

      await DB.instance.addPhoto(
        timestamp,
        projectId,
        extension,
        newPhotoLength,
        path.basename(imgPath),
        orientation,
      );

      if (refreshSettings != null) {
        refreshSettings();
      }

      await CameraUtils.saveImageToFileSystem(
        XFile(imgPath),
        timestamp,
        projectId,
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
      await File(thumbnailPath).writeAsBytes(processingOutput.thumbnailBytes!);

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
      if (!import && await CameraUtils.loadSaveToCameraRollSetting()) {
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

      // Clean up original HEIC file after successful conversion
      if (heicPathToDelete != null) {
        try {
          final heicFile = File(heicPathToDelete);
          if (await heicFile.exists()) {
            await heicFile.delete();
          }
        } catch (_) {}
      }
    }
  }
}
