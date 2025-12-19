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
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as fdl;
import 'package:opencv_dart/opencv_dart.dart' as cv;
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
  static fdl.FaceDetectorIsolate? _faceDetectorIsolate;

  static Future<void> _ensureFDLite() async {
    if (_faceDetectorIsolate == null || !_faceDetectorIsolate!.isReady) {
      _faceDetectorIsolate = await fdl.FaceDetectorIsolate.spawn(
        model: fdl.FaceDetectionModel.backCamera,
      );
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

  static Future<List<dynamic>?> getFacesFromBytes(
    Uint8List bytes,
    FaceDetector? faceDetector, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await _ensureFDLite();

        // Face detection runs entirely in background isolate - UI never blocked
        final facesDetected = await _faceDetectorIsolate!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.full,
        );

        if (facesDetected.isEmpty) {
          return [];
        }

        // Get image width from first detected face's originalSize
        final double w = facesDetected.first.originalSize.width;

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
        // Mobile path: write to temp file for google_mlkit
        final Directory tempDir = await getTemporaryDirectory();
        final String tempPath = path.join(tempDir.path, 'temp_face_detection_${DateTime.now().millisecondsSinceEpoch}.png');
        final File tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes);

        try {
          final List<Face> faces = await faceDetector!.processImage(
            InputImage.fromFilePath(tempPath),
          );

          if (!filterByFaceSize || faces.isEmpty) return faces;

          // For mobile, use opencv to get width if not provided
          if (imageWidth == null) {
            final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
            imageWidth = mat.cols;
            mat.dispose();
          }

          return await _filterFacesBySize(faces, imageWidth, tempPath);
        } finally {
          // Clean up temp file
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      }
    } catch(e) {
      print("Error caught while fetching faces from bytes: $e");
      return [];
    }
  }

  static Future<List<dynamic>?> getFacesFromFilepath(
    String imagePath,
    FaceDetector? faceDetector, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    final bool fileExists = await File(imagePath).exists();
    if (!fileExists) {
      return null;
    }

    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await _ensureFDLite();

        final bytes = await File(imagePath).readAsBytes();

        // Face detection runs entirely in background isolate - UI never blocked
        final facesDetected = await _faceDetectorIsolate!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.full,
        );

        if (facesDetected.isEmpty) {
          return [];
        }

        // Get image width from first detected face's originalSize
        final double w = facesDetected.first.originalSize.width;

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
    if (bytes == null) {
      throw Exception('Unable to read image file');
    }

    final dims = await getImageDimensionsFromBytesAsync(bytes);
    if (dims == null) {
      throw Exception('Unable to decode image');
    }

    return dims;
  }

  static Future<void> performFileOperationInBackground(Map<String, dynamic> params) async {
    SendPort sendPort = params['sendPort'];
    String? filePath = params['filePath'];
    var operation = params['operation'];
    var bytes = params['bytes'];

    switch (operation) {
      case 'readToPng':
        // Read any image format and return PNG bytes
        try {
          final fileBytes = await File(filePath!).readAsBytes();
          final mat = cv.imdecode(fileBytes, cv.IMREAD_COLOR);
          if (mat.isEmpty) {
            mat.dispose();
            sendPort.send(null);
            return;
          }
          final (success, pngBytes) = cv.imencode('.png', mat);
          mat.dispose();
          sendPort.send(success ? pngBytes : null);
        } catch (e) {
          sendPort.send(null);
        }
        break;
      case 'writePngFromBytes':
        // Write bytes directly as PNG file
        try {
          if (bytes != null) {
            await File(filePath!).writeAsBytes(bytes as Uint8List);
            sendPort.send('File written successfully');
          } else {
            sendPort.send('Bytes are null');
          }
        } catch (e) {
          sendPort.send('Error writing PNG: $e');
        }
        break;
      case 'writeJpg':
        // Convert PNG bytes to JPG and write
        try {
          if (bytes != null) {
            final mat = cv.imdecode(bytes as Uint8List, cv.IMREAD_COLOR);
            if (mat.isEmpty) {
              mat.dispose();
              sendPort.send('Decoded mat is empty');
              return;
            }
            final (success, jpgBytes) = cv.imencode('.jpg', mat, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
            mat.dispose();
            if (success) {
              await File(filePath!).writeAsBytes(jpgBytes);
              sendPort.send('File written successfully');
            } else {
              sendPort.send('Failed to encode JPG');
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
        // Composite PNG on black background
        try {
          final input = bytes as Uint8List;
          final mat = cv.imdecode(input, cv.IMREAD_UNCHANGED);
          if (mat.isEmpty) {
            mat.dispose();
            sendPort.send('Error compositeBlackPng: empty mat');
            return;
          }

          cv.Mat result;
          if (mat.channels == 4) {
            // Has alpha channel - composite on black
            final bg = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC3);
            final channels = cv.split(mat);
            final bgr = cv.merge(cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
            final alpha = channels[3];
            bgr.copyTo(bg, mask: alpha);
            for (final ch in channels) {
              ch.dispose();
            }
            bgr.dispose();
            result = bg;
          } else {
            result = mat.clone();
          }
          mat.dispose();

          final (success, pngBytes) = cv.imencode('.png', result);
          result.dispose();
          sendPort.send(success ? pngBytes : 'Error compositeBlackPng: encode failed');
        } catch (e) {
          sendPort.send('Error compositeBlackPng: $e');
        }
        break;
      case 'thumbnailFromPng':
        // Create thumbnail from PNG with black background composite
        try {
          final input = bytes as Uint8List;
          final mat = cv.imdecode(input, cv.IMREAD_UNCHANGED);
          if (mat.isEmpty) {
            mat.dispose();
            sendPort.send('Error thumbnailFromPng: empty mat');
            return;
          }

          cv.Mat composited;
          if (mat.channels == 4) {
            // Has alpha channel - composite on black
            final bg = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC3);
            final channels = cv.split(mat);
            final bgr = cv.merge(cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
            final alpha = channels[3];
            bgr.copyTo(bg, mask: alpha);
            for (final ch in channels) {
              ch.dispose();
            }
            bgr.dispose();
            composited = bg;
          } else {
            composited = mat.clone();
          }
          mat.dispose();

          // Resize to 500px width
          final aspectRatio = composited.rows / composited.cols;
          final height = (500 * aspectRatio).round();
          final thumb = cv.resize(composited, (500, height));
          composited.dispose();

          final (success, jpgBytes) = cv.imencode('.jpg', thumb, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
          thumb.dispose();
          sendPort.send(success ? jpgBytes : 'Error thumbnailFromPng: encode failed');
        } catch (e) {
          sendPort.send('Error thumbnailFromPng: $e');
        }
        break;
    }
  }

  /// Read any image file and return PNG bytes (using opencv for fast native decoding)
  static Future<Uint8List?> readImageAsPngBytesInIsolate(String filePath) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'operation': 'readToPng'
    };

    Isolate? isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params
    );
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result as Uint8List?;
  }

  /// Write PNG bytes to file
  static Future<void> writePngBytesToFileInIsolate(
    String filepath,
    Uint8List pngBytes
  ) async {
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filepath,
      'bytes': pngBytes,
      'operation': 'writePngFromBytes'
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
        if (result.exitCode != 0 || !await File(jpgImgPath).exists()) {
          return;
        }
      } else {
        await HeifConverter.convert(
          imgPath,
          output: jpgImgPath,
          format: 'jpeg',
        );
        if (!await File(jpgImgPath).exists()) {
          return;
        }
      }

      imgPath = jpgImgPath;
    }

    final Uint8List? pngBytes = await readImageAsPngBytesInIsolate(imgPath);
    if (pngBytes != null) {
      await writePngBytesToFileInIsolate(pngPath, pngBytes);
    }

    if (conversionToJpgNeeded) {
      await ProjectUtils.deleteFile(File(jpgImgPath));
    }
  }


  static Future<File> flipImageHorizontally(String imagePath) async {
    return await processImageInIsolate(imagePath, 'flip_horizontal', '_flipped.png');
  }

  // Rotate Image 90 Degrees Clockwise
  static Future<File> rotateImageClockwise(String imagePath) async {
    return await processImageInIsolate(imagePath, 'rotate_clockwise', '_rotated_clockwise.png');
  }

  // Rotate Image 90 Degrees Counter-Clockwise
  static Future<File> rotateImageCounterClockwise(String imagePath) async {
    return await processImageInIsolate(imagePath, 'rotate_counter_clockwise', '_rotated_counter_clockwise.png');
  }

  static Future<void> performImageProcessingInBackground(Map<String, dynamic> params) async {
    final rootIsolateToken = params['rootIsolateToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

    SendPort sendPort = params['sendPort'];
    String filePath = params['filePath'];
    String suffix = params['suffix'];
    String operation = params['operation'];

    try {
      final Uint8List imageBytes = await File(filePath).readAsBytes();
      final mat = cv.imdecode(imageBytes, cv.IMREAD_COLOR);

      if (mat.isEmpty) {
        mat.dispose();
        throw Exception('Failed to decode image');
      }

      cv.Mat processedMat;
      switch (operation) {
        case 'flip_horizontal':
          processedMat = cv.flip(mat, 1); // 1 = horizontal
          break;
        case 'rotate_clockwise':
          processedMat = cv.rotate(mat, cv.ROTATE_90_CLOCKWISE);
          break;
        case 'rotate_counter_clockwise':
          processedMat = cv.rotate(mat, cv.ROTATE_90_COUNTERCLOCKWISE);
          break;
        default:
          processedMat = mat.clone();
      }
      mat.dispose();

      final Directory tempDir = await getTemporaryDirectory();
      final String name = path.basenameWithoutExtension(filePath);

      final String newName = '$name$suffix';
      final String newPath = path.join(tempDir.path, newName);
      final File processedImageFile = File(newPath);

      final (success, pngBytes) = cv.imencode('.png', processedMat);
      processedMat.dispose();

      if (!success) {
        throw Exception('Failed to encode PNG');
      }

      await processedImageFile.writeAsBytes(pngBytes);
      sendPort.send(processedImageFile);
    } catch (e) {
      sendPort.send(e);
    }
  }

  static Future<File> processImageInIsolate(String imagePath, String operation, String suffix) async {
    ReceivePort receivePort = ReceivePort();
    final rootIsolateToken = RootIsolateToken.instance;
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': imagePath,
      'operation': operation,
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

  /// Load image as cv.Mat from PNG file path (desktop only)
  /// Returns the raw bytes so caller can decode to Mat synchronously after async read
  static Future<Uint8List?> loadPngBytesAsync(String pngPath) async {
    if (!await File(pngPath).exists()) return null;
    return await File(pngPath).readAsBytes();
  }

  /// Isolate entry point for getting image dimensions
  static void _getImageDimensionsIsolate(Map<String, dynamic> params) {
    final SendPort sendPort = params['sendPort'];
    final Uint8List bytes = params['bytes'];

    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) {
        mat.dispose();
        sendPort.send(null);
        return;
      }
      final dims = (mat.cols, mat.rows);
      mat.dispose();
      sendPort.send(dims);
    } catch (e) {
      sendPort.send(null);
    }
  }

  /// Get image dimensions from bytes asynchronously (runs decode in isolate)
  static Future<(int, int)?> getImageDimensionsFromBytesAsync(Uint8List bytes) async {
    final ReceivePort receivePort = ReceivePort();
    final params = {
      'sendPort': receivePort.sendPort,
      'bytes': bytes,
    };

    final isolate = await Isolate.spawn(_getImageDimensionsIsolate, params);
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);

    return result as (int, int)?;
  }

  /// Generate stabilized image bytes using OpenCV warpAffine (desktop only)
  /// This is faster than Flutter's Canvas-based approach due to SIMD optimization
  static Uint8List? generateStabilizedImageBytesCV(
    cv.Mat srcMat,
    double rotationDegrees,
    double scaleFactor,
    double translateX,
    double translateY,
    int canvasWidth,
    int canvasHeight,
  ) {
    final int iw = srcMat.cols;
    final int ih = srcMat.rows;

    // Create rotation matrix centered at image center
    // Negate angle to match Flutter Canvas rotation convention
    final cv.Mat rotMat = cv.getRotationMatrix2D(
      cv.Point2f(iw / 2.0, ih / 2.0),
      -rotationDegrees,
      scaleFactor,
    );

    // Adjust translation to center scaled image in canvas + apply user translation
    final double offsetX = (canvasWidth - iw) / 2.0 + translateX;
    final double offsetY = (canvasHeight - ih) / 2.0 + translateY;
    rotMat.set<double>(0, 2, rotMat.at<double>(0, 2) + offsetX);
    rotMat.set<double>(1, 2, rotMat.at<double>(1, 2) + offsetY);

    // Apply affine transformation
    final cv.Mat dst = cv.warpAffine(
      srcMat,
      rotMat,
      (canvasWidth, canvasHeight),
      borderMode: cv.BORDER_CONSTANT,
      borderValue: cv.Scalar.black,
    );

    // Encode to PNG
    final (bool success, Uint8List bytes) = cv.imencode('.png', dst);

    // Cleanup
    rotMat.dispose();
    dst.dispose();

    return success ? bytes : null;
  }

  /// Isolate entry point for CV stabilization
  static void _stabilizeCVIsolate(Map<String, dynamic> params) {
    final SendPort sendPort = params['sendPort'];
    final Uint8List srcBytes = params['srcBytes'];
    final double rotationDegrees = params['rotationDegrees'];
    final double scaleFactor = params['scaleFactor'];
    final double translateX = params['translateX'];
    final double translateY = params['translateY'];
    final int canvasWidth = params['canvasWidth'];
    final int canvasHeight = params['canvasHeight'];

    try {
      final cv.Mat srcMat = cv.imdecode(srcBytes, cv.IMREAD_COLOR);
      if (srcMat.isEmpty) {
        srcMat.dispose();
        sendPort.send(null);
        return;
      }

      final int iw = srcMat.cols;
      final int ih = srcMat.rows;

      final cv.Mat rotMat = cv.getRotationMatrix2D(
        cv.Point2f(iw / 2.0, ih / 2.0),
        -rotationDegrees,
        scaleFactor,
      );

      final double offsetX = (canvasWidth - iw) / 2.0 + translateX;
      final double offsetY = (canvasHeight - ih) / 2.0 + translateY;
      rotMat.set<double>(0, 2, rotMat.at<double>(0, 2) + offsetX);
      rotMat.set<double>(1, 2, rotMat.at<double>(1, 2) + offsetY);

      final cv.Mat dst = cv.warpAffine(
        srcMat,
        rotMat,
        (canvasWidth, canvasHeight),
        borderMode: cv.BORDER_CONSTANT,
        borderValue: cv.Scalar.black,
      );

      final (bool success, Uint8List bytes) = cv.imencode('.png', dst);

      rotMat.dispose();
      dst.dispose();
      srcMat.dispose();

      sendPort.send(success ? bytes : null);
    } catch (e) {
      sendPort.send(null);
    }
  }

  /// Async version that runs CV stabilization in an isolate to avoid blocking UI
  static Future<Uint8List?> generateStabilizedImageBytesCVAsync(
    Uint8List srcBytes,
    double rotationDegrees,
    double scaleFactor,
    double translateX,
    double translateY,
    int canvasWidth,
    int canvasHeight,
  ) async {
    final ReceivePort receivePort = ReceivePort();
    final params = {
      'sendPort': receivePort.sendPort,
      'srcBytes': srcBytes,
      'rotationDegrees': rotationDegrees,
      'scaleFactor': scaleFactor,
      'translateX': translateX,
      'translateY': translateY,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
    };

    final isolate = await Isolate.spawn(_stabilizeCVIsolate, params);
    final result = await receivePort.first;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);

    return result as Uint8List?;
  }
}
