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
import 'package:pose_detection_tflite/pose_detection_tflite.dart' as pdl;

import '../../services/database_helper.dart';
import '../camera_utils.dart';
import '../dir_utils.dart';
import '../project_utils.dart';
import '../settings_utils.dart';

class FaceLike {
  final Rect boundingBox;
  final Point<double>? leftEye;
  final Point<double>? rightEye;

  FaceLike({
    required this.boundingBox,
    required this.leftEye,
    required this.rightEye,
  });
}

class StabUtils {
  static fdl.FaceDetector? _faceDetector;
  static bool _fdLiteReady = false;

  static Future<void> _ensureFDLite() async {
    if (_faceDetector == null) {
      _faceDetector = fdl.FaceDetector();
      await _faceDetector!.initialize(model: fdl.FaceDetectionModel.backCamera);
      _fdLiteReady = true;
    } else if (!_fdLiteReady) {
      await _faceDetector!.initialize(model: fdl.FaceDetectionModel.backCamera);
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
    FaceDetector? faceDetector, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    final bool fileExists = File(imagePath).existsSync();
    if (!fileExists) {
      return null;
    }

    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await _ensureFDLite();

        final bytes = await File(imagePath).readAsBytes();
        final imglib.Image? decodedImg = imglib.decodeImage(bytes);
        if (decodedImg == null) {
          return [];
        }
        final double w = decodedImg.width.toDouble();

        final facesDetected = await _faceDetector!.detectFaces(bytes);

        final List<FaceLike> faces = [];
        for (final face in facesDetected) {
          final boundingBox = face.boundingBox;
          final Rect bbox = Rect.fromLTRB(
            boundingBox.topLeft.x,
            boundingBox.topLeft.y,
            boundingBox.bottomRight.x,
            boundingBox.bottomRight.y,
          );

          final landmarks = face.landmarks;
          final Point<double>? l = landmarks.leftEye != null
              ? Point(landmarks.leftEye!.x, landmarks.leftEye!.y)
              : null;
          final Point<double>? r = landmarks.rightEye != null
              ? Point(landmarks.rightEye!.x, landmarks.rightEye!.y)
              : null;

          faces.add(
            FaceLike(
              boundingBox: bbox,
              leftEye: l,
              rightEye: r,
            ),
          );
        }

        if (!filterByFaceSize || faces.isEmpty) return faces;

        const double minFaceSize = 0.1;
        final filtered = faces
            .where((f) => (f.boundingBox.width / w) > minFaceSize)
            .toList();
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
    String? filePath = params['filePath'];
    var operation = params['operation'];
    imglib.Image? bitmap = params['bitmap'];
    var bytes = params['bytes'];

    switch (operation) {
      case 'readJpg':
        try {
          String extension = path.extension(filePath!).toLowerCase();
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
            await File(filePath!).writeAsBytes(bytes!);
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
              await File(filePath!).writeAsBytes(bytes);
              sendPort.send('File written successfully');
            } else {
              sendPort.send('Decoded bitmap is null');
            }
          } else {
            sendPort.send('Bytes are null');
          }
        } catch (e) {
          if (e is FileSystemException && e.osError?.errorCode == 28) {
            sendPort.send('NoSpaceLeftError');
          } else {
            sendPort.send('Error writing JPG: $e');
          }
        }
        break;
      case 'compositeBlackPng':
        try {
          final input = bytes as Uint8List;
          final decoded = imglib.decodePng(input);
          final bg = imglib.Image(width: decoded!.width, height: decoded.height);
          imglib.fill(bg, color: imglib.ColorRgb8(0, 0, 0));
          imglib.compositeImage(bg, decoded);
          final out = imglib.encodePng(bg);
          sendPort.send(Uint8List.fromList(out));
        } catch (e) {
          sendPort.send('Error compositeBlackPng: $e');
        }
        break;
      case 'thumbnailFromPng':
        try {
          final input = bytes as Uint8List;
          final decoded = imglib.decodePng(input);
          final bg = imglib.Image(width: decoded!.width, height: decoded.height, numChannels: 4);
          imglib.fill(bg, color: imglib.ColorRgb8(0, 0, 0));
          imglib.compositeImage(bg, decoded);
          final thumb = imglib.copyResize(bg, width: 500);
          final out = imglib.encodeJpg(thumb);
          sendPort.send(Uint8List.fromList(out));
        } catch (e) {
          sendPort.send('Error thumbnailFromPng: $e');
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

    Isolate? isolate = await Isolate.spawn(
      performFileOperationInBackground, 
      params
    );
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result as imglib.Image?;
  }

  static Future<void> writeBitmapToPngFileInIsolate(
    String filepath, 
    imglib.Image bitmap
  ) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filepath,
      'bitmap': bitmap,
      'operation': 'writePng'
    };

    Isolate? isolate = await Isolate.spawn(
      performFileOperationInBackground, 
      params
    );
    await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }

  static Future<Uint8List> compositeBlackPngBytes(Uint8List pngBytes) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'bytes': pngBytes,
      'operation': 'compositeBlackPng'
    };
    Isolate? isolate = await Isolate.spawn(performFileOperationInBackground, params);
    final result = await receivePort.first as Uint8List;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result;
  }

  static Future<Uint8List> thumbnailJpgFromPngBytes(Uint8List pngBytes) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'bytes': pngBytes,
      'operation': 'thumbnailFromPng'
    };
    Isolate? isolate = await Isolate.spawn(performFileOperationInBackground, params);
    final result = await receivePort.first as Uint8List;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result;
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
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    if (result == 'NoSpaceLeftError') {
      throw const FileSystemException('NoSpaceLeftError');
    }
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

    final bool rawExists = await File(imgPath).exists();
    if (!rawExists) {
      return;
    }

    final bool pngExists = await pngFile.exists();
    if (pngExists) {
      final int len = await pngFile.length();
      if (len > 0) {
        return;
      }
    }

    bool conversionToJpgNeeded = false;
    String jpgImgPath = "";

    final String lowerExt = path.extension(imgPath).toLowerCase();
    if (lowerExt == ".heic" || lowerExt == ".heif") {
      conversionToJpgNeeded = true;
      jpgImgPath = path.setExtension(imgPath, ".jpg");

      if (Platform.isMacOS) {
        final result = await Process.run(
          'sips',
          ['-s', 'format', 'jpeg', imgPath, '--out', jpgImgPath],
        );
        if (result.exitCode != 0 || !File(jpgImgPath).existsSync()) {
          return;
        }
      } else {
        await HeifConverter.convert(
          imgPath,
          output: jpgImgPath,
          format: 'jpeg',
        );
        if (!File(jpgImgPath).existsSync()) {
          return;
        }
      }

      imgPath = jpgImgPath;
    }

    final imglib.Image? bitmap = await getBitmapInIsolate(imgPath);
    if (bitmap != null) {
      await writeBitmapToPngFileInIsolate(pngPath, bitmap);
    }

    if (conversionToJpgNeeded) {
      await ProjectUtils.deleteFile(File(jpgImgPath));
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

    Isolate? isolate = await Isolate.spawn(
      performImageProcessingInBackground, 
      params
    );
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);

    if (result is File) {
      return result;
    } else {
      throw result;
    }
  }

  static Future<String> getStabilizedImagePath(
    String originalFilePath, 
    int projectId, 
    String? projectOrientation
  ) async {
    final stabilizedDirectoryPath = await DirUtils.getStabilizedDirPath(projectId);
    final String originalBasename = path.basenameWithoutExtension(originalFilePath);
    return path.join(stabilizedDirectoryPath, projectOrientation, '$originalBasename.jpg');
  }

  static Future<ui.Image?> loadImageFromFile(File file) async {
    const int maxWaitSec = 10;
    final Stopwatch sw = Stopwatch()..start();

    while (!(await file.exists())) {
      if (sw.elapsed.inSeconds >= maxWaitSec) {
        debugPrint("Error loading image: file not found within $maxWaitSec seconds");
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    while (true) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final ui.Image img = await decodeImageFromList(bytes);
        return img;
      } catch (_) {
        if (sw.elapsed.inSeconds >= maxWaitSec) {
          debugPrint("Error loading image: not decodable within $maxWaitSec seconds");
          return null;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}
