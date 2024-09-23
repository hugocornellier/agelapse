import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as imglib;
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:vibration/vibration.dart';

import '../services/database_helper.dart';
import 'dir_utils.dart';

class CameraUtils {
  static Future<bool> loadSaveToCameraRollSetting() async {
    try {
      String saveToCameraRollStr = await DB.instance.getSettingValueByTitle('save_to_camera_roll');
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
    } catch(_) {
      return null;
    } finally {
      bytes = null;
    }
  }

  static Future<String> saveImageToFileSystemInIsolate(String saveToPath, String xFilePath) async {
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

  static Future<String> saveImageToFileSystem(XFile image, String timestamp, int projectId) async {
    final String rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
    final String imagePath = path.join(rawPhotoDirPath, "$timestamp${path.extension(image.path)}");
    await DirUtils.createDirectoryIfNotExists(imagePath);

    await saveImageToFileSystemInIsolate(imagePath, image.path);

    return imagePath;
  }

  static Future<void> saveToGallery(XFile image) async {
    await saveImageToGallery(image.path);
  }

  static Future<void> saveImageToGallery(String filePath) async {
    try {
      PermissionStatus storageStatus = await Permission.storage.request();
      PermissionStatus photosStatus = await Permission.photos.request();

      if (!storageStatus.isGranted) {
        print('Storage permission not granted');
        return;
      }

      if (!photosStatus.isGranted) {
        print('Photos permission not granted');
        return;
      }

      print("Both permissions granted");
    } catch (e) {
      print('Error checking permissions: $e');
    }

    try {
      String name = path.basename(filePath).isEmpty
          ? "image"
          : path.basename(filePath);

      print("here... name: ");
      print(name);
      final SaveResult result = await SaverGallery.saveFile(
          file: filePath,
          name: name,
          androidExistNotSave: false
      );
      print("here2");
      if (result.isSuccess) {
        print('Image saved to gallery: $result');
      } else {
        print('Failed to save image to gallery');
      }
    } catch (e) {
      print('Error saving image to gallery: $e');
    }
  }

  static Future<void> flashAndVibrate() async {
    var hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != null && hasVibrator) {
      Vibration.vibrate(duration: 5, amplitude: 1);
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }

  static Future<bool> savePhoto(
    XFile? image,
    int projectId,
    bool import,
    int? imageTimestampFromExif,
    bool failedToParseDateMetadata,
    {
      Uint8List? bytes,
      VoidCallback? increaseSuccessfulImportCount,
      VoidCallback? refreshSettings
    }
  ) async {
    String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final int? newPhotoLength = await image?.length();
      if (newPhotoLength == null) return false;

      if (imageTimestampFromExif != null) {
        timestamp = imageTimestampFromExif.toString();
        bool photoExists = await DB.instance.doesPhotoExistByTimestamp(timestamp, projectId);
        while (photoExists) {
          final Map<String, dynamic> existingPhoto = (await DB.instance.getPhotosByTimestamp(timestamp, projectId)).first;
          if (newPhotoLength == existingPhoto['imageLength']) {
            return false;
          }

          final int timestampPlusPlus = int.parse(timestamp) + 1;
          timestamp = timestampPlusPlus.toString();
          photoExists = await DB.instance.doesPhotoExistByTimestamp(timestamp, projectId);
        }
      }

      String imgPath = image!.path;
      String extension = path.extension(imgPath).toLowerCase();
      String heicPath = "";

      if (extension == ".heic") {
        extension = ".jpg";
        heicPath = imgPath;
        imgPath = heicPath.replaceAll(".heic", extension);

        await HeifConverter.convert(
            heicPath,
            output: imgPath,
            format: 'jpeg'
        );
      }

      bytes = await CameraUtils.readBytesInIsolate(imgPath);
      if (bytes == null) {
        return false;
      }

      final imglib.Image? rawImage = await compute(imglib.decodeImage, bytes);
      if (rawImage == null) {
        return false;
      }

      int? importedImageWidth = rawImage.width;
      int? importedImageHeight = rawImage.height;

      double aspectRatio = (importedImageWidth ?? 1) / (importedImageHeight ?? 1);
      aspectRatio = aspectRatio > 1 ? aspectRatio : 1 / aspectRatio;

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
        orientation
      );

      if (refreshSettings != null) {
        refreshSettings();
      }

      await CameraUtils.saveImageToFileSystem(XFile(imgPath), timestamp, projectId);

      // Create thumbnail and save
      final String thumbnailPath = path.join(
        await DirUtils.getThumbnailDirPath(projectId),
        "$timestamp.jpg"
      );
      await DirUtils.createDirectoryIfNotExists(thumbnailPath);

      bool result = await _createThumbnailForNewImage(extension, bytes, imgPath, thumbnailPath, rawImage);
      if (!result) return false;

      bytes = null;

      // Save to gallery if setting is enabled
      if (!import && await CameraUtils.loadSaveToCameraRollSetting()) {
        await CameraUtils.saveToGallery(image);
      }

      if (increaseSuccessfulImportCount != null) {
        increaseSuccessfulImportCount();
      }

      return true;
    } finally {
      bytes = null;
    }
  }

  static Future<bool> _createThumbnailForNewImage(
    String extension,
    bytes,
    String imgPath,
    String thumbnailPath,
    imglib.Image rawImage
  ) async {
    return _createThumbnailFromRawImage(rawImage, thumbnailPath);
  }

  static Future<bool> _createThumbnailFromRawImage(imglib.Image rawImage, String thumbnailPath) async {
    final imglib.Image thumbnail = imglib.copyResize(rawImage, width: 500);
    final File thumbnailFile = File(thumbnailPath);
    Uint8List? encodedJpgBytes = encodeJpg(thumbnail);
    await thumbnailFile.writeAsBytes(encodedJpgBytes!);
    return true;
  }

  static Uint8List? encodeJpg(imglib.Image thumbnail) {
    try {
      var data = imglib.encodeJpg(thumbnail);
      return data;
    } catch(_) {
      return null;
    }
  }
} 
