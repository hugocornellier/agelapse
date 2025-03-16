import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../services/database_helper.dart';
import '../camera_utils.dart';
import '../dir_utils.dart';
import '../project_utils.dart';
import '../settings_utils.dart';

class StabUtils {
  static Future<List<Map<String, dynamic>>> getUnstabilizedPhotos(projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    return await DB.instance.getUnstabilizedPhotos(projectId, projectOrientation);
  }

  static List<Point<int>?> extractEyePositions(List<Face> faces) {
    return faces
        .where((face) => face.landmarks[FaceLandmarkType.leftEye] != null && face.landmarks[FaceLandmarkType.rightEye] != null)
        .expand((face) => [
          Point(face.landmarks[FaceLandmarkType.leftEye]!.position.x.toInt(), face.landmarks[FaceLandmarkType.leftEye]!.position.y.toInt()),
          Point(face.landmarks[FaceLandmarkType.rightEye]!.position.x.toInt(), face.landmarks[FaceLandmarkType.rightEye]!.position.y.toInt()),
        ])
        .toList();
  }

  static Future<List<Face>?> getFacesFromFilepath(
    String imagePath,
    FaceDetector faceDetector,
    {
      bool filterByFaceSize = true,
      int? imageWidth,
    }
  ) async {
    final bool fileExists = File(imagePath).existsSync();
    if (!fileExists) {
      return null;
    }

    try {
      final List<Face> faces = await faceDetector.processImage(
        InputImage.fromFilePath(imagePath),
      );

      if (!filterByFaceSize || faces.isEmpty) return faces;

      return await _filterFacesBySize(faces, imageWidth, imagePath);
    } catch(e) {
      print("Error caught while fetching faces: $e");
      return [];
    }
  }

  static Future<List<Face>> _filterFacesBySize(
    List<Face> faces,
    int? imageWidth,
    String imagePath
  ) async {
    const double minFaceSize = 0.1;

    try {
      if (imageWidth == null) {
        (imageWidth, _) = await getImageDimensions(imagePath);
      }

      List<Face> filteredFaces = faces.where((face) {
        final double faceWidth = face.boundingBox.right - face.boundingBox.left;
        return faceWidth / imageWidth! > minFaceSize;
      }).toList();

      return filteredFaces.isNotEmpty ? filteredFaces : faces;
    } catch (_) {
      return [];
    }
  }

  static Future<(int, int)> getImageDimensions(String imagePath) async {
    final bytes = await CameraUtils.readBytesInIsolate(imagePath);
    final imglib.Image? image = await compute(imglib.decodeImage, bytes!);

    if (image == null) {
      throw Exception('Unable to decode image');
    }

    return (image.width, image.height);
  }

  static Future<void> performFileOperationInBackground(Map<String, dynamic> params) async {
    SendPort sendPort = params['sendPort'];
    String filePath = params['filePath'];
    var operation = params['operation'];
    imglib.Image? bitmap = params['bitmap'];
    var bytes = params['bytes'];

    switch (operation) {
      case 'readJpg':
        try {
          String extension = path.extension(filePath).toLowerCase();
          if (extension == ".jpg") {
            bytes = await File(filePath).readAsBytes();
            bitmap = imglib.JpegDecoder().decode(bytes);
          } else {
            bytes = await File(filePath).readAsBytes();
            bitmap = imglib.decodeImage(bytes);
          }
        } catch (e) {
          bitmap = null;
        } finally {
          sendPort.send(bitmap);
        }
        break;
      case 'writePng':
        try {
          if (bitmap != null) {
            bytes = imglib.encodePng(bitmap);
            await File(filePath).writeAsBytes(bytes!);
            sendPort.send('File written successfully');
          } else {
            sendPort.send('Bitmap is null');
          }
        } catch (e) {
          sendPort.send('Error writing PNG: $e');
        }
        break;
      case 'writeJpg':
        try {
          if (bytes != null) {
            bitmap = imglib.PngDecoder().decode(bytes);
            if (bitmap != null) {
              bytes = imglib.encodeJpg(bitmap);
              await File(filePath).writeAsBytes(bytes);
              sendPort.send('File written successfully');
            } else {
              sendPort.send('Decoded bitmap is null');
            }
          } else {
            sendPort.send('Bytes are null');
          }
        } catch (e) {
          sendPort.send('Error writing JPG: $e');
        }
        break;
    }
  }

  static Future<imglib.Image?> getBitmapInIsolate(String filePath) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'operation': 'readJpg'
    };

    Isolate? isolate = await Isolate.spawn(performFileOperationInBackground, params);
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result as imglib.Image?;
  }

  static Future<void> writeBitmapToPngFileInIsolate(String filepath, imglib.Image bitmap) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filepath,
      'bitmap': bitmap,
      'operation': 'writePng'
    };

    Isolate? isolate = await Isolate.spawn(performFileOperationInBackground, params);
    await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }

  static Future<void> writeBytesToJpgFileInIsolate(String filePath, List<int> bytes) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'bytes': bytes,
      'operation': 'writeJpg'
    };

    Isolate? isolate = await Isolate.spawn(performFileOperationInBackground, params);
    await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }

  static Future<bool> writeImagesBytesToJpgFile(Uint8List bytes, String imagePath) async {
    await DirUtils.createDirectoryIfNotExists(imagePath);
    await writeBytesToJpgFileInIsolate(imagePath, bytes);
    return true;
  }

  static Future<void> preparePNG(String imgPath) async {
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(imgPath);
    await DirUtils.createDirectoryIfNotExists(pngPath);
    final File pngFile = File(pngPath);

    if ((File(imgPath).existsSync() && !pngFile.existsSync()) || await pngFile.length() == 0) {
      bool conversionToJpgNeeded = false;
      String jpgImgPath = "";

      if (path.extension(imgPath).toLowerCase() == ".heic") {
        conversionToJpgNeeded = true;
        jpgImgPath = imgPath.replaceAll(".heic", ".jpg");
        await HeifConverter.convert(
            imgPath,
            output: jpgImgPath,
            format: 'jpeg'
        );
        imgPath = jpgImgPath;
      }

      final imglib.Image? bitmap = await getBitmapInIsolate(imgPath);

      if (bitmap != null) await writeBitmapToPngFileInIsolate(pngPath, bitmap);

      if (conversionToJpgNeeded) {
        await ProjectUtils.deleteFile(File(jpgImgPath));
      }
    }
  }

  static Future<File> flipImageHorizontally(String imagePath) async {
    return await processImageInIsolate(imagePath, imglib.flipHorizontal, '_flipped.png');
  }

  // Rotate Image 90 Degrees Clockwise
  static Future<File> rotateImageClockwise(String imagePath) async {
    return await processImageInIsolate(imagePath, (image) => imglib.copyRotate(image, angle: 90), '_rotated_clockwise.png');
  }

  // Rotate Image 90 Degrees Counter-Clockwise
  static Future<File> rotateImageCounterClockwise(String imagePath) async {
    return await processImageInIsolate(imagePath, (image) => imglib.copyRotate(image, angle: -90), '_rotated_counter_clockwise.png');
  }

  static Future<void> performImageProcessingInBackground(Map<String, dynamic> params) async {
    final rootIsolateToken = params['rootIsolateToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

    SendPort sendPort = params['sendPort'];
    String filePath = params['filePath'];
    String suffix = params['suffix'];
    imglib.Image Function(imglib.Image) operationFunction = params['operationFunction'];

    try {
      final Uint8List imageBytes = await File(filePath).readAsBytes();
      final imglib.Image? image = imglib.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      final imglib.Image processedImage = operationFunction(image);
      final Directory tempDir = await getTemporaryDirectory();
      final String name = path.basenameWithoutExtension(filePath);

      final String newName = '$name$suffix';
      final String newPath = path.join(tempDir.path, newName);
      final File processedImageFile = File(newPath);
      await processedImageFile.writeAsBytes(imglib.encodePng(processedImage));

      sendPort.send(processedImageFile);
    } catch (e) {
      sendPort.send(e);
    }
  }

  static Future<File> processImageInIsolate(String imagePath, imglib.Image Function(imglib.Image) operation, String suffix) async {
    ReceivePort receivePort = ReceivePort();
    final rootIsolateToken = RootIsolateToken.instance;
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': imagePath,
      'operationFunction': operation,
      'suffix': suffix,
      'rootIsolateToken': rootIsolateToken
    };

    Isolate? isolate = await Isolate.spawn(performImageProcessingInBackground, params);
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);

    if (result is File) {
      return result;
    } else {
      throw result;
    }
  }

  static Future<String> getStabilizedImagePath(String originalFilePath, int projectId, String? projectOrientation) async {
    final stabilizedDirectoryPath = await DirUtils.getStabilizedDirPath(projectId);
    final String originalBasename = path.basenameWithoutExtension(originalFilePath);
    return path.join(stabilizedDirectoryPath, projectOrientation, '$originalBasename.jpg');
  }

  static Future<ui.Image?> loadImageFromFile(File file) async {
    try {
      const int maxWaitTimeInSeconds = 10;
      int elapsedSeconds = 0;

      while (!(await file.exists())) {
        if (elapsedSeconds >= maxWaitTimeInSeconds) {
          debugPrint("Error loading image: file not found within $maxWaitTimeInSeconds seconds");
          return null;
        }
        await Future.delayed(const Duration(seconds: 1));
        elapsedSeconds++;
      }

      final Uint8List bytes = await file.readAsBytes();
      return await decodeImageFromList(bytes);
    } catch (e) {
      debugPrint("Error loading image: $e");
      return null;
    }
  }

}
