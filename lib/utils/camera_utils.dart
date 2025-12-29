import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path/path.dart' as path;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:vibration/vibration.dart';

import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import 'dir_utils.dart';
import 'heic_utils.dart';

class CameraUtils {
  static Future<bool> loadSaveToCameraRollSetting() async {
    try {
      String saveToCameraRollStr =
          await DB.instance.getSettingValueByTitle('save_to_camera_roll');
      return bool.tryParse(saveToCameraRollStr) ?? false;
    } catch (e) {
      debugPrint('Failed to load watermark setting: $e');
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
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
    };

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
      String saveToPath, String xFilePath) async {
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
      XFile image, String timestamp, int projectId) async {
    final String rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
    final String imagePath =
        path.join(rawPhotoDirPath, "$timestamp${path.extension(image.path)}");
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

  static Future<void> flashAndVibrate() async {
    var hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      LogService.instance.log("vibrating");
      Vibration.vibrate(duration: 500, amplitude: 155);
    } else {
      LogService.instance.log("no vibrate");
    }
    await Future.delayed(const Duration(milliseconds: 50));
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
    try {
      LogService.instance.log("[savePhoto] START: $filename");

      final int? newPhotoLength = await image?.length();
      LogService.instance.log("[savePhoto] File size: $newPhotoLength bytes");
      if (newPhotoLength == null) {
        LogService.instance
            .log("[savePhoto] SKIP: File size is null for $filename");
        return false;
      }

      if (imageTimestampFromExif != null) {
        timestamp = imageTimestampFromExif.toString();
        LogService.instance.log(
            "[savePhoto] Checking for duplicate with timestamp: $timestamp, size: $newPhotoLength");
        bool photoExists =
            await DB.instance.doesPhotoExistByTimestamp(timestamp, projectId);
        while (photoExists) {
          final Map<String, dynamic> existingPhoto =
              (await DB.instance.getPhotosByTimestamp(timestamp, projectId))
                  .first;
          LogService.instance.log(
              "[savePhoto] Found existing photo at timestamp $timestamp with size: ${existingPhoto['imageLength']}");
          if (newPhotoLength == existingPhoto['imageLength']) {
            LogService.instance.log(
                "[savePhoto] SKIP DUPLICATE: $filename has same timestamp AND size as existing photo");
            return false;
          }

          final int timestampPlusPlus = int.parse(timestamp) + 1;
          LogService.instance.log(
              "[savePhoto] Different size, incrementing timestamp: $timestamp -> $timestampPlusPlus");
          timestamp = timestampPlusPlus.toString();
          photoExists =
              await DB.instance.doesPhotoExistByTimestamp(timestamp, projectId);
        }
        LogService.instance.log(
            "[savePhoto] No duplicate found, proceeding with timestamp: $timestamp");
      }

      String imgPath = image!.path;
      String extension = path.extension(imgPath).toLowerCase();
      LogService.instance
          .log("[savePhoto] Processing file: $imgPath (extension: $extension)");

      if (extension == ".heic" || extension == ".heif") {
        LogService.instance
            .log("[savePhoto] HEIC/HEIF detected, converting to JPG");
        final String heicPath = imgPath;
        final String jpgPath = path.setExtension(heicPath, ".jpg");

        if (Platform.isMacOS) {
          final result = await Process.run(
            'sips',
            ['-s', 'format', 'jpeg', heicPath, '--out', jpgPath],
          );
          if (result.exitCode != 0 || !await File(jpgPath).exists()) {
            LogService.instance.log(
                "[savePhoto] SKIP: HEIC conversion failed (sips) for $filename");
            return false;
          }
        } else if (Platform.isWindows) {
          final success = await HeicUtils.convertHeicToJpgAt(heicPath, jpgPath);
          if (!success) {
            LogService.instance.log(
                "[savePhoto] SKIP: HEIC conversion failed (HeicUtils) for $filename");
            return false;
          }
        } else {
          // iOS/Android - use heif_converter package
          await HeifConverter.convert(
            heicPath,
            output: jpgPath,
            format: 'jpeg',
          );
          if (!await File(jpgPath).exists()) {
            LogService.instance.log(
                "[savePhoto] SKIP: HEIC conversion failed (HeifConverter) for $filename");
            return false;
          }
        }
        LogService.instance
            .log("[savePhoto] HEIC conversion successful: $jpgPath");
        imgPath = jpgPath;
        extension = ".jpg";
      }

      LogService.instance.log("[savePhoto] Reading bytes from: $imgPath");
      bytes = await CameraUtils.readBytesInIsolate(imgPath);
      if (bytes == null) {
        LogService.instance
            .log("[savePhoto] SKIP: Failed to read bytes from $filename");
        return false;
      }
      LogService.instance.log("[savePhoto] Read ${bytes.length} bytes");

      LogService.instance.log("[savePhoto] Decoding image with OpenCV");
      cv.Mat rawImage = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (rawImage.isEmpty) {
        LogService.instance
            .log("[savePhoto] SKIP: OpenCV failed to decode image $filename");
        rawImage.dispose();
        return false;
      }
      LogService.instance.log(
          "[savePhoto] OpenCV decoded: ${rawImage.width}x${rawImage.height}");

      if (deviceOrientation != null) {
        cv.Mat rotated;
        if (deviceOrientation == "Landscape Left") {
          rotated = cv.rotate(rawImage, cv.ROTATE_90_CLOCKWISE);
        } else if (deviceOrientation == "Landscape Right") {
          rotated = cv.rotate(rawImage, cv.ROTATE_90_COUNTERCLOCKWISE);
        } else {
          rotated = rawImage;
        }
        if (rotated != rawImage) {
          rawImage.dispose();
          rawImage = rotated;
        }
        if (extension == ".png") {
          final (success, encoded) = cv.imencode('.png', rawImage);
          if (success) bytes = encoded;
        } else {
          final (success, encoded) = cv.imencode('.jpg', rawImage);
          if (success) bytes = encoded;
        }
        await File(imgPath).writeAsBytes(bytes);
      }

      if (applyMirroring) {
        final flipped = cv.flip(rawImage, 1); // 1 = horizontal flip
        rawImage.dispose();
        rawImage = flipped;
        if (extension == ".png") {
          final (success, encoded) = cv.imencode('.png', rawImage);
          if (success) bytes = encoded;
        } else {
          final (success, encoded) = cv.imencode('.jpg', rawImage);
          if (success) bytes = encoded;
        }
        await File(imgPath).writeAsBytes(bytes);
      }

      int importedImageWidth = rawImage.cols;
      int importedImageHeight = rawImage.rows;

      double aspectRatio = importedImageWidth / importedImageHeight;
      aspectRatio = aspectRatio > 1 ? aspectRatio : 1 / aspectRatio;

      String orientation = importedImageHeight > importedImageWidth
          ? "portrait"
          : importedImageHeight < importedImageWidth
              ? "landscape"
              : "square";

      await DB.instance.addPhoto(timestamp, projectId, extension,
          newPhotoLength, path.basename(imgPath), orientation);

      if (refreshSettings != null) {
        refreshSettings();
      }

      await CameraUtils.saveImageToFileSystem(
          XFile(imgPath), timestamp, projectId);

      final String thumbnailPath = path.join(
          await DirUtils.getThumbnailDirPath(projectId), "$timestamp.jpg");
      await DirUtils.createDirectoryIfNotExists(thumbnailPath);

      LogService.instance.log("[savePhoto] Creating thumbnail: $thumbnailPath");
      bool result = await _createThumbnailForNewImage(thumbnailPath, rawImage);
      rawImage.dispose();
      if (!result) {
        LogService.instance
            .log("[savePhoto] SKIP: Thumbnail creation failed for $filename");
        return false;
      }

      ThumbnailService.instance.emit(ThumbnailEvent(
        thumbnailPath: thumbnailPath,
        status: ThumbnailStatus.success,
        projectId: projectId,
        timestamp: timestamp.toString(),
      ));

      bytes = null;

      // Save to gallery if setting is enabled
      if (!import && await CameraUtils.loadSaveToCameraRollSetting()) {
        await CameraUtils.saveToGallery(image);
      }

      if (increaseSuccessfulImportCount != null) {
        increaseSuccessfulImportCount();
      }

      LogService.instance.log(
          "[savePhoto] SUCCESS: $filename imported with timestamp $timestamp");
      return true;
    } catch (e, stackTrace) {
      LogService.instance.log("[savePhoto] EXCEPTION for $filename: $e");
      LogService.instance.log("[savePhoto] Stack trace: $stackTrace");
      return false;
    } finally {
      bytes = null;
    }
  }

  static Future<bool> _createThumbnailForNewImage(
      String thumbnailPath, cv.Mat rawImage) async {
    return _createThumbnailFromRawImage(rawImage, thumbnailPath);
  }

  static Future<bool> _createThumbnailFromRawImage(
      cv.Mat rawImage, String thumbnailPath) async {
    // Resize to 500px width maintaining aspect ratio
    final aspectRatio = rawImage.rows / rawImage.cols;
    final height = (500 * aspectRatio).round();
    final thumbnail = cv.resize(rawImage, (500, height));

    final File thumbnailFile = File(thumbnailPath);
    final (success, encodedJpgBytes) = cv.imencode('.jpg', thumbnail,
        params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
    thumbnail.dispose();

    if (!success) return false;
    await thumbnailFile.writeAsBytes(encodedJpgBytes);
    return true;
  }
}
