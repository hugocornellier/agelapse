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
import 'package:face_detection_tflite/face_detection_tflite.dart' as fdl;
import 'package:apple_vision_face/apple_vision_face.dart' as av hide Face;

import '../../services/database_helper.dart';
import '../camera_utils.dart';
import '../dir_utils.dart';
import '../project_utils.dart';
import '../settings_utils.dart';

class AVFaceLike {
  final Rect boundingBox;
  final Point<double>? leftEye;
  final Point<double>? rightEye;

  AVFaceLike({
    required this.boundingBox,
    required this.leftEye,
    required this.rightEye,
  });
}

class StabUtils {
  static fdl.FaceDetector? _fdLite;
  static bool _fdLiteReady = false;
  static final av.AppleVisionFaceController _avController = av.AppleVisionFaceController();

  static Future<void> _ensureFDLite() async {
    if (_fdLite == null) {
      _fdLite = fdl.FaceDetector();
      await _fdLite!.initialize(model: fdl.FaceDetectionModel.backCamera);
      _fdLiteReady = true;
    } else if (!_fdLiteReady) {
      await _fdLite!.initialize(model: fdl.FaceDetectionModel.backCamera);
      _fdLiteReady = true;
    }
  }
  static Future<List<Map<String, dynamic>>> getUnstabilizedPhotos(projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    return await DB.instance.getUnstabilizedPhotos(projectId, projectOrientation);
  }

  static double? getShortSide(String resolution) {
    if (resolution == "1080p") return 1080;
    if (resolution == "2K") return 1152;
    if (resolution == "3K") return 1728;
    if (resolution == "4K") return 2304;
    return null;
  }

  static double? getAspectRatioAsDecimal(String aspectRatio) {
    if (!aspectRatio.contains(':')) return null;
    final List<String> split = aspectRatio.split(":");
    int? dividend = int.tryParse(split[0]);
    int? divisor = int.tryParse(split[1]);
    if (dividend == null || divisor == null) return null;
    return dividend / divisor;
  }

  static List<Point<double>?> extractEyePositions(List<Face> faces) {
    final out = <Point<double>?>[];
    for (final face in faces) {
      final l = face.landmarks[FaceLandmarkType.leftEye];
      final r = face.landmarks[FaceLandmarkType.rightEye];
      if (l == null || r == null) continue;
      var a = Point(l.position.x.toDouble(), l.position.y.toDouble());
      var b = Point(r.position.x.toDouble(), r.position.y.toDouble());
      if (a.x > b.x) { final t = a; a = b; b = t; }
      out..add(a)..add(b);
    }
    return out;
  }

  static Future<List<dynamic>?> getFacesFromFilepath(
      String imagePath,
      FaceDetector? faceDetector,
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
      if (Platform.isLinux || Platform.isWindows) {
        await _ensureFDLite();
        final bytes = await File(imagePath).readAsBytes();
        final Size? origSize = await _fdLite!.getOriginalSize(bytes);
        if (origSize == null) return [];
        final double w = origSize.width;
        final double h = origSize.height;

        final detections = await _fdLite!.getDetections(bytes);
        final List<AVFaceLike> faces = [];
        for (final d in detections) {
          final Rect bbox = Rect.fromLTRB(
            d.bbox.xmin * w,
            d.bbox.ymin * h,
            d.bbox.xmax * w,
            d.bbox.ymax * h,
          );

          final Offset? l = d.landmarks[fdl.FaceIndex.leftEye];
          final Offset? r = d.landmarks[fdl.FaceIndex.rightEye];

          final Point<double>? leftPt  = l == null ? null : Point<double>(l.dx.toDouble(), l.dy.toDouble());
          final Point<double>? rightPt = r == null ? null : Point<double>(r.dx.toDouble(), r.dy.toDouble());

          faces.add(AVFaceLike(
            boundingBox: bbox,
            leftEye: leftPt,
            rightEye: rightPt,
          ));
        }

        if (!filterByFaceSize || faces.isEmpty) return faces;

        const double minFaceSize = 0.1;
        final filtered = faces.where((f) => (f.boundingBox.width / w) > minFaceSize).toList();
        return filtered.isNotEmpty ? filtered : faces;
      } else if (Platform.isMacOS) {
        final ui.Image? uiImg = await loadImageFromFile(File(imagePath));
        if (uiImg == null) return [];
        final int width = imageWidth ?? uiImg.width;
        final int height = uiImg.height;
        uiImg.dispose();

        final bytes = await File(imagePath).readAsBytes();
        final results = await _avController.processImage(bytes, Size(width.toDouble(), height.toDouble()));
        if (results == null || results.isEmpty) return [];

        final List<AVFaceLike> faces = [];
        for (final faceData in results) {
          double minX = double.infinity, minY = double.infinity;
          double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

          Point<double>? leftEyeCenter;
          Point<double>? rightEyeCenter;

          for (final mark in faceData.marks) {
            if (mark.location.isEmpty) continue;

            final bool isLeft = mark.landmark == av.LandMark.leftEye;
            final bool isRight = mark.landmark == av.LandMark.rightEye;

            double sx = 0, sy = 0;
            for (final p in mark.location) {
              sx += p.x;
              sy += p.y;
              if (p.x < minX) minX = p.x;
              if (p.y < minY) minY = p.y;
              if (p.x > maxX) maxX = p.x;
              if (p.y > maxY) maxY = p.y;
            }

            if (isLeft || isRight) {
              final cx = sx / mark.location.length;
              final cy = sy / mark.location.length;
              final center = Point<double>(cx, cy);
              if (isLeft) {
                leftEyeCenter = center;
              } else {
                rightEyeCenter = center;
              }
            }
          }

          final bool normalized = maxX <= 1.0 && maxY <= 1.0;
          final double sx = normalized ? width.toDouble() : 1.0;
          final double sy = normalized ? height.toDouble() : 1.0;

          final Rect bbox = Rect.fromLTRB(
            (minX.isFinite ? minX : 0) * sx,
            (minY.isFinite ? minY : 0) * sy,
            (maxX.isFinite ? maxX : 0) * sx,
            (maxY.isFinite ? maxY : 0) * sy,
          );

          final Point<double>? leftScaled = leftEyeCenter == null ? null : Point<double>(leftEyeCenter.x * sx, leftEyeCenter.y * sy);
          final Point<double>? rightScaled = rightEyeCenter == null ? null : Point<double>(rightEyeCenter.x * sx, rightEyeCenter.y * sy);

          faces.add(AVFaceLike(
            boundingBox: bbox,
            leftEye: leftScaled,
            rightEye: rightScaled,
          ));
        }

        if (!filterByFaceSize || faces.isEmpty) return faces;

        const double minFaceSize = 0.1;
        final filtered = faces.where((f) => (f.boundingBox.width / width) > minFaceSize).toList();
        return filtered.isNotEmpty ? filtered : faces;
      } else {
        final List<Face> faces = await faceDetector!.processImage(
          InputImage.fromFilePath(imagePath),
        );
        if (!filterByFaceSize || faces.isEmpty) return faces;
        return await _filterFacesBySize(faces, imageWidth, imagePath);
      }
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
