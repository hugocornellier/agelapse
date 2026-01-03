import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as fdl;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../services/async_mutex.dart';
import '../../services/cancellation_token.dart';
import '../../services/database_helper.dart';
import '../../services/isolate_manager.dart';
import '../../services/isolate_pool.dart';
import '../../services/log_service.dart';
import '../camera_utils.dart';
import '../dir_utils.dart';
import '../heic_utils.dart';
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

  static final AsyncMutex _faceDetectorMutex = AsyncMutex();

  static Future<void> _ensureFDLite() async {
    if (_faceDetectorIsolate == null || !_faceDetectorIsolate!.isReady) {
      _faceDetectorIsolate = await fdl.FaceDetectorIsolate.spawn(
        model: fdl.FaceDetectionModel.backCamera,
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getUnstabilizedPhotos(
      int projectId) async {
    String projectOrientation =
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    return await DB.instance
        .getUnstabilizedPhotos(projectId, projectOrientation);
  }

  static double? getShortSide(String resolution) {
    // Standard presets
    if (resolution == "1080p") return 1080;
    if (resolution == "4K") return 2304;
    if (resolution == "8K") return 4320;

    // Legacy presets (backwards compatibility with pre-2.2.1 versions)
    if (resolution == "2K") return 1152;
    if (resolution == "3K") return 1728;

    // Handle WIDTHxHEIGHT format (e.g., "1920x1080")
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    if (match != null) {
      final w = double.parse(match.group(1)!);
      final h = double.parse(match.group(2)!);
      return w < h ? w : h; // Return smaller dimension
    }

    // Custom: try parsing as number (e.g., "1728" -> 1728.0)
    final parsed = double.tryParse(resolution);
    if (parsed != null && parsed >= 480 && parsed <= 5400) return parsed;

    return null;
  }

  /// Get both dimensions from a "WIDTHxHEIGHT" format resolution string.
  /// Returns (width, height) or null if not in that format.
  static (int, int)? getDimensions(String resolution) {
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    if (match != null) {
      return (int.parse(match.group(1)!), int.parse(match.group(2)!));
    }
    return null;
  }

  /// Get output canvas dimensions (width, height) for a given resolution setting.
  ///
  /// For custom "WIDTHxHEIGHT" resolutions, returns exact dimensions.
  /// For presets (1080p, 4K, 8K), calculates from short side × aspect ratio.
  /// Returns null if resolution cannot be parsed.
  static (int, int)? getOutputDimensions(
    String resolution,
    String aspectRatio,
    String orientation,
  ) {
    final customDims = getDimensions(resolution);
    if (customDims != null) {
      return customDims;
    }

    final shortSide = getShortSide(resolution);
    final aspectDecimal = getAspectRatioAsDecimal(aspectRatio);
    if (shortSide == null || aspectDecimal == null) return null;

    final longSide = (shortSide * aspectDecimal).toInt();
    final isLandscape = orientation.toLowerCase() == 'landscape';
    final width = isLandscape ? longSide : shortSide.toInt();
    final height = isLandscape ? shortSide.toInt() : longSide;
    return (width, height);
  }

  static double? getAspectRatioAsDecimal(String aspectRatio) {
    if (!aspectRatio.contains(':')) return null;
    final List<String> split = aspectRatio.split(":");
    int? dividend = int.tryParse(split[0]);
    int? divisor = int.tryParse(split[1]);
    if (dividend == null || divisor == null) return null;
    return dividend / divisor;
  }

  /// Result from face detection containing both FaceLike wrappers and raw faces.
  /// The raw faces are needed for embedding extraction.
  static (List<FaceLike>, List<fdl.Face>) _convertFaces(
    List<fdl.Face> facesDetected, {
    bool filterByFaceSize = true,
  }) {
    if (facesDetected.isEmpty) {
      return ([], []);
    }

    // Get image width from first detected face's originalSize
    final double w = facesDetected.first.originalSize.width;

    final List<FaceLike> faces = [];
    final List<fdl.Face> rawFaces = [];

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

      final faceLike = FaceLike(
        boundingBox: bbox,
        leftEye: l,
        rightEye: r,
      );

      if (!filterByFaceSize || (bbox.width / w) > 0.1) {
        faces.add(faceLike);
        rawFaces.add(face);
      }
    }

    // If filtering removed all faces, return original set
    if (faces.isEmpty && facesDetected.isNotEmpty) {
      return _convertFaces(facesDetected, filterByFaceSize: false);
    }

    return (faces, rawFaces);
  }

  static Future<List<FaceLike>?> getFacesFromBytes(
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    final result = await getFacesFromBytesWithRaw(
      bytes,
      filterByFaceSize: filterByFaceSize,
      imageWidth: imageWidth,
    );
    return result?.$1;
  }

  /// Gets faces from bytes, returning both FaceLike wrappers and raw fdl.Face objects.
  /// The raw faces are needed for embedding extraction without re-detecting.
  static Future<(List<FaceLike>, List<fdl.Face>)?> getFacesFromBytesWithRaw(
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();

        // Face detection runs entirely in background isolate - UI never blocked
        final facesDetected = await _faceDetectorIsolate!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.full,
        );

        if (facesDetected.isEmpty) {
          return (<FaceLike>[], <fdl.Face>[]);
        }

        return _convertFaces(facesDetected, filterByFaceSize: filterByFaceSize);
      } catch (e) {
        LogService.instance
            .log("Error caught while fetching faces from bytes: $e");
        return (<FaceLike>[], <fdl.Face>[]);
      }
    });
  }

  static Future<List<FaceLike>?> getFacesFromFilepath(
    String imagePath, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    final bool fileExists = await File(imagePath).exists();
    if (!fileExists) {
      return null;
    }

    // Read file bytes outside mutex (doesn't need face detector)
    final bytes = await File(imagePath).readAsBytes();

    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
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
      } catch (e) {
        LogService.instance.log("Error caught while fetching faces: $e");
        return [];
      }
    });
  }

  // ============================================================
  // Face Embedding Methods for identity-based face matching
  // ============================================================

  /// Gets face embedding for the first detected face in the image.
  /// Used for single-face photos to store reference embeddings.
  /// Returns null if no faces detected or embedding extraction fails.
  static Future<Float32List?> getFaceEmbeddingFromBytes(Uint8List bytes) async {
    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();

        final faces = await _faceDetectorIsolate!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.fast,
        );

        if (faces.isEmpty) return null;

        final embedding = await _faceDetectorIsolate!.getFaceEmbedding(
          faces.first,
          bytes,
        );

        return embedding;
      } catch (e) {
        LogService.instance.log("Error extracting face embedding: $e");
        return null;
      }
    });
  }

  /// Gets face embeddings for all detected faces in the image.
  /// Returns a list of embeddings (may contain nulls for faces where extraction failed).
  static Future<List<Float32List?>> getFaceEmbeddingsFromBytes(
      Uint8List bytes) async {
    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();

        final faces = await _faceDetectorIsolate!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.fast,
        );

        if (faces.isEmpty) return [];

        final embeddings = await _faceDetectorIsolate!.getFaceEmbeddings(
          faces,
          bytes,
        );

        return embeddings;
      } catch (e) {
        LogService.instance.log("Error extracting face embeddings: $e");
        return [];
      }
    });
  }

  /// Picks the face index with highest similarity to the reference embedding.
  /// Returns -1 if no match found above threshold, or falls back to first face.
  /// [referenceEmbedding] is the 192-dim embedding from a single-face photo.
  /// [imageBytes] is the raw image bytes (needed for embedding extraction).
  /// [preDetectedFaces] optional pre-detected faces to avoid redundant detection.
  static Future<int> pickFaceIndexByEmbedding(
    Float32List referenceEmbedding,
    Uint8List imageBytes, {
    List<fdl.Face>? preDetectedFaces,
  }) async {
    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();

        // Use pre-detected faces if available, otherwise detect
        final List<fdl.Face> faces;
        if (preDetectedFaces != null && preDetectedFaces.isNotEmpty) {
          faces = preDetectedFaces;
          LogService.instance.log(
              "Using ${faces.length} pre-detected faces for embedding matching");
        } else {
          faces = await _faceDetectorIsolate!.detectFaces(
            imageBytes,
            mode: fdl.FaceDetectionMode.fast,
          );
        }

        if (faces.isEmpty) return -1;
        if (faces.length == 1) return 0;

        int bestIndex = 0;
        double bestSimilarity = -1.0;

        for (int i = 0; i < faces.length; i++) {
          final embedding = await _faceDetectorIsolate!.getFaceEmbedding(
            faces[i],
            imageBytes,
          );

          final similarity =
              fdl.FaceDetector.compareFaces(referenceEmbedding, embedding);

          LogService.instance.log(
              "Face $i embedding similarity: ${similarity.toStringAsFixed(3)}");

          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestIndex = i;
          }
        }

        LogService.instance.log(
            "Selected face $bestIndex with similarity ${bestSimilarity.toStringAsFixed(3)}");

        return bestIndex;
      } catch (e) {
        LogService.instance.log("Error in embedding-based face selection: $e");
        return 0; // Fallback to first face
      }
    });
  }

  /// Converts a Float32List embedding to Uint8List for database storage.
  static Uint8List embeddingToBytes(Float32List embedding) {
    return embedding.buffer.asUint8List();
  }

  /// Converts a Uint8List from database back to Float32List embedding.
  static Float32List bytesToEmbedding(Uint8List bytes) {
    return bytes.buffer.asFloat32List();
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

  static Future<void> performFileOperationInBackground(
      Map<String, dynamic> params) async {
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
            final (success, jpgBytes) = cv.imencode('.jpg', mat,
                params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
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
            final bgr = cv.merge(
                cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
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
          sendPort.send(
              success ? pngBytes : 'Error compositeBlackPng: encode failed');
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
            final bgr = cv.merge(
                cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
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

          final (success, jpgBytes) = cv.imencode('.jpg', thumb,
              params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
          thumb.dispose();
          sendPort.send(
              success ? jpgBytes : 'Error thumbnailFromPng: encode failed');
        } catch (e) {
          sendPort.send('Error thumbnailFromPng: $e');
        }
        break;
    }
  }

  /// Read any image file and return PNG bytes (using opencv for fast native decoding)
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<Uint8List?> readImageAsPngBytesInIsolate(String filePath,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      return await IsolatePool.instance.execute<Uint8List>(
        'readToPng',
        {'filePath': filePath},
      );
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'operation': 'readToPng'
    };

    final isolate =
        await Isolate.spawn(performFileOperationInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first;
      return result as Uint8List?;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Write PNG bytes to file
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<void> writePngBytesToFileInIsolate(
      String filepath, Uint8List pngBytes,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      await IsolatePool.instance.execute(
        'writePngFromBytes',
        {'filePath': filepath, 'bytes': pngBytes},
      );
      return;
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filepath,
      'bytes': pngBytes,
      'operation': 'writePngFromBytes'
    };

    final isolate =
        await Isolate.spawn(performFileOperationInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      await receivePort.first;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Composite PNG on black background.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<Uint8List> compositeBlackPngBytes(Uint8List pngBytes,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      final result = await IsolatePool.instance.execute<Uint8List>(
        'compositeBlackPng',
        {'bytes': pngBytes},
      );
      return result ?? pngBytes; // Fallback to original if composite fails
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'bytes': pngBytes,
      'operation': 'compositeBlackPng'
    };

    final isolate =
        await Isolate.spawn(performFileOperationInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first as Uint8List;
      return result;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Create thumbnail JPG from PNG bytes.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<Uint8List> thumbnailJpgFromPngBytes(Uint8List pngBytes,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      final result = await IsolatePool.instance.execute<Uint8List>(
        'thumbnailFromPng',
        {'bytes': pngBytes},
      );
      return result ?? pngBytes; // Fallback to original if thumbnail fails
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'bytes': pngBytes,
      'operation': 'thumbnailFromPng'
    };

    final isolate =
        await Isolate.spawn(performFileOperationInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first as Uint8List;
      return result;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Write bytes to JPG file.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<void> writeBytesToJpgFileInIsolate(
      String filePath, List<int> bytes,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      await IsolatePool.instance.execute(
        'writeJpg',
        {'filePath': filePath, 'bytes': Uint8List.fromList(bytes)},
      );
      return;
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'bytes': bytes,
      'operation': 'writeJpg'
    };

    final isolate =
        await Isolate.spawn(performFileOperationInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first;
      if (result == 'NoSpaceLeftError') {
        throw const FileSystemException('NoSpaceLeftError');
      }
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  static Future<bool> writeImagesBytesToJpgFile(
      Uint8List bytes, String imagePath) async {
    await DirUtils.createDirectoryIfNotExists(imagePath);
    await writeBytesToJpgFileInIsolate(imagePath, bytes);
    return true;
  }

  /// Prepares a PNG version of the image and returns the PNG bytes.
  /// Also writes to disk for caching. If PNG already exists, reads and returns it.
  static Future<Uint8List?> preparePNG(String imgPath) async {
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(imgPath);
    await DirUtils.createDirectoryIfNotExists(pngPath);
    final File pngFile = File(pngPath);

    final bool rawExists = await File(imgPath).exists();
    if (!rawExists) {
      return null;
    }

    // If PNG already cached, read and return those bytes directly
    final bool pngExists = await pngFile.exists();
    if (pngExists) {
      final int len = await pngFile.length();
      if (len > 0) {
        return await pngFile.readAsBytes();
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
          return null;
        }
      } else if (Platform.isWindows) {
        final success = await HeicUtils.convertHeicToJpgAt(imgPath, jpgImgPath);
        if (!success) {
          return null;
        }
      } else {
        // iOS/Android - use heif_converter package
        await HeifConverter.convert(
          imgPath,
          output: jpgImgPath,
          format: 'jpeg',
        );
        if (!await File(jpgImgPath).exists()) {
          return null;
        }
      }

      imgPath = jpgImgPath;
    }

    final Uint8List? pngBytes = await readImageAsPngBytesInIsolate(imgPath);
    if (pngBytes != null) {
      // Write to disk for caching (fire-and-forget for future runs)
      await writePngBytesToFileInIsolate(pngPath, pngBytes);
    }

    if (conversionToJpgNeeded) {
      await ProjectUtils.deleteFile(File(jpgImgPath));
    }

    // Return bytes directly - caller doesn't need to read from disk
    return pngBytes;
  }

  static Future<File> flipImageHorizontally(String imagePath) async {
    return await processImageInIsolate(
        imagePath, 'flip_horizontal', '_flipped.png');
  }

  // Rotate Image 90 Degrees Clockwise
  static Future<File> rotateImageClockwise(String imagePath) async {
    return await processImageInIsolate(
        imagePath, 'rotate_clockwise', '_rotated_clockwise.png');
  }

  // Rotate Image 90 Degrees Counter-Clockwise
  static Future<File> rotateImageCounterClockwise(String imagePath) async {
    return await processImageInIsolate(imagePath, 'rotate_counter_clockwise',
        '_rotated_counter_clockwise.png');
  }

  static Future<void> performImageProcessingInBackground(
      Map<String, dynamic> params) async {
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

  static Future<File> processImageInIsolate(
      String imagePath, String operation, String suffix,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    ReceivePort receivePort = ReceivePort();
    final rootIsolateToken = RootIsolateToken.instance;
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': imagePath,
      'operation': operation,
      'suffix': suffix,
      'rootIsolateToken': rootIsolateToken
    };

    final isolate =
        await Isolate.spawn(performImageProcessingInBackground, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first;
      if (result is File) {
        return result;
      } else {
        throw result;
      }
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  static Future<String> getStabilizedImagePath(String originalFilePath,
      int projectId, String? projectOrientation) async {
    final stabilizedDirectoryPath =
        await DirUtils.getStabilizedDirPath(projectId);
    final String originalBasename =
        path.basenameWithoutExtension(originalFilePath);
    return path.join(
        stabilizedDirectoryPath, projectOrientation, '$originalBasename.jpg');
  }

  static Future<ui.Image?> loadImageFromFile(File file) async {
    const int maxWaitSec = 10;
    final Stopwatch sw = Stopwatch()..start();

    while (!(await file.exists())) {
      if (sw.elapsed.inSeconds >= maxWaitSec) {
        debugPrint(
            "Error loading image: file not found within $maxWaitSec seconds");
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
          debugPrint(
              "Error loading image: not decodable within $maxWaitSec seconds");
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
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<(int, int)?> getImageDimensionsFromBytesAsync(Uint8List bytes,
      {CancellationToken? token}) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      return await IsolatePool.instance.execute<(int, int)>(
        'getImageDimensions',
        {'bytes': bytes},
      );
    }

    // Fallback to individual isolate if pool not initialized
    final ReceivePort receivePort = ReceivePort();
    final params = {
      'sendPort': receivePort.sendPort,
      'bytes': bytes,
    };

    final isolate = await Isolate.spawn(_getImageDimensionsIsolate, params);
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first;
      return result as (int, int)?;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Generate stabilized image bytes using OpenCV warpAffine (desktop only)
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

  /// Async version that runs CV stabilization in an isolate to avoid blocking UI.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  ///
  /// When [srcId] is provided, the decoded source Mat is cached in the worker.
  /// Call [IsolatePool.instance.clearMatCache()] after finishing each photo.
  static Future<Uint8List?> generateStabilizedImageBytesCVAsync(
    Uint8List srcBytes,
    double rotationDegrees,
    double scaleFactor,
    double translateX,
    double translateY,
    int canvasWidth,
    int canvasHeight, {
    CancellationToken? token,
    String? srcId,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      return await IsolatePool.instance.execute<Uint8List>(
        'stabilizeCV',
        {
          'srcBytes': srcBytes,
          'rotationDegrees': rotationDegrees,
          'scaleFactor': scaleFactor,
          'translateX': translateX,
          'translateY': translateY,
          'canvasWidth': canvasWidth,
          'canvasHeight': canvasHeight,
          'srcId': srcId,
        },
      );
    }

    // Fallback to individual isolate if pool not initialized
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
    IsolateManager.instance.register(isolate);

    try {
      final result = await receivePort.first;
      return result as Uint8List?;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }
}
