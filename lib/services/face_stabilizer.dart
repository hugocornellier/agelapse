import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'cancellation_token.dart';
import 'isolate_manager.dart';
import 'isolate_pool.dart';
import 'log_service.dart';
import 'stabilization_settings.dart';
import 'thumbnail_service.dart';
import '../models/stabilization_mode.dart';
import 'package:pose_detection/pose_detection.dart' as pose;
import 'package:path/path.dart' as path;
import '../utils/camera_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/format_decode_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/video_utils.dart';
import 'database_helper.dart';

class StabilizationResult {
  final bool success;
  final bool cancelled; // True if operation was cancelled
  final double? preScore; // Score before two-pass (first pass)
  final double? twoPassScore; // Score after two-pass (null if not attempted)
  final double?
      threePassScore; // Score after three-pass (null if not attempted)
  final double? fourPassScore; // Score after four-pass (null if not attempted)

  // Final benchmark metrics
  final double? finalScore; // Final stabilization score
  final double?
      finalEyeDeltaY; // Final vertical difference between eyes (rotation error)
  final double? finalEyeDistance; // Final distance between eyes
  final double? goalEyeDistance; // Target eye distance

  StabilizationResult({
    required this.success,
    this.cancelled = false,
    this.preScore,
    this.twoPassScore,
    this.threePassScore,
    this.fourPassScore,
    this.finalScore,
    this.finalEyeDeltaY,
    this.finalEyeDistance,
    this.goalEyeDistance,
  });

  /// Creates a cancelled result.
  factory StabilizationResult.cancelled() =>
      StabilizationResult(success: false, cancelled: true);
}

class FaceStabilizer {
  final int projectId;
  String? projectOrientation;
  late int canvasHeight;
  late int canvasWidth;
  late double leftEyeXGoal;
  late double rightEyeXGoal;
  late double bothEyesYGoal;
  late double eyeDistanceGoal;
  late double bodyDistanceGoal;
  List<Point<double>?>? originalEyePositions;
  late String aspectRatio;
  late double? aspectRatioDecimal;
  late String resolution;
  late String projectType;
  late double originalRightAnkleX;
  late double originalRightAnkleY;
  late double originalRightHipX;
  late double originalRightHipY;
  late int pregRightAnkleYGoal;
  late int pregRightAnkleXGoal;
  late int muscRightHipYGoal;
  late int muscRightHipXGoal;
  pose.PoseDetector? _poseDetector;
  late double eyeOffsetX;
  late double eyeOffsetY;
  late StabilizationMode stabilizationMode;
  late List<int>? backgroundColorBGR;
  late bool lossless;

  /// Whether this project type uses eye-based stabilization (face, cat, dog).
  bool get _isEyeBasedProject =>
      projectType == "face" || projectType == "cat" || projectType == "dog";

  // Face embedding tracking for identity-based face matching
  int? _currentFaceCount;
  Float32List? _currentEmbedding;

  final VoidCallback userRanOutOfSpaceCallbackIn;
  final StabilizationSettings? _preloadedSettings;

  FaceStabilizer(
    this.projectId,
    this.userRanOutOfSpaceCallbackIn, {
    StabilizationSettings? settings,
  }) : _preloadedSettings = settings;

  bool _disposed = false;

  /// Releases native resources held by the pose detector.
  /// Must be called when the stabilizer is no longer needed.
  /// Safe to call multiple times (idempotent).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _poseDetector?.dispose();
    _poseDetector = null;
  }

  Future<void>? _initFuture;
  bool _ready = false;

  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    await initializeProjectSettings();
    _ready = true;
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    await init();
  }

  Future<void> initializeProjectSettings() async {
    // Use preloaded settings if available, otherwise load from DB
    final settings =
        _preloadedSettings ?? await StabilizationSettings.load(projectId);

    projectType = settings.projectType;
    projectOrientation = settings.projectOrientation;
    resolution = settings.resolution;
    aspectRatio = settings.aspectRatio;
    aspectRatioDecimal = settings.aspectRatioDecimal;
    stabilizationMode = StabilizationMode.fromString(
      settings.stabilizationMode,
    );
    eyeOffsetX = settings.eyeOffsetX;
    eyeOffsetY = settings.eyeOffsetY;
    backgroundColorBGR = settings.backgroundColorBGR;
    lossless = settings.lossless;

    if (!_isEyeBasedProject) {
      final poseDetector = pose.PoseDetector(
        mode: pose.PoseMode.boxesAndLandmarks,
        landmarkModel: pose.PoseLandmarkModel.heavy,
        // pose_detection >= 2.0.3 defaults to Metal on iOS, which shifts results.
        performanceConfig: Platform.isIOS
            ? pose.PerformanceConfig.disabled
            : const pose.PerformanceConfig(),
      );
      await poseDetector.initialize();
      _poseDetector = poseDetector;
    }

    final dims = StabUtils.getOutputDimensions(
      resolution,
      aspectRatio,
      projectOrientation!,
    );
    canvasWidth = dims!.$1;
    canvasHeight = dims.$2;

    _initializeGoalsAndOffsets();
  }

  void _initializeGoalsAndOffsets() {
    final double xAxisCenter = canvasWidth / 2;
    leftEyeXGoal = (xAxisCenter - eyeOffsetX * canvasWidth);
    rightEyeXGoal = (xAxisCenter + eyeOffsetX * canvasWidth);
    eyeDistanceGoal = rightEyeXGoal - leftEyeXGoal;
    bothEyesYGoal = (canvasHeight * eyeOffsetY);
    bodyDistanceGoal = canvasHeight * 0.7;
    pregRightAnkleXGoal = xAxisCenter.toInt();
    pregRightAnkleYGoal = (canvasHeight * 0.85).toInt();
    muscRightHipXGoal = (xAxisCenter - eyeOffsetX * canvasWidth).toInt();
    muscRightHipYGoal = (canvasHeight * 0.8).toInt();
  }

  Future<StabilizationResult> stabilize(
    String rawPhotoPath,
    CancellationToken? token,
    void Function() userRanOutOfSpaceCallback, {
    Rect? targetBoundingBox,
  }) async {
    try {
      token?.throwIfCancelled();
      await _ensureReady();

      if (_isEyeBasedProject) {
        return await _stabilizeWithOrientationRetry(
          rawPhotoPath,
          token,
          userRanOutOfSpaceCallback,
          targetBoundingBox: targetBoundingBox,
        );
      } else {
        return await _stabilizeSingleAttempt(
          rawPhotoPath,
          rawPhotoPath,
          token,
          userRanOutOfSpaceCallback,
          targetBoundingBox: targetBoundingBox,
        );
      }
    } on CancelledException {
      LogService.instance.log("Stabilization cancelled");
      return StabilizationResult.cancelled();
    } catch (e) {
      LogService.instance.log("Caught error: $e");
      return StabilizationResult(success: false);
    } finally {
      await IsolatePool.instance.clearMatCache();
      _lastCvBytes = null;
      _lastRawFaces = null;
    }
  }

  /// Tries to stabilize an eye-based project by attempting multiple orientations:
  /// original, flipped, counter-clockwise rotation, clockwise rotation.
  /// Returns the first successful result, or StabilizationResult(success: false) if all fail.
  /// Transforms [originalPath] using [transformFn], runs a stabilization attempt,
  /// and registers the temp file in [tempFiles] for cleanup.
  /// Returns the result if success or cancelled; returns null to continue retrying.
  Future<StabilizationResult?> _tryTransformedAttempt(
    String originalPath,
    CancellationToken? token,
    void Function() userRanOutOfSpaceCallback,
    Uint8List? preDecodedBytes,
    List<String> tempFiles,
    Future<File> Function(String, {Uint8List? preDecodedBytes}) transformFn,
  ) async {
    token?.throwIfCancelled();
    final File transformed = await transformFn(
      originalPath,
      preDecodedBytes: preDecodedBytes,
    );
    tempFiles.add(transformed.path);
    final result = await _stabilizeSingleAttempt(
      transformed.path,
      originalPath,
      token,
      userRanOutOfSpaceCallback,
      targetBoundingBox: null,
    );
    if (result.success || result.cancelled) return result;
    return null;
  }

  Future<StabilizationResult> _stabilizeWithOrientationRetry(
    String originalPath,
    CancellationToken? token,
    void Function() userRanOutOfSpaceCallback, {
    Rect? targetBoundingBox,
  }) async {
    // Pre-decode on main thread so the isolate receives cv-compatible bytes
    // (avoids crash for TIFF/JP2 on Apple where cv.imdecode segfaults).
    final Uint8List? preDecodedBytes =
        FormatDecodeUtils.needsConversion(path.extension(originalPath))
            ? await FormatDecodeUtils.loadCvCompatibleBytes(originalPath)
            : null;

    final tempFiles = <String>[];
    try {
      // Attempt 1: original image — pass targetBoundingBox (it references original coords)
      token?.throwIfCancelled();
      final result1 = await _stabilizeSingleAttempt(
        originalPath,
        originalPath,
        token,
        userRanOutOfSpaceCallback,
        targetBoundingBox: targetBoundingBox,
      );
      if (result1.success) return result1;
      if (result1.cancelled) return result1;

      // Attempts 2–4: transformed variants (bounding box not meaningful after transform)
      for (final transformFn in [
        StabUtils.flipImageHorizontally,
        StabUtils.rotateImageCounterClockwise,
        StabUtils.rotateImageClockwise,
      ]) {
        final r = await _tryTransformedAttempt(
          originalPath,
          token,
          userRanOutOfSpaceCallback,
          preDecodedBytes,
          tempFiles,
          transformFn,
        );
        if (r != null) return r;
      }

      // All orientations failed
      await DB.instance.setPhotoNoFacesFound(
        path.basenameWithoutExtension(originalPath),
        projectId,
      );
      unawaited(
        _emitThumbnailFailure(originalPath, ThumbnailStatus.noFacesFound),
      );
      return StabilizationResult(success: false);
    } finally {
      for (final p in tempFiles) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
  }

  /// Processes a single image attempt. [inputPath] is the image to process
  /// (may be flipped/rotated). [originalPath] is the canonical source path
  /// used for output naming and DB lookups.
  Future<StabilizationResult> _stabilizeSingleAttempt(
    String inputPath,
    String originalPath,
    CancellationToken? token,
    void Function() userRanOutOfSpaceCallback, {
    Rect? targetBoundingBox,
  }) async {
    final String srcId = path.basenameWithoutExtension(originalPath);

    double? rotationDegrees, scaleFactor, translateX, translateY;

    token?.throwIfCancelled();
    final Uint8List? srcBytes =
        await FormatDecodeUtils.loadCvCompatibleBytes(inputPath);
    if (srcBytes == null) return StabilizationResult(success: false);

    token?.throwIfCancelled();
    final dims = await StabUtils.getImageDimensionsFromBytesAsync(
      srcBytes,
      token: token,
    );
    if (dims == null) return StabilizationResult(success: false);
    final (int imgWidth, int imgHeight) = dims;

    token?.throwIfCancelled();
    (scaleFactor, rotationDegrees) = await _calculateRotationAndScale(
      originalPath,
      imgWidth,
      imgHeight,
      targetBoundingBox,
      userRanOutOfSpaceCallback,
      cvBytes: srcBytes,
    );
    if (rotationDegrees == null || scaleFactor == null) {
      return StabilizationResult(success: false);
    }

    (translateX, translateY) = _calculateTranslateData(
      scaleFactor,
      rotationDegrees,
      imgWidth,
      imgHeight,
    );
    if (translateX == null || translateY == null) {
      return StabilizationResult(success: false);
    }

    if (projectType == "musc") translateY = 0;

    token?.throwIfCancelled();
    Uint8List? imageBytesStabilized =
        await StabUtils.generateStabilizedImageBytesCVAsync(
      srcBytes,
      rotationDegrees,
      scaleFactor,
      translateX,
      translateY,
      canvasWidth,
      canvasHeight,
      token: token,
      srcId: srcId,
      backgroundColorBGR: backgroundColorBGR,
      preserveBitDepth: lossless,
    );
    if (imageBytesStabilized == null) {
      return StabilizationResult(success: false);
    }

    final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
      originalPath,
      projectId,
      projectOrientation,
    );

    token?.throwIfCancelled();
    final (
      bool result,
      double? preScore,
      double? twoPassScore,
      double? threePassScore,
      double? fourPassScore,
      double? finalScore,
      double? finalEyeDeltaY,
      double? finalEyeDistance,
    ) = await _finalizeStabilization(
      originalPath,
      stabilizedPhotoPath,
      imgWidth,
      imgHeight,
      translateX,
      translateY,
      rotationDegrees,
      scaleFactor,
      imageBytesStabilized,
      srcBytes,
      token,
      srcId,
    );

    LogService.instance.log("Result => '$result'");

    if (result) {
      unawaited(
        createStabThumbnail(path.setExtension(stabilizedPhotoPath, '.png')),
      );
    }

    return StabilizationResult(
      success: result,
      preScore: preScore,
      twoPassScore: twoPassScore,
      threePassScore: threePassScore,
      fourPassScore: fourPassScore,
      finalScore: finalScore,
      finalEyeDeltaY: finalEyeDeltaY,
      finalEyeDistance: finalEyeDistance,
      goalEyeDistance: eyeDistanceGoal,
    );
  }

  Future<(bool, double?, double?, double?, double?, double?, double?, double?)>
      _handleFallbackStabilization({
    required String rawPhotoPath,
    required String stabilizedJpgPhotoPath,
    required Uint8List imageBytesStabilized,
    required int imgWidth,
    required int imgHeight,
    required double scaleFactor,
    required double rotationDegrees,
    required double translateX,
    required double translateY,
    required Point<double> goalLeftEye,
    required Point<double> goalRightEye,
    required bool markNoFacesFound,
  }) async {
    if (markNoFacesFound) {
      await DB.instance.setPhotoNoFacesFound(
        path.basenameWithoutExtension(rawPhotoPath),
        projectId,
      );
      unawaited(
        _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound),
      );
    }
    final eyesXY = _estimatedEyesAfterTransform(
      imgWidth,
      imgHeight,
      scaleFactor,
      rotationDegrees,
      translateX: translateX,
      translateY: translateY,
    );
    final score = calculateStabScore(eyesXY, goalLeftEye, goalRightEye);
    final success = await saveStabilizedImage(
      imageBytesStabilized,
      rawPhotoPath,
      stabilizedJpgPhotoPath,
      score,
      translateX: translateX,
      translateY: translateY,
      rotationDegrees: rotationDegrees,
      scaleFactor: scaleFactor,
    );
    return (success, score, null, null, null, score, null, null);
  }

  /// Returns (success, preScore, twoPassScore, threePassScore, fourPassScore, finalScore, finalEyeDeltaY, finalEyeDistance)
  Future<(bool, double?, double?, double?, double?, double?, double?, double?)>
      _finalizeStabilization(
    String rawPhotoPath,
    String stabilizedJpgPhotoPath,
    int imgWidth,
    int imgHeight,
    double translateX,
    double translateY,
    double rotationDegrees,
    double scaleFactor,
    Uint8List imageBytesStabilized,
    Uint8List srcBytes,
    CancellationToken? token,
    String srcId,
  ) async {
    if (!_isEyeBasedProject) {
      await StabUtils.writeImagesBytesToJpgFile(
        imageBytesStabilized,
        stabilizedJpgPhotoPath,
      );
      final success = await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        0.0,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
      return (
        success,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      ); // No scores for non-eye-based projects
    }

    final Point<double> goalLeftEye = Point(leftEyeXGoal, bothEyesYGoal);
    final Point<double> goalRightEye = Point(rightEyeXGoal, bothEyesYGoal);

    // Detect faces directly from bytes using face_detection_tflite (works on all platforms)
    final stabFaces = await _detectFaces(
      imageBytesStabilized,
      filterByFaceSize: false,
      imageWidth: canvasWidth,
    );

    if (stabFaces == null || stabFaces.isEmpty) {
      return _handleFallbackStabilization(
        rawPhotoPath: rawPhotoPath,
        stabilizedJpgPhotoPath: stabilizedJpgPhotoPath,
        imageBytesStabilized: imageBytesStabilized,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
        scaleFactor: scaleFactor,
        rotationDegrees: rotationDegrees,
        translateX: translateX,
        translateY: translateY,
        goalLeftEye: goalLeftEye,
        goalRightEye: goalRightEye,
        markNoFacesFound: stabFaces != null && stabFaces.isEmpty,
      );
    }

    List<Point<double>?> eyes = await _filterAndCenterEyesAsync(stabFaces);

    if (!_areEyesValid(eyes)) {
      return _handleFallbackStabilization(
        rawPhotoPath: rawPhotoPath,
        stabilizedJpgPhotoPath: stabilizedJpgPhotoPath,
        imageBytesStabilized: imageBytesStabilized,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
        scaleFactor: scaleFactor,
        rotationDegrees: rotationDegrees,
        translateX: translateX,
        translateY: translateY,
        goalLeftEye: goalLeftEye,
        goalRightEye: goalRightEye,
        markNoFacesFound: true,
      );
    }

    LogService.instance.log(
      "Goal: L$goalLeftEye R$goalRightEye | Init: L${eyes[0]} R${eyes[1]}",
    );

    List<String> toDelete = [
      stabilizedJpgPhotoPath,
    ];

    final (
      bool successfulStabilization,
      double? preScore,
      double? twoPassScore,
      double? threePassScore,
      double? fourPassScore,
      double? finalScore,
      double? finalEyeDeltaY,
      double? finalEyeDistance,
    ) = await _performMultiPassFix(
      stabFaces,
      eyes,
      goalLeftEye,
      goalRightEye,
      translateX,
      translateY,
      rotationDegrees,
      scaleFactor,
      imageBytesStabilized,
      rawPhotoPath,
      stabilizedJpgPhotoPath,
      toDelete,
      imgWidth,
      imgHeight,
      srcBytes,
      token,
      srcId,
    );

    await DirUtils.tryDeleteFiles(toDelete);
    return (
      successfulStabilization,
      preScore,
      twoPassScore,
      threePassScore,
      fourPassScore,
      finalScore,
      finalEyeDeltaY,
      finalEyeDistance,
    );
  }

  List<Point<double>> _estimatedEyesAfterTransform(
    int imgWidth,
    int imgHeight,
    double scale,
    double rotationDegrees, {
    double translateX = 0,
    double translateY = 0,
  }) {
    final Point<double> left0 = originalEyePositions![0]!;
    final Point<double> right0 = originalEyePositions![1]!;

    final a = transformPointByCanvasSize(
      originalPointX: left0.x.toDouble(),
      originalPointY: left0.y.toDouble(),
      scale: scale,
      rotationDegrees: rotationDegrees,
      canvasWidth: canvasWidth.toDouble(),
      canvasHeight: canvasHeight.toDouble(),
      originalWidth: imgWidth.toDouble(),
      originalHeight: imgHeight.toDouble(),
    );
    final b = transformPointByCanvasSize(
      originalPointX: right0.x.toDouble(),
      originalPointY: right0.y.toDouble(),
      scale: scale,
      rotationDegrees: rotationDegrees,
      canvasWidth: canvasWidth.toDouble(),
      canvasHeight: canvasHeight.toDouble(),
      originalWidth: imgWidth.toDouble(),
      originalHeight: imgHeight.toDouble(),
    );

    final ax = (a['x']! + translateX);
    final ay = (a['y']! + translateY);
    final bx = (b['x']! + translateX);
    final by = (b['y']! + translateY);

    return [Point(ax, ay), Point(bx, by)];
  }

  /// Returns (success, preScore, twoPassScore, threePassScore, fourPassScore, finalScore, finalEyeDeltaY, finalEyeDistance)
  /// Scores are null if that pass was not attempted
  ///
  /// FAST MODE: Translation-only multi-pass (up to 4 passes)
  /// SLOW MODE: Full affine refinement (rotation, scale, translation passes)
  Future<(bool, double?, double?, double?, double?, double?, double?, double?)>
      _performMultiPassFix(
    List<dynamic> stabFaces,
    List<Point<double>?> eyes,
    Point<double> goalLeftEye,
    Point<double> goalRightEye,
    double translateX,
    double translateY,
    double rotationDegrees,
    double scaleFactor,
    Uint8List imageBytesStabilized,
    String rawPhotoPath,
    String stabilizedJpgPhotoPath,
    List<String> toDelete,
    int imgWidth,
    int imgHeight,
    Uint8List srcBytes,
    CancellationToken? token,
    String srcId,
  ) async {
    if (stabilizationMode == StabilizationMode.fast) {
      return _performFastMultiPass(
        stabFaces,
        eyes,
        goalLeftEye,
        goalRightEye,
        translateX,
        translateY,
        rotationDegrees,
        scaleFactor,
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        toDelete,
        imgWidth,
        imgHeight,
        srcBytes,
        token,
        srcId,
      );
    } else {
      return _performSlowMultiPass(
        stabFaces,
        eyes,
        goalLeftEye,
        goalRightEye,
        translateX,
        translateY,
        rotationDegrees,
        scaleFactor,
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        toDelete,
        imgWidth,
        imgHeight,
        srcBytes,
        token,
        srcId,
      );
    }
  }

  /// FAST MODE: Translation-only multi-pass correction (up to 4 passes).
  Future<(bool, double?, double?, double?, double?, double?, double?, double?)>
      _performFastMultiPass(
    List<dynamic> stabFaces,
    List<Point<double>?> eyes,
    Point<double> goalLeftEye,
    Point<double> goalRightEye,
    double translateX,
    double translateY,
    double rotationDegrees,
    double scaleFactor,
    Uint8List imageBytesStabilized,
    String rawPhotoPath,
    String stabilizedJpgPhotoPath,
    List<String> toDelete,
    int imgWidth,
    int imgHeight,
    Uint8List srcBytes,
    CancellationToken? token,
    String srcId,
  ) async {
    bool successfulStabilization = false;

    final double firstPassScore = calculateStabScore(
      eyes,
      goalLeftEye,
      goalRightEye,
    );
    final (
      double overshotLeftX,
      double overshotLeftY,
      double overshotRightX,
      double overshotRightY,
    ) = _calculateOvershots(
      eyes,
      goalLeftEye,
      goalRightEye,
    );

    if (!correctionIsNeeded(
      firstPassScore,
      overshotLeftX,
      overshotRightX,
      overshotLeftY,
      overshotRightY,
    )) {
      // No correction needed - save with first pass result
      successfulStabilization = await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        firstPassScore,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
      return (
        successfulStabilization,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        null,
        null,
      );
    }

    final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
      rawPhotoPath,
      projectId,
      projectOrientation,
    );

    // Track best result across all passes
    Uint8List bestBytes = imageBytesStabilized;
    double bestScore = firstPassScore;
    double bestTX = translateX;
    double bestTY = translateY;

    // Track which buffer is currently best (for memory recycling)
    // 0 = imageBytesStabilized, 1 = twoPass, 2 = threePass, 3 = fourPass
    int bestPassIndex = 0;

    // Track scores and state for each pass
    double? twoPassScore, threePassScore, fourPassScore;
    bool usedTwoPass = false, usedThreePass = false, usedFourPass = false;
    List<Point<double>?>? currentEyes = eyes;
    double currentTX = translateX;
    double currentTY = translateY;

    // === TWO-PASS ===
    token?.throwIfCancelled();
    LogService.instance.log(
      "Attempting two-pass correction. First-pass score = $firstPassScore...",
    );

    var (double ovLX, double ovLY, double ovRX, double ovRY) =
        _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);
    final (double twoPassTX, double twoPassTY) = _calculateNewTranslations(
      currentTX,
      currentTY,
      ovLX,
      ovRX,
      ovLY,
      ovRY,
    );

    Uint8List? twoPassBytes =
        await StabUtils.generateStabilizedImageBytesCVAsync(
      srcBytes,
      rotationDegrees,
      scaleFactor,
      twoPassTX,
      twoPassTY,
      canvasWidth,
      canvasHeight,
      token: token,
      srcId: srcId,
      backgroundColorBGR: backgroundColorBGR,
      preserveBitDepth: lossless,
    );
    if (twoPassBytes == null) {
      return (
        false,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        null,
        null,
      );
    }

    final twoPassFaces = await _detectFaces(
      twoPassBytes,
      filterByFaceSize: false,
      imageWidth: canvasWidth,
    );
    if (twoPassFaces == null) {
      return (
        false,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        null,
        null,
      );
    }

    List<Point<double>?> twoPassEyes = await _filterAndCenterEyesAsync(
      twoPassFaces,
    );

    if (_areEyesValid(twoPassEyes)) {
      twoPassScore = calculateStabScore(twoPassEyes, goalLeftEye, goalRightEye);
      if (twoPassScore < bestScore) {
        usedTwoPass = true;
        bestBytes = twoPassBytes;
        bestScore = twoPassScore;
        bestTX = twoPassTX;
        bestTY = twoPassTY;
        currentEyes = twoPassEyes;
        currentTX = twoPassTX;
        currentTY = twoPassTY;
        bestPassIndex = 1;
      } else {
        // Two-pass not better, release its memory
        twoPassBytes = null;
      }
    } else {
      // Couldn't detect eyes, release memory
      twoPassBytes = null;
    }

    // === THREE-PASS (only if two-pass improved) ===
    if (usedTwoPass && _areEyesValid(currentEyes)) {
      token?.throwIfCancelled();
      (ovLX, ovLY, ovRX, ovRY) = _calculateOvershots(
        currentEyes,
        goalLeftEye,
        goalRightEye,
      );

      if (correctionIsNeeded(bestScore, ovLX, ovRX, ovLY, ovRY)) {
        LogService.instance.log(
          "Attempting three-pass correction. Two-pass score = $twoPassScore...",
        );

        final (
          double threePassTX,
          double threePassTY,
        ) = _calculateNewTranslations(
          currentTX,
          currentTY,
          ovLX,
          ovRX,
          ovLY,
          ovRY,
        );

        Uint8List? threePassBytes =
            await StabUtils.generateStabilizedImageBytesCVAsync(
          srcBytes,
          rotationDegrees,
          scaleFactor,
          threePassTX,
          threePassTY,
          canvasWidth,
          canvasHeight,
          token: token,
          srcId: srcId,
          backgroundColorBGR: backgroundColorBGR,
          preserveBitDepth: lossless,
        );

        if (threePassBytes != null) {
          final threePassEyes = await _detectAndFilterEyes(threePassBytes);

          if (threePassEyes != null) {
            threePassScore = calculateStabScore(
              threePassEyes,
              goalLeftEye,
              goalRightEye,
            );
            if (threePassScore < bestScore) {
              usedThreePass = true;
              // Release previous best if it was twoPass
              if (bestPassIndex == 1) twoPassBytes = null;
              bestBytes = threePassBytes;
              bestScore = threePassScore;
              bestTX = threePassTX;
              bestTY = threePassTY;
              currentEyes = threePassEyes;
              currentTX = threePassTX;
              currentTY = threePassTY;
              bestPassIndex = 2;
            } else {
              // Three-pass not better, release its memory
              threePassBytes = null;
            }
          } else {
            threePassBytes = null;
          }
        }
      }
    }

    // === FOUR-PASS (only if three-pass improved) ===
    if (usedThreePass && _areEyesValid(currentEyes)) {
      token?.throwIfCancelled();
      (ovLX, ovLY, ovRX, ovRY) = _calculateOvershots(
        currentEyes,
        goalLeftEye,
        goalRightEye,
      );

      if (correctionIsNeeded(bestScore, ovLX, ovRX, ovLY, ovRY)) {
        LogService.instance.log(
          "Attempting four-pass correction. Three-pass score = $threePassScore...",
        );

        final (
          double fourPassTX,
          double fourPassTY,
        ) = _calculateNewTranslations(
          currentTX,
          currentTY,
          ovLX,
          ovRX,
          ovLY,
          ovRY,
        );

        Uint8List? fourPassBytes =
            await StabUtils.generateStabilizedImageBytesCVAsync(
          srcBytes,
          rotationDegrees,
          scaleFactor,
          fourPassTX,
          fourPassTY,
          canvasWidth,
          canvasHeight,
          token: token,
          srcId: srcId,
          backgroundColorBGR: backgroundColorBGR,
          preserveBitDepth: lossless,
        );

        if (fourPassBytes != null) {
          final fourPassEyes = await _detectAndFilterEyes(fourPassBytes);

          if (fourPassEyes != null) {
            fourPassScore = calculateStabScore(
              fourPassEyes,
              goalLeftEye,
              goalRightEye,
            );
            if (fourPassScore < bestScore) {
              usedFourPass = true;
              bestBytes = fourPassBytes;
              bestScore = fourPassScore;
              bestTX = fourPassTX;
              bestTY = fourPassTY;
              bestPassIndex = 3;
            } else {
              // Four-pass not better, release its memory
              fourPassBytes = null;
            }
          } else {
            fourPassBytes = null;
          }
        }
      }
    }

    // Save the best result
    if (bestScore < 20) {
      successfulStabilization = await saveStabilizedImage(
        bestBytes,
        rawPhotoPath,
        stabilizedPhotoPath,
        bestScore,
        translateX: bestTX,
        translateY: bestTY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
    } else {
      LogService.instance.log("STAB FAILURE. STAB SCORE: $bestScore");
      await StabUtils.writeImagesBytesToJpgFile(bestBytes, stabilizedPhotoPath);
      await _handleStabilizationFailure(
        rawPhotoPath,
        stabilizedPhotoPath,
        toDelete,
      );
      successfulStabilization = false;
    }

    return (
      successfulStabilization,
      firstPassScore,
      usedTwoPass ? twoPassScore : null,
      usedThreePass ? threePassScore : null,
      usedFourPass ? fourPassScore : null,
      bestScore,
      null, // No finalEyeDeltaY in fast mode
      null, // No finalEyeDistance in fast mode
    );
  }

  /// SLOW MODE: Full affine refinement with rotation, scale, and translation passes.
  ///
  /// Sequential refinement approach:
  /// 1. Rotation Pass: Fix eye angle (make eyes horizontal)
  /// 2. Scale Pass: Fix eye distance
  /// 3. Translation Passes: Fix eye position
  Future<(bool, double?, double?, double?, double?, double?, double?, double?)>
      _performSlowMultiPass(
    List<dynamic> stabFaces,
    List<Point<double>?> eyes,
    Point<double> goalLeftEye,
    Point<double> goalRightEye,
    double translateX,
    double translateY,
    double rotationDegrees,
    double scaleFactor,
    Uint8List imageBytesStabilized,
    String rawPhotoPath,
    String stabilizedJpgPhotoPath,
    List<String> toDelete,
    int imgWidth,
    int imgHeight,
    Uint8List srcBytes,
    CancellationToken? token,
    String srcId,
  ) async {
    bool successfulStabilization = false;

    final double firstPassScore = calculateStabScore(
      eyes,
      goalLeftEye,
      goalRightEye,
    );

    // Log initial eye positions for debugging
    final double initialEyeDeltaY = eyes[1]!.y - eyes[0]!.y;
    final double initialEyeDistance = _eyeDistance(eyes);
    LogService.instance.log(
      "Init: score=${firstPassScore.toStringAsFixed(2)}, tilt=${initialEyeDeltaY.toStringAsFixed(1)}px, dist=${initialEyeDistance.toStringAsFixed(1)}→$eyeDistanceGoal",
    );

    final (
      double overshotLeftX,
      double overshotLeftY,
      double overshotRightX,
      double overshotRightY,
    ) = _calculateOvershots(
      eyes,
      goalLeftEye,
      goalRightEye,
    );

    if (!correctionIsNeeded(
      firstPassScore,
      overshotLeftX,
      overshotRightX,
      overshotLeftY,
      overshotRightY,
    )) {
      // No correction needed - save with first pass result
      successfulStabilization = await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        firstPassScore,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
      return (
        successfulStabilization,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        initialEyeDeltaY,
        initialEyeDistance,
      );
    }

    final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
      rawPhotoPath,
      projectId,
      projectOrientation,
    );

    // Track best result across all passes
    Uint8List bestBytes = imageBytesStabilized;
    double bestScore = firstPassScore;
    double bestTX = translateX;
    double bestTY = translateY;
    double bestRotation = rotationDegrees;
    double bestScale = scaleFactor;

    // Track previous pass bytes for memory recycling
    Uint8List? previousPassBytes;

    // Track scores for each pass type
    double? rotationPassScore, scalePassScore, translationPassScore;
    List<Point<double>?>? currentEyes = eyes;

    // === ROTATION REFINEMENT PASSES ===
    const int maxRotationPasses = 3;
    double eyeDeltaY = currentEyes[1]!.y - currentEyes[0]!.y;
    final double rotStartEyeDeltaY = eyeDeltaY;
    int rotPassCount = 0;

    for (int rotPass = 1; rotPass <= maxRotationPasses; rotPass++) {
      token?.throwIfCancelled();

      if (!_areEyesValid(currentEyes)) break;

      double eyeDeltaX = currentEyes![1]!.x - currentEyes[0]!.x;
      double detectedAngleDeg = atan2(eyeDeltaY, eyeDeltaX) * 180 / pi;

      if (detectedAngleDeg.abs() <= 0.1) break;

      double newRotation = bestRotation - detectedAngleDeg;
      final (double? rotTX, double? rotTY) = _calculateTranslateData(
        bestScale,
        newRotation,
        imgWidth,
        imgHeight,
      );

      if (rotTX == null || rotTY == null) break;

      Uint8List? rotPassBytes =
          await StabUtils.generateStabilizedImageBytesCVAsync(
        srcBytes,
        newRotation,
        bestScale,
        rotTX,
        rotTY,
        canvasWidth,
        canvasHeight,
        token: token,
        srcId: srcId,
        backgroundColorBGR: backgroundColorBGR,
        preserveBitDepth: lossless,
      );

      if (rotPassBytes == null) break;

      final rotPassEyes = await _detectAndFilterEyes(rotPassBytes);

      if (rotPassEyes == null) {
        rotPassBytes = null;
        break;
      }

      double newEyeDeltaY = rotPassEyes[1]!.y - rotPassEyes[0]!.y;
      rotationPassScore = calculateStabScore(
        rotPassEyes,
        goalLeftEye,
        goalRightEye,
      );

      if (newEyeDeltaY.abs() < eyeDeltaY.abs()) {
        rotPassCount++;
        // Release previous best bytes (unless it's the original input)
        previousPassBytes = _updatePreviousPassBytes(
            previousPassBytes, bestBytes, imageBytesStabilized);
        bestBytes = rotPassBytes;
        bestScore = rotationPassScore;
        bestTX = rotTX;
        bestTY = rotTY;
        bestRotation = newRotation;
        currentEyes = rotPassEyes;
        eyeDeltaY = newEyeDeltaY;
      } else {
        // This pass didn't improve, release its memory
        rotPassBytes = null;
        break;
      }
    }

    if (rotPassCount > 0) {
      LogService.instance.log(
        "Rot: |${rotStartEyeDeltaY.toStringAsFixed(1)}|→|${eyeDeltaY.toStringAsFixed(1)}|px ($rotPassCount pass${rotPassCount > 1 ? 'es' : ''})",
      );
    }

    // === SCALE REFINEMENT PASSES ===
    const int maxScalePasses = 3;
    double currentEyeDistance = _areEyesValid(currentEyes)
        ? _eyeDistance(currentEyes!)
        : eyeDistanceGoal;
    double scaleError = (currentEyeDistance - eyeDistanceGoal).abs();
    final double initialScaleError = scaleError;
    int scalePassCount = 0;

    for (int scalePass = 1; scalePass <= maxScalePasses; scalePass++) {
      token?.throwIfCancelled();

      if (!_areEyesValid(currentEyes)) break;

      if (scaleError <= 1.0) break;
      if (currentEyeDistance < 1.0) break;

      double scaleCorrection = eyeDistanceGoal / currentEyeDistance;
      double newScale = bestScale * scaleCorrection;

      final (double? scaleTX, double? scaleTY) = _calculateTranslateData(
        newScale,
        bestRotation,
        imgWidth,
        imgHeight,
      );

      if (scaleTX == null || scaleTY == null) break;

      Uint8List? scalePassBytes =
          await StabUtils.generateStabilizedImageBytesCVAsync(
        srcBytes,
        bestRotation,
        newScale,
        scaleTX,
        scaleTY,
        canvasWidth,
        canvasHeight,
        token: token,
        srcId: srcId,
        backgroundColorBGR: backgroundColorBGR,
        preserveBitDepth: lossless,
      );

      if (scalePassBytes == null) break;

      final scalePassEyes = await _detectAndFilterEyes(scalePassBytes);

      if (scalePassEyes == null) {
        scalePassBytes = null;
        break;
      }

      double newEyeDistance = _eyeDistance(scalePassEyes);
      double newScaleError = (newEyeDistance - eyeDistanceGoal).abs();
      scalePassScore = calculateStabScore(
        scalePassEyes,
        goalLeftEye,
        goalRightEye,
      );

      if (newScaleError < scaleError) {
        scalePassCount++;
        // Release previous best bytes (unless it's the original input)
        previousPassBytes = _updatePreviousPassBytes(
            previousPassBytes, bestBytes, imageBytesStabilized);
        bestBytes = scalePassBytes;
        bestScore = scalePassScore;
        bestTX = scaleTX;
        bestTY = scaleTY;
        bestScale = newScale;
        currentEyes = scalePassEyes;
        currentEyeDistance = newEyeDistance;
        scaleError = newScaleError;
      } else {
        // This pass didn't improve, release its memory
        scalePassBytes = null;
        break;
      }
    }

    if (scalePassCount > 0) {
      LogService.instance.log(
        "Scale: ${initialScaleError.toStringAsFixed(1)}→${scaleError.toStringAsFixed(1)}px ($scalePassCount pass${scalePassCount > 1 ? 'es' : ''})",
      );
    }

    // === TRANSLATION REFINEMENT PASSES ===
    token?.throwIfCancelled();

    if (!_areEyesValid(currentEyes)) {
      // Can't do translation passes without valid eyes, save current best and return
      bool success = await saveStabilizedImage(
        bestBytes,
        rawPhotoPath,
        stabilizedPhotoPath,
        bestScore,
        translateX: bestTX,
        translateY: bestTY,
        rotationDegrees: bestRotation,
        scaleFactor: bestScale,
      );
      return (
        success,
        firstPassScore,
        rotationPassScore,
        scalePassScore,
        null,
        bestScore,
        null,
        null,
      );
    }

    var (double ovLX, double ovLY, double ovRX, double ovRY) =
        _calculateOvershots(currentEyes!, goalLeftEye, goalRightEye);

    double currentTX = bestTX;
    double currentTY = bestTY;

    const int maxTranslationPasses = 3;
    const double convergenceThreshold = 0.05;
    final double initialTransScore = bestScore;
    int transPassCount = 0;

    for (int passNum = 1; passNum <= maxTranslationPasses; passNum++) {
      token?.throwIfCancelled();

      if (!correctionIsNeeded(bestScore, ovLX, ovRX, ovLY, ovRY)) break;

      final (double transTX, double transTY) = _calculateNewTranslations(
        currentTX,
        currentTY,
        ovLX,
        ovRX,
        ovLY,
        ovRY,
      );

      Uint8List? transPassBytes =
          await StabUtils.generateStabilizedImageBytesCVAsync(
        srcBytes,
        bestRotation,
        bestScale,
        transTX,
        transTY,
        canvasWidth,
        canvasHeight,
        token: token,
        srcId: srcId,
        backgroundColorBGR: backgroundColorBGR,
        preserveBitDepth: lossless,
      );

      if (transPassBytes == null) break;

      final transPassEyes = await _detectAndFilterEyes(transPassBytes);

      if (transPassEyes == null) {
        transPassBytes = null;
        break;
      }

      double passScore = calculateStabScore(
        transPassEyes,
        goalLeftEye,
        goalRightEye,
      );

      double improvement = bestScore - passScore;

      if (passScore < bestScore) {
        transPassCount++;
        // Release previous best bytes (unless it's the original input)
        previousPassBytes = _updatePreviousPassBytes(
            previousPassBytes, bestBytes, imageBytesStabilized);
        bestBytes = transPassBytes;
        bestScore = passScore;
        bestTX = transTX;
        bestTY = transTY;
        currentEyes = transPassEyes;
        currentTX = transTX;
        currentTY = transTY;
        translationPassScore = passScore;

        // Update overshots for next pass
        (ovLX, ovLY, ovRX, ovRY) = _calculateOvershots(
          currentEyes,
          goalLeftEye,
          goalRightEye,
        );

        // Check convergence
        if (improvement > 0 && improvement < convergenceThreshold) break;
      } else {
        // This pass didn't improve, release its memory
        transPassBytes = null;
        currentTX = transTX;
        currentTY = transTY;
        (ovLX, ovLY, ovRX, ovRY) = _calculateOvershots(
          transPassEyes,
          goalLeftEye,
          goalRightEye,
        );
      }
    }

    if (transPassCount > 0) {
      LogService.instance.log(
        "Trans: ${initialTransScore.toStringAsFixed(2)}→${bestScore.toStringAsFixed(2)} ($transPassCount pass${transPassCount > 1 ? 'es' : ''})",
      );
    }

    // === FINAL CLEANUP PASS ===
    token?.throwIfCancelled();

    final Point<double>? cleanupLeftEye =
        (currentEyes != null && currentEyes.isNotEmpty) ? currentEyes[0] : null;
    final Point<double>? cleanupRightEye =
        (currentEyes != null && currentEyes.length > 1) ? currentEyes[1] : null;

    double cleanupEyeDeltaY = 0;
    double cleanupEyeDistance = eyeDistanceGoal;
    double cleanupScaleError = 0;
    double cleanupRotationAngle = 0;
    bool needsCleanup = false;

    if (cleanupLeftEye != null && cleanupRightEye != null) {
      cleanupEyeDeltaY = cleanupRightEye.y - cleanupLeftEye.y;
      cleanupEyeDistance = sqrt(
        pow(cleanupRightEye.x - cleanupLeftEye.x, 2) +
            pow(cleanupRightEye.y - cleanupLeftEye.y, 2),
      );
      cleanupScaleError = (cleanupEyeDistance - eyeDistanceGoal).abs();
      cleanupRotationAngle =
          atan2(cleanupEyeDeltaY, cleanupRightEye.x - cleanupLeftEye.x) *
              180 /
              pi;
      needsCleanup = cleanupEyeDeltaY.abs() > 1.5 || cleanupScaleError > 2.0;
    }

    if (needsCleanup && bestScore > 0.5) {
      double cleanupRotation = bestRotation;
      double cleanupScale = bestScale;

      if (cleanupEyeDeltaY.abs() > 1.5) {
        cleanupRotation = bestRotation - cleanupRotationAngle;
      }

      if (cleanupScaleError > 2.0 && cleanupEyeDistance >= 1.0) {
        double scaleCorrection = eyeDistanceGoal / cleanupEyeDistance;
        cleanupScale = bestScale * scaleCorrection;
      }

      // Apply cleanup transform
      final (double? cleanupTX, double? cleanupTY) = _calculateTranslateData(
        cleanupScale,
        cleanupRotation,
        imgWidth,
        imgHeight,
      );

      if (cleanupTX != null && cleanupTY != null) {
        Uint8List? cleanupBytes =
            await StabUtils.generateStabilizedImageBytesCVAsync(
          srcBytes,
          cleanupRotation,
          cleanupScale,
          cleanupTX,
          cleanupTY,
          canvasWidth,
          canvasHeight,
          token: token,
          srcId: srcId,
          backgroundColorBGR: backgroundColorBGR,
          preserveBitDepth: lossless,
        );

        if (cleanupBytes != null) {
          final cleanupEyes = await _detectAndFilterEyes(cleanupBytes);

          if (cleanupEyes != null) {
            double cleanupScore = calculateStabScore(
              cleanupEyes,
              goalLeftEye,
              goalRightEye,
            );

            if (cleanupScore < bestScore) {
              LogService.instance.log(
                "Cleanup: ${bestScore.toStringAsFixed(2)}→${cleanupScore.toStringAsFixed(2)}",
              );
              // Release previous best bytes (unless it's the original input)
              if (previousPassBytes != null) {
                previousPassBytes = null;
              }
              if (bestBytes != imageBytesStabilized) {
                previousPassBytes = bestBytes;
              }
              bestBytes = cleanupBytes;
              bestScore = cleanupScore;
              bestTX = cleanupTX;
              bestTY = cleanupTY;
              bestRotation = cleanupRotation;
              bestScale = cleanupScale;
              currentEyes = cleanupEyes;
              // Release previous pass bytes now that we've switched
              previousPassBytes = null;
            } else {
              // Cleanup didn't improve, release its memory
              cleanupBytes = null;
            }
          } else {
            cleanupBytes = null;
          }
        }
      }
    }

    double? finalEyeDeltaY;
    double? finalEyeDistance;
    if (_areEyesValid(currentEyes)) {
      finalEyeDeltaY = currentEyes![1]!.y - currentEyes[0]!.y;
      finalEyeDistance = _eyeDistance(currentEyes);
      LogService.instance.log(
        "Final: score=${bestScore.toStringAsFixed(2)}, tilt=${finalEyeDeltaY.toStringAsFixed(1)}px, dist=${finalEyeDistance.toStringAsFixed(1)}px",
      );
    }

    // Save the best result
    if (bestScore < 20) {
      successfulStabilization = await saveStabilizedImage(
        bestBytes,
        rawPhotoPath,
        stabilizedPhotoPath,
        bestScore,
        translateX: bestTX,
        translateY: bestTY,
        rotationDegrees: bestRotation,
        scaleFactor: bestScale,
      );
    } else {
      LogService.instance.log("STAB FAILURE. STAB SCORE: $bestScore");
      await StabUtils.writeImagesBytesToJpgFile(bestBytes, stabilizedPhotoPath);
      await _handleStabilizationFailure(
        rawPhotoPath,
        stabilizedPhotoPath,
        toDelete,
      );
      successfulStabilization = false;
    }

    return (
      successfulStabilization,
      firstPassScore,
      rotationPassScore,
      scalePassScore,
      translationPassScore,
      bestScore,
      finalEyeDeltaY,
      finalEyeDistance,
    );
  }

  Future<bool> saveStabilizedImage(
    Uint8List imageBytes,
    String rawPhotoPath,
    String stabilizedPhotoPath,
    double score, {
    double? translateX,
    double? translateY,
    double? rotationDegrees,
    double? scaleFactor,
  }) async {
    // For transparent backgrounds, preserve the alpha channel directly.
    // For opaque backgrounds, composite onto black background.
    final bool isTransparent = backgroundColorBGR == null;
    final Uint8List pngBytes = isTransparent
        ? imageBytes
        : await StabUtils.compositeBlackPngBytes(imageBytes);

    final String result = await saveBytesToPngFileInIsolate(
      pngBytes,
      path.setExtension(stabilizedPhotoPath, '.png'),
    );

    if (result != "success") {
      if (result == "NoSpaceLeftError") {
        LogService.instance.log("User is out of space...");
        userRanOutOfSpaceCallbackIn();
      }
      return false;
    }

    final tx = translateX ?? 0;
    final ty = translateY ?? 0;
    final rot = rotationDegrees ?? 0;
    final sc = scaleFactor ?? 1;

    if (tx.isInfinite || ty.isInfinite || rot.isInfinite || sc.isInfinite) {
      LogService.instance.log('ABORT save: infinite transform values detected');
      return false;
    }

    await setPhotoStabilized(
      rawPhotoPath,
      translateX: tx,
      translateY: ty,
      rotationDegrees: rot,
      scaleFactor: sc,
    );

    // Store face count and embedding (if available) for future reference
    if (_currentFaceCount != null) {
      final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
      Uint8List? embeddingBytes;
      if (_currentEmbedding != null) {
        embeddingBytes = StabUtils.embeddingToBytes(_currentEmbedding!);
      }
      await DB.instance.setPhotoFaceData(
        timestamp,
        projectId,
        _currentFaceCount!,
        embedding: embeddingBytes,
      );
      LogService.instance.log(
        "Stored face data: count=$_currentFaceCount, hasEmbedding=${embeddingBytes != null}",
      );
    }

    LogService.instance.log(
      "SUCCESS! STAB SCORE: $score (closer to 0 is better)",
    );
    LogService.instance.log(
      "FINAL TRANSFORM -> translateX: $tx, translateY: $ty, rotationDegrees: $rot, scaleFactor: $sc",
    );

    return true;
  }

  Future<void> _handleStabilizationFailure(
    String rawPhotoPath,
    String stabilizedJpgPhotoPath,
    List<String> toDelete,
  ) async {
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
    await DB.instance.setPhotoStabFailed(timestamp, projectId);
    unawaited(_emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.stabFailed));

    final String failureDir = await DirUtils.getFailureDirPath(projectId);
    final String failureImgPath = path.join(
      failureDir,
      path.basename(stabilizedJpgPhotoPath),
    );
    await DirUtils.createDirectoryIfNotExists(failureImgPath);
    await copyFile(stabilizedJpgPhotoPath, failureImgPath);

    final String stabilizedPngPath = stabilizedJpgPhotoPath.replaceAll(
      ".jpg",
      ".png",
    );
    toDelete.add(stabilizedPngPath);
  }

  Future<void> createStabThumbnail(String stabilizedPhotoPath) async {
    // Check if transparent background is enabled
    final bgColor = await SettingsUtil.loadBackgroundColor(
      projectId.toString(),
    );
    final isTransparent = SettingsUtil.isTransparent(bgColor);

    final String stabThumbnailPath = getStabThumbnailPath(
      stabilizedPhotoPath,
      preserveAlpha: isTransparent,
    );
    final String timestamp = path.basenameWithoutExtension(stabilizedPhotoPath);
    try {
      await DirUtils.createDirectoryIfNotExists(stabThumbnailPath);
      final bytes = await CameraUtils.readBytesInIsolate(stabilizedPhotoPath);
      if (bytes == null) {
        LogService.instance.log(
          "createStabThumbnail: bytes null for $stabilizedPhotoPath",
        );
        // Still emit success - widget will fall back to full image
        ThumbnailService.instance.emit(
          ThumbnailEvent(
            thumbnailPath: stabThumbnailPath,
            status: ThumbnailStatus.success,
            projectId: projectId,
            timestamp: timestamp,
          ),
        );
        return;
      }
      final thumbnailBytes = isTransparent
          ? await StabUtils.thumbnailPngFromPngBytes(bytes)
          : await StabUtils.thumbnailJpgFromPngBytes(bytes);
      await File(stabThumbnailPath).writeAsBytes(thumbnailBytes);

      ThumbnailService.instance.emit(
        ThumbnailEvent(
          thumbnailPath: stabThumbnailPath,
          status: ThumbnailStatus.success,
          projectId: projectId,
          timestamp: timestamp,
        ),
      );
    } catch (e) {
      LogService.instance.log("createStabThumbnail error (non-fatal): $e");
      // Still emit success so widget doesn't stay stuck - it will fall back to full image
      ThumbnailService.instance.emit(
        ThumbnailEvent(
          thumbnailPath: stabThumbnailPath,
          status: ThumbnailStatus.success,
          projectId: projectId,
          timestamp: timestamp,
        ),
      );
    }
  }

  /// Creates thumbnail and waits for completion. Use this for manual
  /// restabilization where we need the thumbnail ready before UI updates.
  Future<String> createStabThumbnailFromRawPath(String rawPhotoPath) async {
    final String stabilizedPath = await StabUtils.getStabilizedImagePath(
      rawPhotoPath,
      projectId,
      projectOrientation,
    );
    final String pngPath = path.setExtension(stabilizedPath, '.png');
    await createStabThumbnail(pngPath);
    return getStabThumbnailPath(pngPath);
  }

  Future<void> _emitThumbnailFailure(
    String rawPhotoPath,
    ThumbnailStatus status,
  ) async {
    final String timestamp = path
        .basenameWithoutExtension(rawPhotoPath)
        .replaceAll('_flipped', '')
        .replaceAll('_rotated_counter_clockwise', '')
        .replaceAll('_rotated_clockwise', '');
    final String stabilizedPath = await StabUtils.getStabilizedImagePath(
      rawPhotoPath,
      projectId,
      projectOrientation,
    );
    final String thumbnailPath = getStabThumbnailPath(
      path.setExtension(stabilizedPath, '.png'),
    );

    ThumbnailService.instance.emit(
      ThumbnailEvent(
        thumbnailPath: thumbnailPath,
        status: status,
        projectId: projectId,
        timestamp: timestamp,
      ),
    );
  }

  Future<(double?, double?)> _calculateRotationAndScale(
    String rawPhotoPath,
    int imgWidth,
    int imgHeight,
    Rect? targetBoundingBox,
    userRanOutOfSpaceCallback, {
    Uint8List? cvBytes,
  }) async {
    try {
      if (projectType == "face") {
        return await _calculateRotationAngleAndScaleFace(
          rawPhotoPath,
          imgWidth,
          imgHeight,
          targetBoundingBox,
          userRanOutOfSpaceCallback,
          cvBytes: cvBytes,
        );
      } else if (projectType == "cat" || projectType == "dog") {
        return await _calculateRotationAngleAndScaleAnimal(
          rawPhotoPath,
          imgWidth,
          imgHeight,
          targetBoundingBox,
          userRanOutOfSpaceCallback,
          cvBytes: cvBytes,
        );
      } else if (projectType == "pregnancy") {
        final Uint8List? bytes = cvBytes ??
            await FormatDecodeUtils.loadCvCompatibleBytes(rawPhotoPath);
        if (bytes == null) return (null, null);
        return await _calculateRotationAngleAndScalePregnancy(bytes);
      } else if (projectType == "musc") {
        final Uint8List? bytes = cvBytes ??
            await FormatDecodeUtils.loadCvCompatibleBytes(rawPhotoPath);
        if (bytes == null) return (null, null);
        return await _calculateRotationAngleAndScaleMusc(bytes);
      } else {
        return (null, null);
      }
    } catch (e) {
      LogService.instance.log("Error caught: $e");
      return (null, null);
    }
  }

  /// Shared scaffold for eye-based rotation/scale calculation (face, cat, dog).
  ///
  /// Uses [preloadedFaces] if provided (avoiding a redundant detection call),
  /// otherwise calls [getFacesFromRawPhotoPath]. Handles [targetBoundingBox]
  /// selection, extracts eyes, then delegates multi-face selection to
  /// [selectEyes]. Validates the result, stores [originalEyePositions] and
  /// returns the eye metrics.
  Future<(double?, double?)> _calculateRotationAngleAndScaleEye(
    String rawPhotoPath,
    int imgWidth,
    int imgHeight,
    Rect? targetBoundingBox,
    String noFacesLogMessage, {
    Uint8List? cvBytes,
    List<dynamic>? preloadedFaces,
    required Future<List<Point<double>?>> Function(
      List<dynamic> facesToUse,
      List<Point<double>?> eyes,
    ) selectEyes,
  }) async {
    final List<dynamic>? faces;
    if (preloadedFaces != null) {
      faces = preloadedFaces;
    } else {
      final bool noFaceSizeFilter = targetBoundingBox != null;
      faces = await getFacesFromRawPhotoPath(
        rawPhotoPath,
        imgWidth,
        filterByFaceSize: !noFaceSizeFilter,
        cvBytes: cvBytes,
      );
    }

    if (faces == null || faces.isEmpty) {
      LogService.instance.log(noFacesLogMessage);
      return (null, null);
    }

    List<dynamic> facesToUse = faces;
    if (targetBoundingBox != null) {
      final idx = await _pickFaceIndexByBoxAsync(faces, targetBoundingBox);
      if (idx != -1) {
        facesToUse = [faces[idx]];
      }
    }

    List<Point<double>?> eyes = await getEyesFromFacesAsync(facesToUse);

    if (facesToUse.length > 1) {
      eyes = await selectEyes(facesToUse, eyes);
    }

    if (!_areEyesValid(eyes)) {
      await DB.instance.setPhotoNoFacesFound(
        path.basenameWithoutExtension(rawPhotoPath),
        projectId,
      );
      unawaited(
        _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound),
      );
      return (null, null);
    }

    originalEyePositions = eyes;
    return _calculateEyeMetrics(eyes);
  }

  /// Cat/dog stabilization: like face but without embedding-based multi-face matching.
  /// Uses centermost animal selection when multiple are detected.
  Future<(double?, double?)> _calculateRotationAngleAndScaleAnimal(
    String rawPhotoPath,
    int imgWidth,
    int imgHeight,
    Rect? targetBoundingBox,
    userRanOutOfSpaceCallback, {
    Uint8List? cvBytes,
  }) async {
    return _calculateRotationAngleAndScaleEye(
      rawPhotoPath,
      imgWidth,
      imgHeight,
      targetBoundingBox,
      "No $projectType faces found.",
      cvBytes: cvBytes,
      selectEyes: (facesToUse, eyes) async {
        // No embedding support for cat/dog — always use centermost
        LogService.instance.log(
          "Multiple ${projectType}s detected, using centermost",
        );
        return getCentermostEyesAsync(eyes, facesToUse, imgWidth, imgHeight);
      },
    );
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleFace(
    String rawPhotoPath,
    int imgWidth,
    int imgHeight,
    Rect? targetBoundingBox,
    userRanOutOfSpaceCallback, {
    Uint8List? cvBytes,
  }) async {
    // Reset face tracking for this photo
    _currentFaceCount = null;
    _currentEmbedding = null;

    // Load faces up front to track count and extract embedding before delegating.
    final bool noFaceSizeFilter = targetBoundingBox != null;
    final faces = await getFacesFromRawPhotoPath(
      rawPhotoPath,
      imgWidth,
      filterByFaceSize: !noFaceSizeFilter,
      cvBytes: cvBytes,
    );
    if (faces == null || faces.isEmpty) {
      LogService.instance.log("No faces found.");
      return (null, null);
    }

    // Track face count for embedding storage
    _currentFaceCount = faces.length;

    // For single-face photos, extract embedding for future reference
    if (faces.length == 1) {
      await _extractAndStoreEmbedding(rawPhotoPath);
    }

    return _calculateRotationAngleAndScaleEye(
      rawPhotoPath,
      imgWidth,
      imgHeight,
      targetBoundingBox,
      "No faces found.",
      preloadedFaces: faces,
      selectEyes: (facesToUse, eyes) async {
        // Multiple faces detected - try embedding-based selection first
        final int? embeddingPickedIdx = await _tryPickFaceByEmbedding(
          rawPhotoPath,
          facesToUse.length,
        );

        if (embeddingPickedIdx != null && embeddingPickedIdx >= 0) {
          // Embedding match found - use that face
          LogService.instance.log(
            "Using embedding-matched face at index $embeddingPickedIdx",
          );
          final int li = 2 * embeddingPickedIdx;
          final int ri = li + 1;
          if (ri < eyes.length && eyes[li] != null && eyes[ri] != null) {
            return [eyes[li]!, eyes[ri]!];
          } else {
            // Fallback to centermost if eyes extraction failed for matched face
            return getCentermostEyesAsync(
                eyes, facesToUse, imgWidth, imgHeight);
          }
        } else {
          // No embedding reference found - fallback to centermost
          LogService.instance.log(
            "No embedding reference found, using centermost face",
          );
          return getCentermostEyesAsync(eyes, facesToUse, imgWidth, imgHeight);
        }
      },
    );
  }

  /// Tries to pick the correct face using embedding similarity.
  /// Returns the face index if a reference embedding was found and matching succeeded.
  /// Returns null if no reference embedding exists (fallback to centermost).
  /// Uses cached PNG bytes and raw faces from previous detection to avoid redundant work.
  Future<int?> _tryPickFaceByEmbedding(
    String rawPhotoPath,
    int faceCount,
  ) async {
    try {
      final String timestamp = path.basenameWithoutExtension(rawPhotoPath);

      // Query for the closest single-face photo's embedding
      final closestSingleFace = await DB.instance.getClosestSingleFacePhoto(
        timestamp,
        projectId,
      );

      if (closestSingleFace == null) {
        LogService.instance.log(
          "No single-face reference photos found for embedding matching",
        );
        return null;
      }

      final Uint8List? embeddingBytes =
          closestSingleFace['faceEmbedding'] as Uint8List?;
      if (embeddingBytes == null) {
        return null;
      }

      final Float32List referenceEmbedding = StabUtils.bytesToEmbedding(
        embeddingBytes,
      );
      final String refTimestamp = closestSingleFace['timestamp'] as String;
      LogService.instance.log(
        "Using reference embedding from photo $refTimestamp for face matching",
      );

      final Uint8List? imageBytes = _lastCvBytes ??
          await FormatDecodeUtils.loadCvCompatibleBytes(rawPhotoPath);
      if (imageBytes == null) return null;

      final List<dynamic>? rawFaces = _lastRawFaces;

      final int bestIdx = await StabUtils.pickFaceIndexByEmbedding(
        referenceEmbedding,
        imageBytes,
        preDetectedFaces: rawFaces?.cast(),
      );

      return bestIdx;
    } catch (e) {
      LogService.instance.log("Error in embedding-based face selection: $e");
      return null;
    }
  }

  /// Extracts and stores the face embedding for a single-face photo.
  Future<void> _extractAndStoreEmbedding(String rawPhotoPath) async {
    try {
      final Uint8List? imageBytes = _lastCvBytes ??
          await FormatDecodeUtils.loadCvCompatibleBytes(rawPhotoPath);
      if (imageBytes == null) return;

      final Float32List? embedding = await StabUtils.getFaceEmbeddingFromBytes(
        imageBytes,
      );

      if (embedding != null) {
        _currentEmbedding = embedding;
        LogService.instance.log(
          "Extracted face embedding (${embedding.length} dims) for single-face photo",
        );
      }
    } catch (e) {
      LogService.instance.log("Error extracting face embedding: $e");
    }
  }

  // ============================================================
  // ISOLATE-BACKED COORDINATE PROCESSING METHODS
  // ============================================================

  /// Isolate-backed version of _filterAndCenterEyes.
  Future<List<Point<double>?>> _filterAndCenterEyesAsync(
    List<dynamic> stabFaces,
  ) async {
    if (stabFaces.isEmpty) return [];

    final facesData = stabFaces.map((f) => (f as FaceLike).toMap()).toList();

    final result = await IsolatePool.instance
        .execute<List<dynamic>>('filterAndCenterEyes', {
      'faces': facesData,
      'imgWidth': canvasWidth,
      'imgHeight': canvasHeight,
      'eyeDistanceGoal': eyeDistanceGoal,
    });

    if (result == null || result.isEmpty) return [];

    return result.map((e) {
      if (e == null) return null;
      final list = e as List;
      return Point<double>(
        (list[0] as num).toDouble(),
        (list[1] as num).toDouble(),
      );
    }).toList();
  }

  /// Isolate-backed version of getEyesFromFaces.
  Future<List<Point<double>?>> getEyesFromFacesAsync(
    List<dynamic> faces,
  ) async {
    if (faces.isEmpty) return [];

    final facesData = faces.map((f) => (f as FaceLike).toMap()).toList();

    final result = await IsolatePool.instance.execute<List<dynamic>>(
      'getEyesFromFaces',
      {'faces': facesData},
    );

    if (result == null) return [];

    return result.map((e) {
      if (e == null) return null;
      final list = e as List;
      return Point<double>(
        (list[0] as num).toDouble(),
        (list[1] as num).toDouble(),
      );
    }).toList();
  }

  /// Isolate-backed version of getCentermostEyes.
  Future<List<Point<double>>> getCentermostEyesAsync(
    List<Point<double>?> eyes,
    List<dynamic> faces,
    int imgWidth,
    int imgHeight,
  ) async {
    if (eyes.isEmpty || faces.isEmpty) return [];

    final eyesData = eyes.map((e) => e != null ? [e.x, e.y] : null).toList();
    final facesData = faces.map((f) => (f as FaceLike).toMap()).toList();

    final result = await IsolatePool.instance.execute<List<dynamic>>(
      'getCentermostEyes',
      {
        'eyes': eyesData,
        'faces': facesData,
        'imgWidth': imgWidth,
        'imgHeight': imgHeight,
      },
    );

    if (result == null || result.isEmpty) return [];

    return result.map((e) {
      final list = e as List;
      return Point<double>(
        (list[0] as num).toDouble(),
        (list[1] as num).toDouble(),
      );
    }).toList();
  }

  /// Isolate-backed version of _pickFaceIndexByBox.
  Future<int> _pickFaceIndexByBoxAsync(
    List<dynamic> faces,
    Rect targetBox,
  ) async {
    if (faces.isEmpty) return -1;

    final facesData = faces.map((f) => (f as FaceLike).toMap()).toList();

    final result = await IsolatePool.instance.execute<int>(
      'pickFaceIndexByBox',
      {
        'faces': facesData,
        'targetBox': [
          targetBox.left,
          targetBox.top,
          targetBox.right,
          targetBox.bottom,
        ],
      },
    );

    return result ?? -1;
  }

  /// Runs the pose detector and returns the first detected pose, or null if none found.
  Future<pose.Pose?> _detectFirstPose(Uint8List cvBytes) async {
    List<pose.Pose>? poses;
    try {
      poses = await _poseDetector?.detect(cvBytes);
    } catch (e) {
      LogService.instance.log("Error caught => $e");
    }
    if (poses == null || poses.isEmpty) return null;
    return poses.first;
  }

  Future<(double?, double?)> _calculateRotationAngleAndScalePregnancy(
    Uint8List cvBytes,
  ) async {
    final pose.Pose? p = await _detectFirstPose(cvBytes);
    if (p == null) return (null, null);
    final Point rightAnklePos = Point(
      p.getLandmark(pose.PoseLandmarkType.rightAnkle)!.x,
      p.getLandmark(pose.PoseLandmarkType.rightAnkle)!.y,
    );
    final Point nosePos = Point(
      p.getLandmark(pose.PoseLandmarkType.nose)!.x,
      p.getLandmark(pose.PoseLandmarkType.nose)!.y,
    );

    originalRightAnkleX = rightAnklePos.x.toDouble();
    originalRightAnkleY = rightAnklePos.y.toDouble();
    final double verticalDistance = (originalRightAnkleY - nosePos.y).abs();
    final double horizontalDistance = (originalRightAnkleX - nosePos.x).abs();
    double hypotenuse = sqrt(
      pow(verticalDistance, 2) + pow(horizontalDistance, 2),
    );
    if (hypotenuse < 1.0) return (null, null);
    double scaleFactor = bodyDistanceGoal / hypotenuse;
    double rotationDegreesRaw =
        90 - (atan2(verticalDistance, horizontalDistance) * (180 / pi));
    double rotationGoal = 6;
    double rotationDegrees = (rotationGoal - rotationDegreesRaw);

    return (scaleFactor, rotationDegrees);
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleMusc(
    Uint8List cvBytes,
  ) async {
    final pose.Pose? p = await _detectFirstPose(cvBytes);
    if (p == null) return (null, null);
    final Point leftHipPos = Point(
      p.getLandmark(pose.PoseLandmarkType.leftHip)!.x,
      p.getLandmark(pose.PoseLandmarkType.leftHip)!.y,
    );
    final Point rightHipPos = Point(
      p.getLandmark(pose.PoseLandmarkType.rightHip)!.x,
      p.getLandmark(pose.PoseLandmarkType.rightHip)!.y,
    );

    originalRightHipX = rightHipPos.x.toDouble();
    originalRightHipY = rightHipPos.y.toDouble();
    final num verticalDistance = (rightHipPos.y - leftHipPos.y).abs();
    final num horizontalDistance = (rightHipPos.x - leftHipPos.x).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) *
        (180 / pi) *
        (rightHipPos.y > leftHipPos.y ? -1 : 1);
    double hypotenuse = sqrt(
      pow(verticalDistance.toDouble(), 2) +
          pow(horizontalDistance.toDouble(), 2),
    );
    if (hypotenuse < 1.0) return (null, null);
    double scaleFactor = eyeDistanceGoal / hypotenuse;

    return (scaleFactor, rotationDegrees);
  }

  /// Returns the thumbnail path for a stabilized photo.
  /// When [preserveAlpha] is null (default), checks if a .png thumbnail exists
  /// first, then falls back to .jpg. When explicitly set, uses that format.
  static String getStabThumbnailPath(
    String stabilizedPhotoPath, {
    bool? preserveAlpha,
  }) {
    final String dirname = path.dirname(stabilizedPhotoPath);
    final String basenameWithoutExt = path.basenameWithoutExtension(
      stabilizedPhotoPath,
    );
    final thumbDir = path.join(dirname, DirUtils.thumbnailDirname);

    // If explicitly specified, use that format
    if (preserveAlpha != null) {
      final ext = preserveAlpha ? '.png' : '.jpg';
      return path.join(thumbDir, "$basenameWithoutExt$ext");
    }

    // Auto-detect: prefer .png if it exists, otherwise .jpg
    final pngPath = path.join(thumbDir, "$basenameWithoutExt.png");
    if (File(pngPath).existsSync()) {
      return pngPath;
    }
    return path.join(thumbDir, "$basenameWithoutExt.jpg");
  }

  (double?, double?) _calculateTranslateData(
    double scaleFactor,
    double rotationDegrees,
    int imgWidth,
    int imgHeight,
  ) {
    num goalX;
    num goalY;
    if (_isEyeBasedProject) {
      goalX = leftEyeXGoal;
      goalY = bothEyesYGoal;
    } else if (projectType == "pregnancy") {
      goalX = pregRightAnkleXGoal;
      goalY = pregRightAnkleYGoal;
    } else {
      goalX = muscRightHipXGoal;
      goalY = muscRightHipYGoal;
    }
    Map<String, double> transformedPoint = transformPoint(
      scaleFactor,
      rotationDegrees,
      imgWidth,
      imgHeight,
    );
    double? translateX = (goalX - transformedPoint['x']!);
    double? translateY = (goalY - transformedPoint['y']!);
    return (translateX, translateY);
  }

  static Future<String> saveBytesToPngFileInIsolate(
    Uint8List imageBytes,
    String saveToPath,
  ) async {
    Future<void> saveImageIsolateOperation(Map<String, dynamic> params) async {
      SendPort sendPort = params['sendPort'];
      Uint8List bytes = params['imageBytes'];
      String saveToPath = params['saveToPath'];
      try {
        await File(saveToPath).writeAsBytes(bytes);
        sendPort.send("success");
      } catch (e) {
        if (e is FileSystemException && e.osError?.errorCode == 28) {
          // If user runs out of space...
          LogService.instance.log("No space left on device error caught => $e");
          sendPort.send("NoSpaceLeftError");
        } else {
          LogService.instance.log("Error caught => $e");
          sendPort.send("Error");
        }
      }
    }

    await DirUtils.createDirectoryIfNotExists(saveToPath);
    ReceivePort receivePort = ReceivePort();
    var params = {
      'sendPort': receivePort.sendPort,
      'saveToPath': saveToPath,
      'imageBytes': imageBytes,
    };
    final isolate = await Isolate.spawn(saveImageIsolateOperation, params);
    IsolateManager.instance.register(isolate);

    try {
      return await receivePort.first;
    } finally {
      receivePort.close();
      IsolateManager.instance.unregister(isolate);
      isolate.kill(priority: Isolate.immediate);
    }
  }

  (double, double, double, double) _calculateOvershots(
    List<Point<double>?> eyes,
    Point<double> goalLeftEye,
    Point<double> goalRightEye,
  ) {
    final double overshotLeftX = eyes[0]!.x - goalLeftEye.x;
    final double overshotLeftY = eyes[0]!.y - goalLeftEye.y;
    final double overshotRightX = eyes[1]!.x - goalRightEye.x;
    final double overshotRightY = eyes[1]!.y - goalRightEye.y;
    return (overshotLeftX, overshotLeftY, overshotRightX, overshotRightY);
  }

  (double, double) _calculateNewTranslations(
    double translateX,
    double translateY,
    double overshotLeftX,
    double overshotRightX,
    double overshotLeftY,
    double overshotRightY,
  ) {
    final double overshotAverageX = (overshotLeftX + overshotRightX) / 2;
    final double overshotAverageY = (overshotLeftY + overshotRightY) / 2;
    final double newTranslateX = translateX - overshotAverageX.toDouble();
    final double newTranslateY = translateY - overshotAverageY.toDouble();
    return (newTranslateX, newTranslateY);
  }

  List<Point<double>> getCentermostEyes(
    List<Point<double>?> eyes,
    List<dynamic> faces,
    int imgWidth,
    int imgHeight,
  ) {
    double smallestDistance = double.infinity;
    List<Point<double>> centeredEyes = [];

    // Filter to faces with detected eyes
    faces = faces.where((face) {
      return face.leftEye != null && face.rightEye != null;
    }).toList();

    final double marginPx = max(4.0, imgWidth * 0.01);

    bool touchesEdge(Rect bbox) {
      return bbox.left <= marginPx ||
          bbox.top <= marginPx ||
          bbox.right >= imgWidth - marginPx ||
          bbox.bottom >= imgHeight - marginPx;
    }

    final int pairCount = eyes.length ~/ 2;
    final int limit = faces.length < pairCount ? faces.length : pairCount;

    for (var i = 0; i < limit; i++) {
      final Rect bbox = faces[i].boundingBox;
      if (touchesEdge(bbox)) continue;

      final int li = 2 * i, ri = li + 1;
      final Point<double>? leftEye = eyes[li];
      final Point<double>? rightEye = eyes[ri];
      if (leftEye == null || rightEye == null) continue;

      final double distance = (leftEye.x - imgWidth ~/ 2).abs() +
          (rightEye.x - imgWidth ~/ 2).abs();

      if (distance < smallestDistance) {
        smallestDistance = distance;
        centeredEyes = [leftEye, rightEye];
      }
    }

    if (centeredEyes.isEmpty &&
        eyes.length >= 2 &&
        eyes[0] != null &&
        eyes[1] != null) {
      centeredEyes = [eyes[0]!, eyes[1]!];
    }

    eyes.clear();
    eyes.addAll(centeredEyes);
    return centeredEyes;
  }

  Uint8List? _lastCvBytes;
  List<dynamic>? _lastRawFaces;

  /// Dispatches face detection to the correct detector based on project type.
  /// Used by multi-pass refinement to re-detect faces in stabilized images.
  Future<List<FaceLike>?> _detectFaces(
    Uint8List bytes, {
    bool filterByFaceSize = true,
    int? imageWidth,
  }) async {
    return StabUtils.getFacesFromBytesForProjectType(
      projectType,
      bytes,
      filterByFaceSize: filterByFaceSize,
      imageWidth: imageWidth,
    );
  }

  /// Detects faces in [bytes] and returns filtered/centered eye positions.
  /// Returns null if face detection fails (null faces list) or if valid eye
  /// positions cannot be extracted from the detected faces.
  Future<List<Point<double>?>?> _detectAndFilterEyes(Uint8List bytes) async {
    final faces = await _detectFaces(
      bytes,
      filterByFaceSize: false,
      imageWidth: canvasWidth,
    );
    if (faces == null) return null;
    final eyes = await _filterAndCenterEyesAsync(faces);
    if (!_areEyesValid(eyes)) return null;
    return eyes;
  }

  Future<List<dynamic>?> getFacesFromRawPhotoPath(
    String rawPhotoPath,
    int width, {
    bool filterByFaceSize = true,
    Uint8List? cvBytes,
  }) async {
    await _ensureReady();
    cvBytes ??= await FormatDecodeUtils.loadCvCompatibleBytes(rawPhotoPath);
    if (cvBytes == null) return null;
    _lastCvBytes = cvBytes;

    // Cat/dog don't return raw faces (no embedding support)
    if (projectType == "cat" || projectType == "dog") {
      final faces = await _detectFaces(
        cvBytes,
        filterByFaceSize: filterByFaceSize,
        imageWidth: width,
      );
      _lastRawFaces = null;
      return faces;
    }

    final result = await StabUtils.getFacesFromBytesWithRaw(
      cvBytes,
      filterByFaceSize: filterByFaceSize,
      imageWidth: width,
    );

    if (result == null) return null;
    _lastRawFaces = result.$2;

    return result.$1;
  }

  List<Point<double>?> getEyesFromFaces(dynamic faces) {
    final List<Point<double>?> eyes = [];
    for (final f in (faces as List)) {
      Point<double>? a = f.leftEye == null
          ? null
          : Point<double>(f.leftEye!.x.toDouble(), f.leftEye!.y.toDouble());
      Point<double>? b = f.rightEye == null
          ? null
          : Point<double>(f.rightEye!.x.toDouble(), f.rightEye!.y.toDouble());

      if (a == null || b == null) {
        final Rect bb = f.boundingBox as Rect;
        final double ey = bb.top + bb.height * 0.42;
        a = Point((bb.left + bb.width * 0.33), ey);
        b = Point((bb.left + bb.width * 0.67), ey);
      }

      if (a.x > b.x) {
        final tmp = a;
        a = b;
        b = tmp;
      }
      eyes
        ..add(a)
        ..add(b);
    }
    return eyes;
  }

  Future<bool> videoSettingsChanged() async =>
      await VideoUtils.videoOutputSettingsChanged(
        projectId,
        await DB.instance.getNewestVideoByProjectId(projectId),
      );

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
      );

  Future<void> setPhotoStabilized(
    String rawPhotoPath, {
    double? translateX,
    double? translateY,
    double? rotationDegrees,
    double? scaleFactor,
  }) async {
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
    await DB.instance.setPhotoStabilized(
      timestamp,
      projectId,
      projectOrientation!, // Use cached value - initialized in initializeProjectSettings()
      aspectRatio,
      resolution,
      eyeOffsetX,
      eyeOffsetY,
      translateX: translateX,
      translateY: translateY,
      rotationDegrees: rotationDegrees,
      scaleFactor: scaleFactor,
    );
  }

  double calculateStabScore(
    List<Point<double>?> eyes,
    Point<double> goalLeftEye,
    Point<double> goalRightEye,
  ) {
    final double distanceLeftEye = calculateDistance(eyes[0]!, goalLeftEye);
    final double distanceRightEye = calculateDistance(eyes[1]!, goalRightEye);
    return ((distanceLeftEye + distanceRightEye) * 1000 / 2) / canvasHeight;
  }

  double calculateDistance(Point<double> point1, Point<double> point2) {
    return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2));
  }

  bool correctionIsNeeded(
    double score,
    double overshotLeftX,
    double overshotRightX,
    double overshotLeftY,
    double overshotRightY,
  ) {
    if (score > 0.5) return true;
    return ((overshotLeftX > 0 && overshotRightX > 0) ||
        (overshotLeftX < 0 && overshotRightX < 0) ||
        (overshotLeftY > 0 && overshotRightY > 0) ||
        (overshotLeftY < 0 && overshotRightY < 0));
  }

  Future<void> copyFile(String sourcePath, String destinationPath) async {
    try {
      final File file = File(sourcePath);
      if (await file.exists()) {
        await file.copy(destinationPath);
      }
    } catch (e) {
      LogService.instance.log('Error copying file: $e');
    }
  }

  Map<String, double> transformPoint(
    double scaleFactor,
    double rotationDegrees,
    int imgWidth,
    int imgHeight,
  ) {
    final double originalPointX;
    final double originalPointY;
    if (_isEyeBasedProject) {
      originalPointX = originalEyePositions![0]!.x.toDouble();
      originalPointY = originalEyePositions![0]!.y.toDouble();
    } else if (projectType == "pregnancy") {
      originalPointX = originalRightAnkleX;
      originalPointY = originalRightAnkleY;
    } else {
      originalPointX = originalRightHipX;
      originalPointY = originalRightHipY;
    }
    return transformPointByCanvasSize(
      originalPointX: originalPointX,
      originalPointY: originalPointY,
      scale: scaleFactor,
      rotationDegrees: rotationDegrees,
      canvasWidth: canvasWidth.toDouble(),
      canvasHeight: canvasHeight.toDouble(),
      originalWidth: imgWidth.toDouble(),
      originalHeight: imgHeight.toDouble(),
    );
  }

  Map<String, double> transformPointByCanvasSize({
    required double originalPointX,
    required double originalPointY,
    required double scale,
    required double rotationDegrees,
    required double canvasWidth,
    required double canvasHeight,
    required double originalWidth,
    required double originalHeight,
  }) {
    double scaledWidth = originalWidth * scale;
    double scaledHeight = originalHeight * scale;

    double translatedX = originalPointX * scale - scaledWidth / 2;
    double translatedY = originalPointY * scale - scaledHeight / 2;

    double angleRadians = rotationDegrees * pi / 180;
    double rotatedX =
        translatedX * cos(angleRadians) - translatedY * sin(angleRadians);
    double rotatedY =
        translatedX * sin(angleRadians) + translatedY * cos(angleRadians);

    double finalX =
        rotatedX + scaledWidth / 2 + (canvasWidth - scaledWidth) / 2;
    double finalY =
        rotatedY + scaledHeight / 2 + (canvasHeight - scaledHeight) / 2;

    return {'x': finalX, 'y': finalY};
  }

  (double, double) _calculateEyeMetrics(List<Point<double>?> detectedEyes) {
    final Point<double> leftEye = detectedEyes[0]!;
    final Point<double> rightEye = detectedEyes[1]!;
    final double verticalDistance = (rightEye.y - leftEye.y).abs();
    final double horizontalDistance = (rightEye.x - leftEye.x).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) *
        (180 / pi) *
        (rightEye.y > leftEye.y ? -1 : 1);
    double hypotenuse = sqrt(
      pow(verticalDistance, 2) + pow(horizontalDistance, 2),
    );
    if (hypotenuse < 1.0) return (1.0, 0.0);
    double scaleFactor = eyeDistanceGoal / hypotenuse;

    return (scaleFactor, rotationDegrees);
  }

  /// Returns true if [eyes] has at least two non-null entries.
  bool _areEyesValid(List<Point<double>?>? eyes) {
    return eyes != null &&
        eyes.length >= 2 &&
        eyes[0] != null &&
        eyes[1] != null;
  }

  /// Returns the Euclidean distance between the two eye points.
  double _eyeDistance(List<Point<double>?> eyes) {
    return sqrt(
      pow(eyes[1]!.x - eyes[0]!.x, 2) + pow(eyes[1]!.y - eyes[0]!.y, 2),
    );
  }

  /// Updates previousPassBytes when a new best is found in refinement passes.
  /// Returns the updated [previousPassBytes] value.
  Uint8List? _updatePreviousPassBytes(
    Uint8List? previousPassBytes,
    Uint8List? bestBytes,
    Uint8List? imageBytesStabilized,
  ) =>
      identical(bestBytes, imageBytesStabilized) ? null : bestBytes;
}
