import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:cat_detection/cat_detection.dart' as cat;
import 'package:dog_detection/dog_detection.dart' as dog;
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

  /// Serialize to isolate-safe map.
  Map<String, dynamic> toMap() => {
        'bbox': [
          boundingBox.left,
          boundingBox.top,
          boundingBox.right,
          boundingBox.bottom,
        ],
        'leftEye': leftEye != null ? [leftEye!.x, leftEye!.y] : null,
        'rightEye': rightEye != null ? [rightEye!.x, rightEye!.y] : null,
      };

  /// Deserialize from isolate-safe map.
  factory FaceLike.fromMap(Map<String, dynamic> m) {
    final bbox = m['bbox'] as List;
    final left = m['leftEye'] as List?;
    final right = m['rightEye'] as List?;
    return FaceLike(
      boundingBox: Rect.fromLTRB(
        (bbox[0] as num).toDouble(),
        (bbox[1] as num).toDouble(),
        (bbox[2] as num).toDouble(),
        (bbox[3] as num).toDouble(),
      ),
      leftEye: left != null
          ? Point<double>(
              (left[0] as num).toDouble(),
              (left[1] as num).toDouble(),
            )
          : null,
      rightEye: right != null
          ? Point<double>(
              (right[0] as num).toDouble(),
              (right[1] as num).toDouble(),
            )
          : null,
    );
  }
}

class StabUtils {
  static fdl.FaceDetector? _faceDetector;

  static final AsyncMutex _faceDetectorMutex = AsyncMutex();

  /// Returns [current] if non-null and [isReady] is true; otherwise calls [spawn].
  static Future<T> _ensureDetector<T>(
    T? current,
    bool Function(T) isReady,
    Future<T> Function() spawn,
  ) async {
    if (current == null || !isReady(current)) return await spawn();
    return current;
  }

  static Future<void> _ensureFDLite() async {
    _faceDetector = await _ensureDetector<fdl.FaceDetector>(
      _faceDetector,
      (d) => d.isReady,
      () async {
        final detector = fdl.FaceDetector();
        await detector.initialize(
          model: fdl.FaceDetectionModel.backCamera,
        );
        return detector;
      },
    );
  }

  // ============================================================
  // Cat Detection
  // ============================================================

  static cat.CatDetectorIsolate? _catDetectorIsolate;
  static final AsyncMutex _catDetectorMutex = AsyncMutex();

  static Future<void> _ensureCatDetector() async {
    _catDetectorIsolate = await _ensureDetector<cat.CatDetectorIsolate>(
      _catDetectorIsolate,
      (d) => d.isReady,
      () => cat.CatDetectorIsolate.spawn(mode: cat.CatDetectionMode.full),
    );
  }

  static Future<void> disposeCatDetector() async {
    await _catDetectorIsolate?.dispose();
    _catDetectorIsolate = null;
  }

  // ============================================================
  // Dog Detection
  // ============================================================

  static dog.DogDetectorIsolate? _dogDetectorIsolate;
  static final AsyncMutex _dogDetectorMutex = AsyncMutex();

  static Future<void> _ensureDogDetector() async {
    _dogDetectorIsolate = await _ensureDetector<dog.DogDetectorIsolate>(
      _dogDetectorIsolate,
      (d) => d.isReady,
      () => dog.DogDetectorIsolate.spawn(mode: dog.DogDetectionMode.full),
    );
  }

  static Future<void> disposeDogDetector() async {
    await _dogDetectorIsolate?.dispose();
    _dogDetectorIsolate = null;
  }

  /// Validates PNG bytes by decoding and checking dimensions.
  /// Returns (width, height) if valid, null if corrupt/invalid.
  /// This guards against truncated cache files causing OpenCV resize failures.
  static Future<List<Map<String, dynamic>>> getUnstabilizedPhotos(
    int projectId,
  ) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    return await DB.instance.getUnstabilizedPhotos(
      projectId,
      projectOrientation,
    );
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

      final faceLike = FaceLike(boundingBox: bbox, leftEye: l, rightEye: r);

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
        final facesDetected = await _faceDetector!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.full,
        );

        if (facesDetected.isEmpty) {
          return (<FaceLike>[], <fdl.Face>[]);
        }

        return _convertFaces(facesDetected, filterByFaceSize: filterByFaceSize);
      } catch (e) {
        LogService.instance.log(
          "Error caught while fetching faces from bytes: $e",
        );
        // Force reinit of face detector on next call - handles stale native state
        // after hot restart or other isolate lifecycle issues
        _faceDetector = null;
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
        final facesDetected = await _faceDetector!.detectFaces(
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

          faces.add(FaceLike(boundingBox: bbox, leftEye: l, rightEye: r));
        }

        if (!filterByFaceSize || faces.isEmpty) return faces;

        const double minFaceSize = 0.1;
        final filtered = faces
            .where((f) => (f.boundingBox.width / w) > minFaceSize)
            .toList();
        return filtered.isNotEmpty ? filtered : faces;
      } catch (e) {
        LogService.instance.log("Error caught while fetching faces: $e");
        _faceDetector = null; // Force reinit on next call
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

        final faces = await _faceDetector!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.fast,
        );

        if (faces.isEmpty) return null;

        final embedding = await _faceDetector!.getFaceEmbedding(
          faces.first,
          bytes,
        );

        return embedding;
      } catch (e) {
        LogService.instance.log("Error extracting face embedding: $e");
        _faceDetector = null; // Force reinit on next call
        return null;
      }
    });
  }

  /// Gets face embeddings for all detected faces in the image.
  /// Returns a list of embeddings (may contain nulls for faces where extraction failed).
  static Future<List<Float32List?>> getFaceEmbeddingsFromBytes(
    Uint8List bytes,
  ) async {
    // Serialize access to the face detector to prevent race conditions
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();

        final faces = await _faceDetector!.detectFaces(
          bytes,
          mode: fdl.FaceDetectionMode.fast,
        );

        if (faces.isEmpty) return [];

        final embeddings = await _faceDetector!.getFaceEmbeddings(
          faces,
          bytes,
        );

        return embeddings;
      } catch (e) {
        LogService.instance.log("Error extracting face embeddings: $e");
        _faceDetector = null; // Force reinit on next call
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
            "Using ${faces.length} pre-detected faces for embedding matching",
          );
        } else {
          faces = await _faceDetector!.detectFaces(
            imageBytes,
            mode: fdl.FaceDetectionMode.fast,
          );
        }

        if (faces.isEmpty) return -1;
        if (faces.length == 1) return 0;

        int bestIndex = 0;
        double bestSimilarity = -1.0;

        for (int i = 0; i < faces.length; i++) {
          final embedding = await _faceDetector!.getFaceEmbedding(
            faces[i],
            imageBytes,
          );

          final similarity = fdl.FaceDetector.compareFaces(
            referenceEmbedding,
            embedding,
          );

          LogService.instance.log(
            "Face $i embedding similarity: ${similarity.toStringAsFixed(3)}",
          );

          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestIndex = i;
          }
        }

        LogService.instance.log(
          "Selected face $bestIndex with similarity ${bestSimilarity.toStringAsFixed(3)}",
        );

        return bestIndex;
      } catch (e) {
        LogService.instance.log("Error in embedding-based face selection: $e");
        _faceDetector = null; // Force reinit on next call
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

  // ============================================================
  // Cat/Dog Face Detection → FaceLike conversion
  // ============================================================

  /// Averages a list of nullable (x, y) coordinate pairs into a single point.
  /// Null entries are skipped. Returns null if no valid coordinates remain.
  static Point<double>? _computeEyeCenterFromCoords(
    List<(double, double)?> coords,
  ) {
    final valid = coords.whereType<(double, double)>().toList();
    if (valid.isEmpty) return null;
    final x = valid.map((c) => c.$1).reduce((a, b) => a + b) / valid.length;
    final y = valid.map((c) => c.$2).reduce((a, b) => a + b) / valid.length;
    return Point<double>(x, y);
  }

  /// Computes an eye center from 4 typed landmarks [outer, top, inner, bottom].
  /// [getLandmark] converts a landmark type to an optional (x, y) coordinate.
  static Point<double>? _computeEyeCenterFromLandmarks<T>(
    List<T> landmarks,
    (double, double)? Function(T) getLandmark,
  ) {
    return _computeEyeCenterFromCoords(landmarks.map(getLandmark).toList());
  }

  static Point<double>? _computeCatEyeCenter(
    cat.CatFace face, {
    required bool left,
  }) {
    return _computeEyeCenterFromLandmarks(
      [
        left
            ? cat.CatLandmarkType.leftEyeOuter
            : cat.CatLandmarkType.rightEyeOuter,
        left ? cat.CatLandmarkType.leftEyeTop : cat.CatLandmarkType.rightEyeTop,
        left
            ? cat.CatLandmarkType.leftEyeInner
            : cat.CatLandmarkType.rightEyeInner,
        left
            ? cat.CatLandmarkType.leftEyeBottom
            : cat.CatLandmarkType.rightEyeBottom,
      ],
      (t) {
        final p = face.getLandmark(t);
        return p != null ? (p.x, p.y) : null;
      },
    );
  }

  static Point<double>? _computeDogEyeCenter(
    dog.DogFace face, {
    required bool left,
  }) {
    return _computeEyeCenterFromLandmarks(
      [
        left
            ? dog.DogLandmarkType.leftEyeOuter
            : dog.DogLandmarkType.rightEyeOuter,
        left ? dog.DogLandmarkType.leftEyeTop : dog.DogLandmarkType.rightEyeTop,
        left
            ? dog.DogLandmarkType.leftEyeInner
            : dog.DogLandmarkType.rightEyeInner,
        left
            ? dog.DogLandmarkType.leftEyeBottom
            : dog.DogLandmarkType.rightEyeBottom,
      ],
      (t) {
        final p = face.getLandmark(t);
        return p != null ? (p.x, p.y) : null;
      },
    );
  }

  /// Shared detection loop: converts a list of animal detections into FaceLike
  /// wrappers. [getImageWidth], [getBoundingBox], and [getEyes] are callbacks
  /// that extract the type-specific fields from each detection result.
  static List<FaceLike> _convertAnimalFaces<T>(
    List<T> detections,
    double Function(T) getImageWidth,
    dynamic Function(T) getBoundingBox,
    (Point<double>?, Point<double>?) Function(T) getEyes, {
    bool filterByFaceSize = true,
    int? imageWidth,
    required List<FaceLike> Function(
      List<T>, {
      bool filterByFaceSize,
      int? imageWidth,
    }) retry,
  }) {
    final double w = imageWidth?.toDouble() ?? getImageWidth(detections.first);
    final List<FaceLike> faces = [];

    for (final d in detections) {
      final bb = getBoundingBox(d);
      final bbox = Rect.fromLTRB(bb.left, bb.top, bb.right, bb.bottom);

      if (filterByFaceSize && (bbox.width / w) <= 0.1) continue;

      final (leftEye, rightEye) = getEyes(d);
      faces.add(
        FaceLike(boundingBox: bbox, leftEye: leftEye, rightEye: rightEye),
      );
    }

    if (faces.isEmpty && detections.isNotEmpty) {
      return retry(detections, filterByFaceSize: false, imageWidth: imageWidth);
    }

    return faces;
  }

  /// Runs an animal detection job inside [mutex], calling [ensure] before
  /// [detect], and [convert] on the result. Resets [onError] on failure.
  static Future<List<FaceLike>?> _getAnimalFacesFromBytes<T>(
    Uint8List bytes,
    AsyncMutex mutex,
    Future<void> Function() ensure,
    Future<List<T>> Function(Uint8List) detect,
    List<FaceLike> Function(List<T>, {bool filterByFaceSize, int? imageWidth})
        convert,
    void Function() onError,
    String errorLabel, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    return mutex.protect(() async {
      try {
        await ensure();
        final results = await detect(bytes);
        if (results.isEmpty) return <FaceLike>[];
        return convert(
          results,
          filterByFaceSize: filterByFaceSize,
          imageWidth: imageWidth,
        );
      } catch (e) {
        LogService.instance.log("Error detecting $errorLabel faces: $e");
        onError();
        return <FaceLike>[];
      }
    });
  }

  /// Detects cats in image bytes and returns FaceLike wrappers with eye centers.
  static Future<List<FaceLike>?> getCatFacesFromBytes(
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) =>
      _getAnimalFacesFromBytes(
        bytes,
        _catDetectorMutex,
        _ensureCatDetector,
        (b) => _catDetectorIsolate!.detectCats(b),
        _convertCatFaces,
        () => _catDetectorIsolate = null,
        'cat',
        filterByFaceSize: filterByFaceSize,
        imageWidth: imageWidth,
      );

  static List<FaceLike> _convertCatFaces(
    List<cat.Cat> cats, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) {
    return _convertAnimalFaces<cat.Cat>(
      cats,
      (c) => c.imageWidth.toDouble(),
      (c) => c.boundingBox,
      (c) {
        if (c.face == null || !c.face!.hasLandmarks) return (null, null);
        return (
          _computeCatEyeCenter(c.face!, left: true),
          _computeCatEyeCenter(c.face!, left: false),
        );
      },
      filterByFaceSize: filterByFaceSize,
      imageWidth: imageWidth,
      retry: _convertCatFaces,
    );
  }

  /// Detects dogs in image bytes and returns FaceLike wrappers with eye centers.
  static Future<List<FaceLike>?> getDogFacesFromBytes(
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) =>
      _getAnimalFacesFromBytes(
        bytes,
        _dogDetectorMutex,
        _ensureDogDetector,
        (b) => _dogDetectorIsolate!.detectDogs(b),
        _convertDogFaces,
        () => _dogDetectorIsolate = null,
        'dog',
        filterByFaceSize: filterByFaceSize,
        imageWidth: imageWidth,
      );

  static List<FaceLike> _convertDogFaces(
    List<dog.Dog> dogs, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) {
    return _convertAnimalFaces<dog.Dog>(
      dogs,
      (d) => d.imageWidth.toDouble(),
      (d) => d.boundingBox,
      (d) {
        if (d.face == null || !d.face!.hasLandmarks) return (null, null);
        return (
          _computeDogEyeCenter(d.face!, left: true),
          _computeDogEyeCenter(d.face!, left: false),
        );
      },
      filterByFaceSize: filterByFaceSize,
      imageWidth: imageWidth,
      retry: _convertDogFaces,
    );
  }

  /// Dispatches face detection to the correct detector based on project type.
  /// Returns FaceLike wrappers for any project type.
  static Future<List<FaceLike>?> getFacesFromBytesForProjectType(
    String projectType,
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    switch (projectType) {
      case 'cat':
        return getCatFacesFromBytes(
          bytes,
          filterByFaceSize: filterByFaceSize,
          imageWidth: imageWidth,
        );
      case 'dog':
        return getDogFacesFromBytes(
          bytes,
          filterByFaceSize: filterByFaceSize,
          imageWidth: imageWidth,
        );
      default:
        return getFacesFromBytes(
          bytes,
          filterByFaceSize: filterByFaceSize,
          imageWidth: imageWidth,
        );
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

  static Future<void> performFileOperationInBackground(
    Map<String, dynamic> params,
  ) async {
    SendPort sendPort = params['sendPort'];
    String? filePath = params['filePath'];
    var operation = params['operation'];
    var bytes = params['bytes'];

    switch (operation) {
      case 'writePngFromBytes':
        // Write bytes atomically: temp file + rename to prevent partial writes
        if (bytes == null) {
          sendPort.send('Bytes are null');
          break;
        }
        // Use unique temp name to prevent collision with concurrent writers
        final tempPath =
            '$filePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
        final tempFile = File(tempPath);
        try {
          await tempFile.writeAsBytes(bytes as Uint8List, flush: true);
          // Delete target first for Windows compatibility (rename fails if exists)
          final targetFile = File(filePath!);
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(filePath);
          sendPort.send('File written successfully');
        } catch (e) {
          // Clean up temp file on any failure
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
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
            final (success, jpgBytes) = cv.imencode(
              '.jpg',
              mat,
              params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]),
            );
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
            final bgType =
                mat.type.depth == 2 ? cv.MatType.CV_16UC3 : cv.MatType.CV_8UC3;
            final bg = cv.Mat.zeros(mat.rows, mat.cols, bgType);
            final channels = cv.split(mat);
            final bgr = cv.merge(
              cv.VecMat.fromList([channels[0], channels[1], channels[2]]),
            );
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

          final (success, pngBytes) = cv.imencode(
            '.png',
            result,
            params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]),
          );
          result.dispose();
          sendPort.send(
            success ? pngBytes : 'Error compositeBlackPng: encode failed',
          );
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
              cv.VecMat.fromList([channels[0], channels[1], channels[2]]),
            );
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

          // Ensure 8-bit for JPEG thumbnail output
          if (composited.type.depth != 0) {
            final composited8 = composited.convertTo(
              cv.MatType.CV_8UC(composited.channels),
              alpha: 1.0 / 256.0,
            );
            composited.dispose();
            composited = composited8;
          }

          // Resize to 800px width with high-quality interpolation
          final aspectRatio = composited.rows / composited.cols;
          final height = (800 * aspectRatio).round();
          final thumb = cv.resize(
              composited,
              (
                800,
                height,
              ),
              interpolation: cv.INTER_CUBIC);
          composited.dispose();

          final (success, jpgBytes) = cv.imencode(
            '.jpg',
            thumb,
            params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]),
          );
          thumb.dispose();
          sendPort.send(
            success ? jpgBytes : 'Error thumbnailFromPng: encode failed',
          );
        } catch (e) {
          sendPort.send('Error thumbnailFromPng: $e');
        }
        break;
      case 'thumbnailFromPngKeepAlpha':
        // Create thumbnail from PNG, preserving alpha channel
        try {
          final input = bytes as Uint8List;
          final mat = cv.imdecode(input, cv.IMREAD_UNCHANGED);
          if (mat.isEmpty) {
            mat.dispose();
            sendPort.send('Error thumbnailFromPngKeepAlpha: empty mat');
            return;
          }

          // Resize to 800px width with high-quality interpolation
          final aspectRatio = mat.rows / mat.cols;
          final height = (800 * aspectRatio).round();
          final thumb = cv.resize(
              mat,
              (
                800,
                height,
              ),
              interpolation: cv.INTER_CUBIC);
          mat.dispose();

          final (success, pngBytes) = cv.imencode(
            '.png',
            thumb,
            params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]),
          );
          thumb.dispose();
          sendPort.send(
            success
                ? pngBytes
                : 'Error thumbnailFromPngKeepAlpha: encode failed',
          );
        } catch (e) {
          sendPort.send('Error thumbnailFromPngKeepAlpha: $e');
        }
        break;
    }
  }

  /// Write PNG bytes to file
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<void> writePngBytesToFileInIsolate(
    String filepath,
    Uint8List pngBytes, {
    CancellationToken? token,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      await IsolatePool.instance.execute('writePngFromBytes', {
        'filePath': filepath,
        'bytes': pngBytes,
      });
      return;
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filepath,
      'bytes': pngBytes,
      'operation': 'writePngFromBytes',
    };

    final isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params,
    );
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
  static Future<Uint8List> compositeBlackPngBytes(
    Uint8List pngBytes, {
    CancellationToken? token,
  }) async {
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
      'operation': 'compositeBlackPng',
    };

    final isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params,
    );
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
  static Future<Uint8List> thumbnailJpgFromPngBytes(
    Uint8List pngBytes, {
    CancellationToken? token,
  }) async {
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
      'operation': 'thumbnailFromPng',
    };

    final isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params,
    );
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

  /// Create thumbnail PNG from PNG bytes, preserving alpha channel.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  static Future<Uint8List> thumbnailPngFromPngBytes(
    Uint8List pngBytes, {
    CancellationToken? token,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      final result = await IsolatePool.instance.execute<Uint8List>(
        'thumbnailFromPngKeepAlpha',
        {'bytes': pngBytes},
      );
      return result ?? pngBytes; // Fallback to original if thumbnail fails
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'bytes': pngBytes,
      'operation': 'thumbnailFromPngKeepAlpha',
    };

    final isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params,
    );
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
    String filePath,
    List<int> bytes, {
    CancellationToken? token,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      await IsolatePool.instance.execute('writeJpg', {
        'filePath': filePath,
        'bytes': Uint8List.fromList(bytes),
      });
      return;
    }

    // Fallback to individual isolate if pool not initialized
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
      'bytes': bytes,
      'operation': 'writeJpg',
    };

    final isolate = await Isolate.spawn(
      performFileOperationInBackground,
      params,
    );
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
    Uint8List bytes,
    String imagePath,
  ) async {
    await DirUtils.createDirectoryIfNotExists(imagePath);
    await writeBytesToJpgFileInIsolate(imagePath, bytes);
    return true;
  }

  static Future<File> flipImageHorizontally(
    String imagePath, {
    Uint8List? preDecodedBytes,
  }) async {
    return await processImageInIsolate(
      imagePath,
      'flip_horizontal',
      '_flipped.png',
      preDecodedBytes: preDecodedBytes,
    );
  }

  // Rotate Image 90 Degrees Clockwise
  static Future<File> rotateImageClockwise(
    String imagePath, {
    Uint8List? preDecodedBytes,
  }) async {
    return await processImageInIsolate(
      imagePath,
      'rotate_clockwise',
      '_rotated_clockwise.png',
      preDecodedBytes: preDecodedBytes,
    );
  }

  // Rotate Image 90 Degrees Counter-Clockwise
  static Future<File> rotateImageCounterClockwise(
    String imagePath, {
    Uint8List? preDecodedBytes,
  }) async {
    return await processImageInIsolate(
      imagePath,
      'rotate_counter_clockwise',
      '_rotated_counter_clockwise.png',
      preDecodedBytes: preDecodedBytes,
    );
  }

  static Future<void> performImageProcessingInBackground(
    Map<String, dynamic> params,
  ) async {
    final rootIsolateToken = params['rootIsolateToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

    SendPort sendPort = params['sendPort'];
    String filePath = params['filePath'];
    String suffix = params['suffix'];
    String operation = params['operation'];

    try {
      final Uint8List? preDecodedBytes =
          params['preDecodedBytes'] as Uint8List?;
      final Uint8List imageBytes =
          preDecodedBytes ?? await File(filePath).readAsBytes();
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
      // macOS sandboxed apps can have their Caches subdirectory pruned by the OS;
      // writeAsBytes throws PathNotFoundException if the directory no longer exists.
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final String name = path.basenameWithoutExtension(filePath);

      final String newName = '$name$suffix';
      final String newPath = path.join(tempDir.path, newName);
      final File processedImageFile = File(newPath);

      final (success, pngBytes) = cv.imencode(
        '.png',
        processedMat,
        params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]),
      );
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
    String imagePath,
    String operation,
    String suffix, {
    CancellationToken? token,
    Uint8List? preDecodedBytes,
  }) async {
    token?.throwIfCancelled();

    ReceivePort receivePort = ReceivePort();
    final rootIsolateToken = RootIsolateToken.instance;
    var params = {
      'sendPort': receivePort.sendPort,
      'filePath': imagePath,
      'operation': operation,
      'suffix': suffix,
      'rootIsolateToken': rootIsolateToken,
      if (preDecodedBytes != null) 'preDecodedBytes': preDecodedBytes,
    };

    final isolate = await Isolate.spawn(
      performImageProcessingInBackground,
      params,
    );
    IsolateManager.instance.register(isolate, receivePort: receivePort);

    try {
      final result = await receivePort.first.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(
          'processImageInIsolate timed out after 60 seconds',
        ),
      );
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

  static Future<String> getStabilizedImagePath(
    String originalFilePath,
    int projectId,
    String? projectOrientation,
  ) async {
    final stabilizedDirectoryPath = await DirUtils.getStabilizedDirPath(
      projectId,
    );
    final String originalBasename = path.basenameWithoutExtension(
      originalFilePath,
    );
    return path.join(
      stabilizedDirectoryPath,
      projectOrientation,
      '$originalBasename.jpg',
    );
  }

  static Future<ui.Image?> loadImageFromFile(File file) async {
    const int maxWaitSec = 10;
    final Stopwatch sw = Stopwatch()..start();

    while (!(await file.exists())) {
      if (sw.elapsed.inSeconds >= maxWaitSec) {
        LogService.instance.log(
          "Error loading image: file not found within $maxWaitSec seconds",
        );
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
          LogService.instance.log(
            "Error loading image: not decodable within $maxWaitSec seconds",
          );
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
  static Future<(int, int)?> getImageDimensionsFromBytesAsync(
    Uint8List bytes, {
    CancellationToken? token,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      return await IsolatePool.instance.execute<(int, int)>(
        'getImageDimensions',
        {'bytes': bytes},
      );
    }

    // Fallback to individual isolate if pool not initialized
    final ReceivePort receivePort = ReceivePort();
    final params = {'sendPort': receivePort.sendPort, 'bytes': bytes};

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
  ///
  /// [backgroundColorBGR] is an optional list of [B, G, R] values for the
  /// background fill color. Null means transparent background (BGRA output).
  /// Defaults to black if not provided and not transparent.
  static Uint8List? generateStabilizedImageBytesCV(
    cv.Mat srcMat,
    double rotationDegrees,
    double scaleFactor,
    double translateX,
    double translateY,
    int canvasWidth,
    int canvasHeight, {
    List<int>? backgroundColorBGR,
    bool isTransparent = false,
  }) {
    // For transparent backgrounds, convert to BGRA (4 channels)
    cv.Mat srcMatForWarp;
    bool needsDispose = false;
    if (isTransparent) {
      srcMatForWarp = cv.cvtColor(srcMat, cv.COLOR_BGR2BGRA);
      needsDispose = true;
    } else {
      srcMatForWarp = srcMat;
    }

    final int iw = srcMatForWarp.cols;
    final int ih = srcMatForWarp.rows;

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

    // Create border color scalar
    // For transparent: BGRA with alpha=0
    // For solid color: BGR with alpha=255
    final cv.Scalar borderValue;
    if (isTransparent) {
      borderValue = cv.Scalar(0.0, 0.0, 0.0, 0.0); // Fully transparent
    } else if (backgroundColorBGR != null) {
      borderValue = cv.Scalar(
        backgroundColorBGR[0].toDouble(), // B
        backgroundColorBGR[1].toDouble(), // G
        backgroundColorBGR[2].toDouble(), // R
        255.0, // A
      );
    } else {
      borderValue = cv.Scalar.black;
    }

    // Apply affine transformation with cubic interpolation for smooth edges
    final cv.Mat dst = cv.warpAffine(
      srcMatForWarp,
      rotMat,
      (canvasWidth, canvasHeight),
      flags: cv.INTER_CUBIC,
      borderMode: cv.BORDER_CONSTANT,
      borderValue: borderValue,
    );

    // Encode to PNG (preserves alpha channel if present)
    final (bool success, Uint8List bytes) = cv.imencode(
      '.png',
      dst,
      params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]),
    );

    // Cleanup
    rotMat.dispose();
    dst.dispose();
    if (needsDispose) {
      srcMatForWarp.dispose();
    }

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
    final List<int>? backgroundColorBGR =
        params['backgroundColorBGR'] as List<int>?;
    final bool preserveBitDepth = params['preserveBitDepth'] as bool? ?? false;
    // null backgroundColorBGR means transparent background
    final bool isTransparent = backgroundColorBGR == null;

    try {
      final decodeFlag = preserveBitDepth
          ? (cv.IMREAD_ANYDEPTH | cv.IMREAD_COLOR)
          : cv.IMREAD_COLOR;
      final cv.Mat srcMat = cv.imdecode(srcBytes, decodeFlag);
      if (srcMat.isEmpty) {
        srcMat.dispose();
        sendPort.send(null);
        return;
      }

      // For transparent backgrounds, convert to BGRA (4 channels)
      cv.Mat srcMatForWarp;
      bool needsDisposeSrcForWarp = false;
      if (isTransparent) {
        srcMatForWarp = cv.cvtColor(srcMat, cv.COLOR_BGR2BGRA);
        needsDisposeSrcForWarp = true;
      } else {
        srcMatForWarp = srcMat;
      }

      final int iw = srcMatForWarp.cols;
      final int ih = srcMatForWarp.rows;

      final cv.Mat rotMat = cv.getRotationMatrix2D(
        cv.Point2f(iw / 2.0, ih / 2.0),
        -rotationDegrees,
        scaleFactor,
      );

      final double offsetX = (canvasWidth - iw) / 2.0 + translateX;
      final double offsetY = (canvasHeight - ih) / 2.0 + translateY;
      rotMat.set<double>(0, 2, rotMat.at<double>(0, 2) + offsetX);
      rotMat.set<double>(1, 2, rotMat.at<double>(1, 2) + offsetY);

      // Create border color scalar
      final cv.Scalar borderValue;
      if (isTransparent) {
        borderValue = cv.Scalar(0.0, 0.0, 0.0, 0.0); // Fully transparent
      } else {
        // backgroundColorBGR is non-null when not transparent (promoted by isTransparent check)
        borderValue = cv.Scalar(
          backgroundColorBGR[0].toDouble(),
          backgroundColorBGR[1].toDouble(),
          backgroundColorBGR[2].toDouble(),
          255.0,
        );
      }

      final cv.Mat dst = cv.warpAffine(
        srcMatForWarp,
        rotMat,
        (canvasWidth, canvasHeight),
        flags: cv.INTER_CUBIC,
        borderMode: cv.BORDER_CONSTANT,
        borderValue: borderValue,
      );

      final (bool success, Uint8List bytes) = cv.imencode(
        '.png',
        dst,
        params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 3]),
      );

      rotMat.dispose();
      dst.dispose();
      if (needsDisposeSrcForWarp) {
        srcMatForWarp.dispose();
      }
      srcMat.dispose();

      sendPort.send(success ? bytes : null);
    } catch (e) {
      sendPort.send(null);
    }
  }

  /// Detect faces from raw Mat bytes (avoids PNG encode/decode overhead).
  ///
  /// Uses [FaceDetector.detectFacesFromMatBytes] which transfers the raw
  /// pixels via zero-copy [TransferableTypedData] and reconstructs the Mat
  /// inside the face-detection background isolate — nothing blocks the UI.
  static Future<List<FaceLike>?> getFacesFromRawMatBytes(
    Uint8List data,
    int width,
    int height,
    int matType, {
    bool filterByFaceSize = true,
  }) async {
    return await _faceDetectorMutex.protect(() async {
      try {
        await _ensureFDLite();
        final facesDetected = await _faceDetector!.detectFacesFromMatBytes(
          data,
          width: width,
          height: height,
          matType: matType,
          mode: fdl.FaceDetectionMode.full,
        );
        if (facesDetected.isEmpty) {
          return <FaceLike>[];
        }
        return _convertFaces(
          facesDetected,
          filterByFaceSize: filterByFaceSize,
        ).$1;
      } catch (e) {
        LogService.instance.log(
          "Error caught while fetching faces from raw mat bytes: $e",
        );
        _faceDetector = null;
        return null;
      }
    });
  }

  /// Async version that runs CV stabilization in an isolate to avoid blocking UI.
  /// Uses persistent isolate pool to avoid spawn/kill overhead.
  ///
  /// When [srcId] is provided, the decoded source Mat is cached in the worker.
  /// Call [IsolatePool.instance.clearMatCache()] after finishing each photo.
  ///
  /// [backgroundColorBGR] is an optional list of [B, G, R] values for the
  /// background fill color. Defaults to black if not provided.
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
    List<int>? backgroundColorBGR,
    bool preserveBitDepth = false,
    bool useCachedSrc = false,
    int pngCompression = 3,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      final params = <String, dynamic>{
        'rotationDegrees': rotationDegrees,
        'scaleFactor': scaleFactor,
        'translateX': translateX,
        'translateY': translateY,
        'canvasWidth': canvasWidth,
        'canvasHeight': canvasHeight,
        'srcId': srcId,
        'backgroundColorBGR': backgroundColorBGR,
        'preserveBitDepth': preserveBitDepth,
        'pngCompression': pngCompression,
      };
      // When useCachedSrc is true and sticky routing guarantees the same
      // worker, skip sending the large srcBytes across the isolate boundary.
      // The worker will use its cached Mat instead.
      if (!useCachedSrc) {
        params['srcBytes'] = srcBytes;
      }
      // Use sticky routing when srcId is available so all passes for the same
      // source image hit the same worker, maximizing Mat cache hits.
      if (srcId != null) {
        return await IsolatePool.instance
            .executeSticky<Uint8List>(srcId, 'stabilizeCV', params);
      }
      return await IsolatePool.instance.execute<Uint8List>(
        'stabilizeCV',
        params,
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
      'backgroundColorBGR': backgroundColorBGR,
      'preserveBitDepth': preserveBitDepth,
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

  /// Like [generateStabilizedImageBytesCVAsync] but returns raw Mat bytes
  /// instead of encoding to PNG. Passes 2-4 use this to skip the PNG
  /// encode/decode cycle for intermediate face detection.
  ///
  /// Returns a Map with keys: 'data' (Uint8List), 'width', 'height', 'matType'.
  /// Returns null on failure.
  static Future<Map<String, dynamic>?> generateStabilizedRawCVAsync(
    Uint8List srcBytes,
    double rotationDegrees,
    double scaleFactor,
    double translateX,
    double translateY,
    int canvasWidth,
    int canvasHeight, {
    CancellationToken? token,
    String? srcId,
    List<int>? backgroundColorBGR,
    bool preserveBitDepth = false,
    bool useCachedSrc = false,
  }) async {
    token?.throwIfCancelled();

    if (IsolatePool.instance.isInitialized) {
      final params = <String, dynamic>{
        'rotationDegrees': rotationDegrees,
        'scaleFactor': scaleFactor,
        'translateX': translateX,
        'translateY': translateY,
        'canvasWidth': canvasWidth,
        'canvasHeight': canvasHeight,
        'srcId': srcId,
        'backgroundColorBGR': backgroundColorBGR,
        'preserveBitDepth': preserveBitDepth,
      };
      if (!useCachedSrc) {
        params['srcBytes'] = srcBytes;
      }
      final Map<String, dynamic>? result;
      if (srcId != null) {
        result = await IsolatePool.instance.executeSticky<Map<String, dynamic>>(
            srcId, 'stabilizeCVRaw', params);
      } else {
        result = await IsolatePool.instance.execute<Map<String, dynamic>>(
          'stabilizeCVRaw',
          params,
        );
      }
      // Materialize zero-copy TransferableTypedData into a plain Uint8List
      // so downstream code sees a normal Map<String, dynamic>.
      if (result != null && result['data'] is TransferableTypedData) {
        result['data'] = (result['data'] as TransferableTypedData)
            .materialize()
            .asUint8List();
      }
      return result;
    }

    // Pool not initialized — not supported for raw path; return null
    return null;
  }

  /// Encodes raw Mat bytes to PNG. Used to persist the best pass result
  /// after skipping PNG encoding in intermediate passes.
  static Future<Uint8List?> encodeRawToPngAsync(
    Uint8List data,
    int width,
    int height,
    int matType, {
    int pngCompression = 3,
  }) async {
    if (IsolatePool.instance.isInitialized) {
      return await IsolatePool.instance.execute<Uint8List>(
        'encodeRawToPng',
        {
          'data': data,
          'width': width,
          'height': height,
          'matType': matType,
          'pngCompression': pngCompression,
        },
      );
    }
    return null;
  }
}
