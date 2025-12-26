import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'cancellation_token.dart';
import 'isolate_manager.dart';
import 'log_service.dart';
import 'thumbnail_service.dart';
import '../models/stabilization_mode.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path/path.dart' as path;
import '../utils/camera_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/heic_utils.dart';
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
  factory StabilizationResult.cancelled() => StabilizationResult(
        success: false,
        cancelled: true,
      );
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
  final Map<String, String> heicToJpgMap = {};
  late int pregRightAnkleYGoal;
  late int pregRightAnkleXGoal;
  late int muscRightHipYGoal;
  late int muscRightHipXGoal;
  PoseDetector? _poseDetector;
  late double eyeOffsetX;
  late double eyeOffsetY;
  late StabilizationMode stabilizationMode;

  // Face embedding tracking for identity-based face matching
  int? _currentFaceCount;
  Float32List? _currentEmbedding;

  final VoidCallback userRanOutOfSpaceCallbackIn;

  FaceStabilizer(this.projectId, this.userRanOutOfSpaceCallbackIn);

  bool _disposed = false;

  /// Releases native resources held by the pose detector.
  /// Must be called when the stabilizer is no longer needed.
  /// Safe to call multiple times (idempotent).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _poseDetector?.close();
    _poseDetector = null;

    // Delete temp HEIC-to-JPG conversions created by this instance
    for (final tempPath in heicToJpgMap.values) {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
    heicToJpgMap.clear();
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
    String? rawProjectType =
        await DB.instance.getProjectTypeByProjectId(projectId);

    projectType = rawProjectType!.toLowerCase();
    projectOrientation =
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(projectId.toString());
    aspectRatioDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);

    if (projectType != "face") {
      final PoseDetector poseDetector = PoseDetector(
          options: PoseDetectorOptions(
              mode: PoseDetectionMode.single,
              model: PoseDetectionModel.accurate));
      _poseDetector = poseDetector;
    }

    final double? shortSideDouble = StabUtils.getShortSide(resolution);
    final int longSide = (aspectRatioDecimal! * shortSideDouble!).toInt();
    final int shortSide = shortSideDouble.toInt();

    canvasWidth = projectOrientation == "landscape" ? longSide : shortSide;
    canvasHeight = projectOrientation == "landscape" ? shortSide : longSide;

    // Load stabilization mode (global setting)
    final String modeStr = await SettingsUtil.loadStabilizationMode();
    stabilizationMode = StabilizationMode.fromString(modeStr);

    await _initializeGoalsAndOffsets();
  }

  Future<void> _initializeGoalsAndOffsets() async {
    final String offsetX =
        await SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString());
    final String offsetY =
        await SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString());
    eyeOffsetX = double.parse(offsetX);
    eyeOffsetY = double.parse(offsetY);

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

      rawPhotoPath = await _convertHeicToJpgIfNeeded(rawPhotoPath);
      if (rawPhotoPath.contains("_flipped_flipped")) {
        token?.throwIfCancelled();
        final bool success =
            await tryRotation(rawPhotoPath, userRanOutOfSpaceCallback, token);
        return StabilizationResult(success: success);
      }

      double? rotationDegrees, scaleFactor, translateX, translateY;

      token?.throwIfCancelled();
      await StabUtils.preparePNG(rawPhotoPath);
      final String canonicalPath =
          await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

      // Load source image bytes asynchronously to avoid blocking UI
      token?.throwIfCancelled();
      final Uint8List? srcBytes =
          await StabUtils.loadPngBytesAsync(canonicalPath);
      if (srcBytes == null) return StabilizationResult(success: false);

      // Get dimensions asynchronously (decode runs in isolate)
      token?.throwIfCancelled();
      final dims = await StabUtils.getImageDimensionsFromBytesAsync(srcBytes,
          token: token);
      if (dims == null) return StabilizationResult(success: false);
      final (int imgWidth, int imgHeight) = dims;

      token?.throwIfCancelled();
      (scaleFactor, rotationDegrees) = await _calculateRotationAndScale(
          rawPhotoPath,
          imgWidth,
          imgHeight,
          targetBoundingBox,
          userRanOutOfSpaceCallback);
      if (rotationDegrees == null || scaleFactor == null) {
        return StabilizationResult(success: false);
      }

      (translateX, translateY) = _calculateTranslateData(
          scaleFactor, rotationDegrees, imgWidth, imgHeight);
      if (translateX == null || translateY == null) {
        return StabilizationResult(success: false);
      }

      if (projectType == "musc") translateY = 0;

      // Generate stabilized bytes using OpenCV in isolate (avoids blocking UI)
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
      );
      if (imageBytesStabilized == null) {
        return StabilizationResult(success: false);
      }

      String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
          rawPhotoPath, projectId, projectOrientation);
      stabilizedPhotoPath = _cleanUpPhotoPath(stabilizedPhotoPath);
      rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

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
          rawPhotoPath,
          stabilizedPhotoPath,
          imgWidth,
          imgHeight,
          translateX,
          translateY,
          rotationDegrees,
          scaleFactor,
          imageBytesStabilized,
          srcBytes,
          token);

      LogService.instance.log("Result => '$result'");

      if (result) {
        unawaited(createStabThumbnail(
            stabilizedPhotoPath.replaceAll('.jpg', '.png')));
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
          goalEyeDistance: eyeDistanceGoal);
    } on CancelledException {
      LogService.instance.log("Stabilization cancelled");
      return StabilizationResult.cancelled();
    } catch (e) {
      LogService.instance.log("Caught error: $e");
      return StabilizationResult(success: false);
    }
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
  ) async {
    if (projectType != "face") {
      await StabUtils.writeImagesBytesToJpgFile(
          imageBytesStabilized, stabilizedJpgPhotoPath);
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
        null
      ); // No scores for non-face projects
    }

    rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

    final Point<double> goalLeftEye = Point(leftEyeXGoal, bothEyesYGoal);
    final Point<double> goalRightEye = Point(rightEyeXGoal, bothEyesYGoal);

    // Detect faces directly from bytes using face_detection_tflite (works on all platforms)
    final stabFaces = await StabUtils.getFacesFromBytes(
      imageBytesStabilized,
      filterByFaceSize: false,
      imageWidth: canvasWidth,
    );

    if (stabFaces == null || stabFaces.isEmpty) {
      // No faces found after stabilization
      if (stabFaces != null && stabFaces.isEmpty) {
        await DB.instance
            .setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
        unawaited(
            _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound));
      }
      // Fall back to estimated eyes for scoring
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
      return (
        success,
        score,
        null,
        null,
        null,
        score,
        null,
        null
      ); // No multi-pass for fallback
    }

    List<Point<double>?> eyes = _filterAndCenterEyes(stabFaces);

    if (eyes.length < 2 || eyes[0] == null || eyes[1] == null) {
      await DB.instance
          .setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      unawaited(
          _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound));
      // Fall back to estimated eyes for scoring
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
      return (
        success,
        score,
        null,
        null,
        null,
        score,
        null,
        null
      ); // No multi-pass for fallback
    }

    LogService.instance.log(
        "Goal: L$goalLeftEye R$goalRightEye | Init: L${eyes[0]} R${eyes[1]}");

    List<String> toDelete = [
      await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath),
      stabilizedJpgPhotoPath
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
      );
    }
  }

  /// FAST MODE: Translation-only multi-pass correction (up to 4 passes).
  /// This is the original algorithm that only adjusts X/Y translation.
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
  ) async {
    bool successfulStabilization = false;

    final double firstPassScore =
        calculateStabScore(eyes, goalLeftEye, goalRightEye);
    final (
      double overshotLeftX,
      double overshotLeftY,
      double overshotRightX,
      double overshotRightY
    ) = _calculateOvershots(eyes, goalLeftEye, goalRightEye);

    if (!correctionIsNeeded(firstPassScore, overshotLeftX, overshotRightX,
        overshotLeftY, overshotRightY)) {
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
        null
      );
    }

    final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
        rawPhotoPath, projectId, projectOrientation);

    // Track best result across all passes
    Uint8List bestBytes = imageBytesStabilized;
    double bestScore = firstPassScore;
    double bestTX = translateX;
    double bestTY = translateY;

    // Track scores and state for each pass
    double? twoPassScore, threePassScore, fourPassScore;
    bool usedTwoPass = false, usedThreePass = false, usedFourPass = false;
    List<Point<double>?>? currentEyes = eyes;
    double currentTX = translateX;
    double currentTY = translateY;

    // === TWO-PASS ===
    token?.throwIfCancelled();
    LogService.instance.log(
        "Attempting two-pass correction. First-pass score = $firstPassScore...");

    var (double ovLX, double ovLY, double ovRX, double ovRY) =
        _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);
    final (double twoPassTX, double twoPassTY) =
        _calculateNewTranslations(currentTX, currentTY, ovLX, ovRX, ovLY, ovRY);

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
    );
    if (twoPassBytes == null)
      return (
        false,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        null,
        null
      );

    final twoPassFaces = await StabUtils.getFacesFromBytes(twoPassBytes,
        filterByFaceSize: false, imageWidth: canvasWidth);
    if (twoPassFaces == null)
      return (
        false,
        firstPassScore,
        null,
        null,
        null,
        firstPassScore,
        null,
        null
      );

    List<Point<double>?> twoPassEyes = _filterAndCenterEyes(twoPassFaces);

    if (twoPassEyes.length >= 2 &&
        twoPassEyes[0] != null &&
        twoPassEyes[1] != null) {
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
      }
    }

    // === THREE-PASS (only if two-pass improved) ===
    if (usedTwoPass &&
        currentEyes.length >= 2 &&
        currentEyes[0] != null &&
        currentEyes[1] != null) {
      token?.throwIfCancelled();
      (ovLX, ovLY, ovRX, ovRY) =
          _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);

      if (correctionIsNeeded(bestScore, ovLX, ovRX, ovLY, ovRY)) {
        LogService.instance.log(
            "Attempting three-pass correction. Two-pass score = $twoPassScore...");

        final (double threePassTX, double threePassTY) =
            _calculateNewTranslations(
                currentTX, currentTY, ovLX, ovRX, ovLY, ovRY);

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
        );

        if (threePassBytes != null) {
          final threePassFaces = await StabUtils.getFacesFromBytes(
              threePassBytes,
              filterByFaceSize: false,
              imageWidth: canvasWidth);

          if (threePassFaces != null) {
            List<Point<double>?> threePassEyes =
                _filterAndCenterEyes(threePassFaces);

            if (threePassEyes.length >= 2 &&
                threePassEyes[0] != null &&
                threePassEyes[1] != null) {
              threePassScore =
                  calculateStabScore(threePassEyes, goalLeftEye, goalRightEye);
              if (threePassScore < bestScore) {
                usedThreePass = true;
                bestBytes = threePassBytes;
                bestScore = threePassScore;
                bestTX = threePassTX;
                bestTY = threePassTY;
                currentEyes = threePassEyes;
                currentTX = threePassTX;
                currentTY = threePassTY;
              }
            }
          }
        }
      }
    }

    // === FOUR-PASS (only if three-pass improved) ===
    if (usedThreePass &&
        currentEyes.length >= 2 &&
        currentEyes[0] != null &&
        currentEyes[1] != null) {
      token?.throwIfCancelled();
      (ovLX, ovLY, ovRX, ovRY) =
          _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);

      if (correctionIsNeeded(bestScore, ovLX, ovRX, ovLY, ovRY)) {
        LogService.instance.log(
            "Attempting four-pass correction. Three-pass score = $threePassScore...");

        final (double fourPassTX, double fourPassTY) =
            _calculateNewTranslations(
                currentTX, currentTY, ovLX, ovRX, ovLY, ovRY);

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
        );

        if (fourPassBytes != null) {
          final fourPassFaces = await StabUtils.getFacesFromBytes(fourPassBytes,
              filterByFaceSize: false, imageWidth: canvasWidth);

          if (fourPassFaces != null) {
            List<Point<double>?> fourPassEyes =
                _filterAndCenterEyes(fourPassFaces);

            if (fourPassEyes.length >= 2 &&
                fourPassEyes[0] != null &&
                fourPassEyes[1] != null) {
              fourPassScore =
                  calculateStabScore(fourPassEyes, goalLeftEye, goalRightEye);
              if (fourPassScore < bestScore) {
                usedFourPass = true;
                bestBytes = fourPassBytes;
                bestScore = fourPassScore;
                bestTX = fourPassTX;
                bestTY = fourPassTY;
              }
            }
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
          rawPhotoPath, stabilizedPhotoPath, toDelete);
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
  /// This is the new algorithm that adjusts all affine transformation parameters.
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
  ) async {
    bool successfulStabilization = false;

    final double firstPassScore =
        calculateStabScore(eyes, goalLeftEye, goalRightEye);

    // Log initial eye positions for debugging
    final double initialEyeDeltaY = eyes[1]!.y - eyes[0]!.y;
    final double initialEyeDistance =
        sqrt(pow(eyes[1]!.x - eyes[0]!.x, 2) + pow(eyes[1]!.y - eyes[0]!.y, 2));
    LogService.instance.log(
        "Init: score=${firstPassScore.toStringAsFixed(2)}, tilt=${initialEyeDeltaY.toStringAsFixed(1)}px, dist=${initialEyeDistance.toStringAsFixed(1)}→$eyeDistanceGoal");

    final (
      double overshotLeftX,
      double overshotLeftY,
      double overshotRightX,
      double overshotRightY
    ) = _calculateOvershots(eyes, goalLeftEye, goalRightEye);

    if (!correctionIsNeeded(firstPassScore, overshotLeftX, overshotRightX,
        overshotLeftY, overshotRightY)) {
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
        initialEyeDistance
      );
    }

    final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(
        rawPhotoPath, projectId, projectOrientation);

    // Track best result across all passes
    Uint8List bestBytes = imageBytesStabilized;
    double bestScore = firstPassScore;
    double bestTX = translateX;
    double bestTY = translateY;
    double bestRotation = rotationDegrees;
    double bestScale = scaleFactor;

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

      if (currentEyes == null ||
          currentEyes.length < 2 ||
          currentEyes[0] == null ||
          currentEyes[1] == null) {
        break;
      }

      double eyeDeltaX = currentEyes[1]!.x - currentEyes[0]!.x;
      double detectedAngleDeg = atan2(eyeDeltaY, eyeDeltaX) * 180 / pi;

      if (detectedAngleDeg.abs() <= 0.1) break;

      double newRotation = bestRotation - detectedAngleDeg;
      final (double? rotTX, double? rotTY) =
          _calculateTranslateData(bestScale, newRotation, imgWidth, imgHeight);

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
      );

      if (rotPassBytes == null) break;

      final rotPassFaces = await StabUtils.getFacesFromBytes(rotPassBytes,
          filterByFaceSize: false, imageWidth: canvasWidth);

      if (rotPassFaces == null) break;

      List<Point<double>?> rotPassEyes = _filterAndCenterEyes(rotPassFaces);

      if (rotPassEyes.length < 2 ||
          rotPassEyes[0] == null ||
          rotPassEyes[1] == null) {
        break;
      }

      double newEyeDeltaY = rotPassEyes[1]!.y - rotPassEyes[0]!.y;
      rotationPassScore =
          calculateStabScore(rotPassEyes, goalLeftEye, goalRightEye);

      if (newEyeDeltaY.abs() < eyeDeltaY.abs()) {
        rotPassCount++;
        bestBytes = rotPassBytes;
        bestScore = rotationPassScore;
        bestTX = rotTX;
        bestTY = rotTY;
        bestRotation = newRotation;
        currentEyes = rotPassEyes;
        eyeDeltaY = newEyeDeltaY;
      } else {
        break;
      }
    }

    if (rotPassCount > 0) {
      LogService.instance.log(
          "Rot: |${rotStartEyeDeltaY.toStringAsFixed(1)}|→|${eyeDeltaY.toStringAsFixed(1)}|px ($rotPassCount pass${rotPassCount > 1 ? 'es' : ''})");
    }

    // === SCALE REFINEMENT PASSES ===
    const int maxScalePasses = 3;
    double currentEyeDistance = (currentEyes != null &&
            currentEyes.length >= 2 &&
            currentEyes[0] != null &&
            currentEyes[1] != null)
        ? sqrt(pow(currentEyes[1]!.x - currentEyes[0]!.x, 2) +
            pow(currentEyes[1]!.y - currentEyes[0]!.y, 2))
        : eyeDistanceGoal;
    double scaleError = (currentEyeDistance - eyeDistanceGoal).abs();
    final double initialScaleError = scaleError;
    int scalePassCount = 0;

    for (int scalePass = 1; scalePass <= maxScalePasses; scalePass++) {
      token?.throwIfCancelled();

      if (currentEyes == null ||
          currentEyes.length < 2 ||
          currentEyes[0] == null ||
          currentEyes[1] == null) {
        break;
      }

      if (scaleError <= 1.0) break;

      double scaleCorrection = eyeDistanceGoal / currentEyeDistance;
      double newScale = bestScale * scaleCorrection;

      final (double? scaleTX, double? scaleTY) =
          _calculateTranslateData(newScale, bestRotation, imgWidth, imgHeight);

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
      );

      if (scalePassBytes == null) break;

      final scalePassFaces = await StabUtils.getFacesFromBytes(scalePassBytes,
          filterByFaceSize: false, imageWidth: canvasWidth);

      if (scalePassFaces == null) break;

      List<Point<double>?> scalePassEyes = _filterAndCenterEyes(scalePassFaces);

      if (scalePassEyes.length < 2 ||
          scalePassEyes[0] == null ||
          scalePassEyes[1] == null) {
        break;
      }

      double newEyeDistance = sqrt(
          pow(scalePassEyes[1]!.x - scalePassEyes[0]!.x, 2) +
              pow(scalePassEyes[1]!.y - scalePassEyes[0]!.y, 2));
      double newScaleError = (newEyeDistance - eyeDistanceGoal).abs();
      scalePassScore =
          calculateStabScore(scalePassEyes, goalLeftEye, goalRightEye);

      if (newScaleError < scaleError) {
        scalePassCount++;
        bestBytes = scalePassBytes;
        bestScore = scalePassScore;
        bestTX = scaleTX;
        bestTY = scaleTY;
        bestScale = newScale;
        currentEyes = scalePassEyes;
        currentEyeDistance = newEyeDistance;
        scaleError = newScaleError;
      } else {
        break;
      }
    }

    if (scalePassCount > 0) {
      LogService.instance.log(
          "Scale: ${initialScaleError.toStringAsFixed(1)}→${scaleError.toStringAsFixed(1)}px ($scalePassCount pass${scalePassCount > 1 ? 'es' : ''})");
    }

    // === TRANSLATION REFINEMENT PASSES ===
    // Up to 3 iterative passes to fix eye position
    token?.throwIfCancelled();

    if (currentEyes == null ||
        currentEyes.length < 2 ||
        currentEyes[0] == null ||
        currentEyes[1] == null) {
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
        null
      );
    }

    var (double ovLX, double ovLY, double ovRX, double ovRY) =
        _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);

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
          currentTX, currentTY, ovLX, ovRX, ovLY, ovRY);

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
      );

      if (transPassBytes == null) break;

      final transPassFaces = await StabUtils.getFacesFromBytes(transPassBytes,
          filterByFaceSize: false, imageWidth: canvasWidth);

      if (transPassFaces == null) break;

      List<Point<double>?> transPassEyes = _filterAndCenterEyes(transPassFaces);

      if (transPassEyes.length < 2 ||
          transPassEyes[0] == null ||
          transPassEyes[1] == null) {
        break;
      }

      double passScore =
          calculateStabScore(transPassEyes, goalLeftEye, goalRightEye);

      double improvement = bestScore - passScore;

      if (passScore < bestScore) {
        transPassCount++;
        bestBytes = transPassBytes;
        bestScore = passScore;
        bestTX = transTX;
        bestTY = transTY;
        currentEyes = transPassEyes;
        currentTX = transTX;
        currentTY = transTY;
        translationPassScore = passScore;

        // Update overshots for next pass
        (ovLX, ovLY, ovRX, ovRY) =
            _calculateOvershots(currentEyes, goalLeftEye, goalRightEye);

        // Check convergence
        if (improvement > 0 && improvement < convergenceThreshold) break;
      } else {
        // Even if rejected, update translations for next attempt
        // This allows the algorithm to "push through" local minima
        currentTX = transTX;
        currentTY = transTY;
        (ovLX, ovLY, ovRX, ovRY) =
            _calculateOvershots(transPassEyes, goalLeftEye, goalRightEye);
      }
    }

    if (transPassCount > 0) {
      LogService.instance.log(
          "Trans: ${initialTransScore.toStringAsFixed(2)}→${bestScore.toStringAsFixed(2)} ($transPassCount pass${transPassCount > 1 ? 'es' : ''})");
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
      cleanupEyeDistance = sqrt(pow(cleanupRightEye.x - cleanupLeftEye.x, 2) +
          pow(cleanupRightEye.y - cleanupLeftEye.y, 2));
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

      if (cleanupScaleError > 2.0) {
        double scaleCorrection = eyeDistanceGoal / cleanupEyeDistance;
        cleanupScale = bestScale * scaleCorrection;
      }

      // Apply cleanup transform
      final (double? cleanupTX, double? cleanupTY) = _calculateTranslateData(
          cleanupScale, cleanupRotation, imgWidth, imgHeight);

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
        );

        if (cleanupBytes != null) {
          final cleanupFaces = await StabUtils.getFacesFromBytes(cleanupBytes,
              filterByFaceSize: false, imageWidth: canvasWidth);

          if (cleanupFaces != null) {
            List<Point<double>?> cleanupEyes =
                _filterAndCenterEyes(cleanupFaces);

            if (cleanupEyes.length >= 2 &&
                cleanupEyes[0] != null &&
                cleanupEyes[1] != null) {
              double cleanupScore =
                  calculateStabScore(cleanupEyes, goalLeftEye, goalRightEye);

              if (cleanupScore < bestScore) {
                LogService.instance.log(
                    "Cleanup: ${bestScore.toStringAsFixed(2)}→${cleanupScore.toStringAsFixed(2)}");
                bestBytes = cleanupBytes;
                bestScore = cleanupScore;
                bestTX = cleanupTX;
                bestTY = cleanupTY;
                bestRotation = cleanupRotation;
                bestScale = cleanupScale;
                currentEyes = cleanupEyes;
              }
            }
          }
        }
      }
    }

    // Log final eye positions for comparison and capture for benchmarking
    double? finalEyeDeltaY;
    double? finalEyeDistance;
    final finalFaces = await StabUtils.getFacesFromBytes(bestBytes,
        filterByFaceSize: false, imageWidth: canvasWidth);
    if (finalFaces != null) {
      final finalEyes = _filterAndCenterEyes(finalFaces);
      if (finalEyes.length >= 2 &&
          finalEyes[0] != null &&
          finalEyes[1] != null) {
        finalEyeDeltaY = finalEyes[1]!.y - finalEyes[0]!.y;
        finalEyeDistance = sqrt(pow(finalEyes[1]!.x - finalEyes[0]!.x, 2) +
            pow(finalEyes[1]!.y - finalEyes[0]!.y, 2));
        LogService.instance.log(
            "Final: score=${bestScore.toStringAsFixed(2)}, tilt=${finalEyeDeltaY.toStringAsFixed(1)}px, dist=${finalEyeDistance.toStringAsFixed(1)}px");
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
        rotationDegrees: bestRotation,
        scaleFactor: bestScale,
      );
    } else {
      LogService.instance.log("STAB FAILURE. STAB SCORE: $bestScore");
      await StabUtils.writeImagesBytesToJpgFile(bestBytes, stabilizedPhotoPath);
      await _handleStabilizationFailure(
          rawPhotoPath, stabilizedPhotoPath, toDelete);
      successfulStabilization = false;
    }

    // Return scores for comparison (reusing existing return structure)
    // rotationPassScore -> twoPassScore slot
    // scalePassScore -> threePassScore slot
    // translationPassScore -> fourPassScore slot
    // Also return final benchmark metrics
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
    final Uint8List blackBackgroundBytes =
        await StabUtils.compositeBlackPngBytes(imageBytes);

    final String result = await saveBytesToPngFileInIsolate(
      blackBackgroundBytes,
      stabilizedPhotoPath.replaceAll('.jpg', '.png'),
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
          "Stored face data: count=$_currentFaceCount, hasEmbedding=${embeddingBytes != null}");
    }

    LogService.instance
        .log("SUCCESS! STAB SCORE: $score (closer to 0 is better)");
    LogService.instance.log(
        "FINAL TRANSFORM -> translateX: $tx, translateY: $ty, rotationDegrees: $rot, scaleFactor: $sc");

    return true;
  }

  Future<void> _handleStabilizationFailure(String rawPhotoPath,
      String stabilizedJpgPhotoPath, List<String> toDelete) async {
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
    await DB.instance.setPhotoStabFailed(timestamp);
    unawaited(_emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.stabFailed));

    final String failureDir = await DirUtils.getFailureDirPath(projectId);
    final String failureImgPath =
        path.join(failureDir, path.basename(stabilizedJpgPhotoPath));
    await DirUtils.createDirectoryIfNotExists(failureImgPath);
    await copyFile(stabilizedJpgPhotoPath, failureImgPath);

    final String stabilizedPngPath =
        stabilizedJpgPhotoPath.replaceAll(".jpg", ".png");
    toDelete.add(stabilizedPngPath);
  }

  Future<String> _convertHeicToJpgIfNeeded(String rawPhotoPath) async {
    if (path.extension(rawPhotoPath).toLowerCase() == ".heic") {
      if (heicToJpgMap.containsKey(rawPhotoPath)) {
        return heicToJpgMap[rawPhotoPath]!;
      } else {
        final String basename =
            path.basename(rawPhotoPath.replaceAll(".heic", ".jpg"));
        final String tempDir = await DirUtils.getTemporaryDirPath();
        final String tempJpgPath = path.join(tempDir, basename);

        if (Platform.isWindows) {
          final success =
              await HeicUtils.convertHeicToJpgAt(rawPhotoPath, tempJpgPath);
          if (!success) return rawPhotoPath;
        } else {
          await HeifConverter.convert(rawPhotoPath,
              output: tempJpgPath, format: 'jpeg');
        }
        heicToJpgMap[rawPhotoPath] = tempJpgPath;
        return tempJpgPath;
      }
    }
    return rawPhotoPath;
  }

  Future<bool> tryRotation(
      String rawPhotoPath,
      void Function() userRanOutOfSpaceCallback,
      CancellationToken? token) async {
    LogService.instance.log(
        "Tried mirroring, but faces were still not found. Trying rotation.");
    final String timestamp = path.basenameWithoutExtension(
        rawPhotoPath.replaceAll("_flipped_flipped", ""));
    rawPhotoPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp, projectId);
    rawPhotoPath = await _convertHeicToJpgIfNeeded(rawPhotoPath);

    token?.throwIfCancelled();
    final File rotatedCounterClockwiseImage =
        await StabUtils.rotateImageCounterClockwise(rawPhotoPath);
    final result1 = await stabilize(
        rotatedCounterClockwiseImage.path, token, userRanOutOfSpaceCallback);
    if (result1.success) return true;
    if (result1.cancelled) return false;

    token?.throwIfCancelled();
    final File rotatedClockwiseImage =
        await StabUtils.rotateImageClockwise(rawPhotoPath);
    final result2 = await stabilize(
        rotatedClockwiseImage.path, token, userRanOutOfSpaceCallback);
    if (result2.success) return true;
    if (result2.cancelled) return false;

    await DB.instance.setPhotoNoFacesFound(timestamp);
    unawaited(
        _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound));
    return false;
  }

  Future<void> createStabThumbnail(String stabilizedPhotoPath) async {
    final String stabThumbnailPath = getStabThumbnailPath(stabilizedPhotoPath);
    final String timestamp = path.basenameWithoutExtension(stabilizedPhotoPath);
    try {
      await DirUtils.createDirectoryIfNotExists(stabThumbnailPath);
      final bytes = await CameraUtils.readBytesInIsolate(stabilizedPhotoPath);
      if (bytes == null) {
        LogService.instance
            .log("createStabThumbnail: bytes null for $stabilizedPhotoPath");
        // Still emit success - widget will fall back to full image
        ThumbnailService.instance.emit(ThumbnailEvent(
          thumbnailPath: stabThumbnailPath,
          status: ThumbnailStatus.success,
          projectId: projectId,
          timestamp: timestamp,
        ));
        return;
      }
      final thumbnailBytes = await StabUtils.thumbnailJpgFromPngBytes(bytes);
      await File(stabThumbnailPath).writeAsBytes(thumbnailBytes);

      ThumbnailService.instance.emit(ThumbnailEvent(
        thumbnailPath: stabThumbnailPath,
        status: ThumbnailStatus.success,
        projectId: projectId,
        timestamp: timestamp,
      ));
    } catch (e) {
      LogService.instance.log("createStabThumbnail error (non-fatal): $e");
      // Still emit success so widget doesn't stay stuck - it will fall back to full image
      ThumbnailService.instance.emit(ThumbnailEvent(
        thumbnailPath: stabThumbnailPath,
        status: ThumbnailStatus.success,
        projectId: projectId,
        timestamp: timestamp,
      ));
    }
  }

  Future<void> _emitThumbnailFailure(
      String rawPhotoPath, ThumbnailStatus status) async {
    final String timestamp = path
        .basenameWithoutExtension(rawPhotoPath)
        .replaceAll('_flipped', '')
        .replaceAll('_rotated_counter_clockwise', '')
        .replaceAll('_rotated_clockwise', '');
    final String stabilizedPath = await StabUtils.getStabilizedImagePath(
        rawPhotoPath, projectId, projectOrientation);
    final String thumbnailPath =
        getStabThumbnailPath(stabilizedPath.replaceAll('.jpg', '.png'));

    ThumbnailService.instance.emit(ThumbnailEvent(
      thumbnailPath: thumbnailPath,
      status: status,
      projectId: projectId,
      timestamp: timestamp,
    ));
  }

  Future<(double?, double?)> _calculateRotationAndScale(
      String rawPhotoPath,
      int imgWidth,
      int imgHeight,
      Rect? targetBoundingBox,
      userRanOutOfSpaceCallback) async {
    try {
      if (projectType == "face") {
        return await _calculateRotationAngleAndScaleFace(rawPhotoPath, imgWidth,
            imgHeight, targetBoundingBox, userRanOutOfSpaceCallback);
      } else if (projectType == "pregnancy") {
        return await _calculateRotationAngleAndScalePregnancy(rawPhotoPath);
      } else if (projectType == "musc") {
        return await _calculateRotationAngleAndScaleMusc(rawPhotoPath);
      } else {
        return (null, null);
      }
    } catch (e) {
      LogService.instance.log("Error caught: $e");
      return (null, null);
    }
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleFace(
      String rawPhotoPath,
      int imgWidth,
      int imgHeight,
      Rect? targetBoundingBox,
      userRanOutOfSpaceCallback) async {
    List<Point<double>?> eyes;

    // Reset face tracking for this photo
    _currentFaceCount = null;
    _currentEmbedding = null;

    final bool noFaceSizeFilter = targetBoundingBox != null;
    final faces = await getFacesFromRawPhotoPath(
      rawPhotoPath,
      imgWidth,
      filterByFaceSize: !noFaceSizeFilter,
    );
    if (faces == null || faces.isEmpty) {
      LogService.instance.log("No faces found. Attempting to flip...");
      await flipAndTryAgain(rawPhotoPath, userRanOutOfSpaceCallback);
      return (null, null);
    }

    // Track face count for embedding storage
    _currentFaceCount = faces.length;

    // For single-face photos, extract embedding for future reference
    if (faces.length == 1) {
      await _extractAndStoreEmbedding(rawPhotoPath);
    }

    List<dynamic> facesToUse = faces;
    if (targetBoundingBox != null) {
      final idx = _pickFaceIndexByBox(faces, targetBoundingBox);
      if (idx != -1) {
        facesToUse = [faces[idx]];
      }
    }

    eyes = getEyesFromFaces(facesToUse);

    if (facesToUse.length > 1) {
      // Multiple faces detected - try embedding-based selection first
      final int? embeddingPickedIdx = await _tryPickFaceByEmbedding(
        rawPhotoPath,
        facesToUse.length,
      );

      if (embeddingPickedIdx != null && embeddingPickedIdx >= 0) {
        // Embedding match found - use that face
        LogService.instance
            .log("Using embedding-matched face at index $embeddingPickedIdx");
        final int li = 2 * embeddingPickedIdx;
        final int ri = li + 1;
        if (ri < eyes.length && eyes[li] != null && eyes[ri] != null) {
          eyes = [eyes[li]!, eyes[ri]!];
        } else {
          // Fallback to centermost if eyes extraction failed for matched face
          eyes = getCentermostEyes(eyes, facesToUse, imgWidth, imgHeight);
        }
      } else {
        // No embedding reference found - fallback to centermost
        LogService.instance
            .log("No embedding reference found, using centermost face");
        eyes = getCentermostEyes(eyes, facesToUse, imgWidth, imgHeight);
      }
    }

    if (eyes.length < 2 || eyes[0] == null || eyes[1] == null) {
      await DB.instance
          .setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      unawaited(
          _emitThumbnailFailure(rawPhotoPath, ThumbnailStatus.noFacesFound));
      return (null, null);
    }

    originalEyePositions = eyes;
    return _calculateEyeMetrics(eyes);
  }

  /// Tries to pick the correct face using embedding similarity.
  /// Returns the face index if a reference embedding was found and matching succeeded.
  /// Returns null if no reference embedding exists (fallback to centermost).
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
            "No single-face reference photos found for embedding matching");
        return null;
      }

      final Uint8List? embeddingBytes =
          closestSingleFace['faceEmbedding'] as Uint8List?;
      if (embeddingBytes == null) {
        return null;
      }

      final Float32List referenceEmbedding =
          StabUtils.bytesToEmbedding(embeddingBytes);
      final String refTimestamp = closestSingleFace['timestamp'] as String;
      LogService.instance.log(
          "Using reference embedding from photo $refTimestamp for face matching");

      // Read the current image bytes for embedding extraction
      final String pngPath =
          await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);
      final Uint8List imageBytes = await File(pngPath).readAsBytes();

      // Use embedding-based face selection
      final int bestIdx = await StabUtils.pickFaceIndexByEmbedding(
        referenceEmbedding,
        imageBytes,
      );

      return bestIdx;
    } catch (e) {
      LogService.instance.log("Error in embedding-based face selection: $e");
      return null;
    }
  }

  /// Extracts and stores the face embedding for a single-face photo.
  /// This embedding will be used as reference for future multi-face photos.
  Future<void> _extractAndStoreEmbedding(String rawPhotoPath) async {
    try {
      final String pngPath =
          await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);
      final Uint8List imageBytes = await File(pngPath).readAsBytes();

      final Float32List? embedding =
          await StabUtils.getFaceEmbeddingFromBytes(imageBytes);

      if (embedding != null) {
        _currentEmbedding = embedding;
        LogService.instance.log(
            "Extracted face embedding (${embedding.length} dims) for single-face photo");
      }
    } catch (e) {
      LogService.instance.log("Error extracting face embedding: $e");
    }
  }

  int _pickFaceIndexByBox(List<dynamic> faces, Rect targetBox) {
    double bestIoU = 0.0;
    int bestIdx = -1;

    for (int i = 0; i < faces.length; i++) {
      final Rect bb = faces[i].boundingBox as Rect;
      final double iou = _rectIoU(bb, targetBox);
      if (iou > bestIoU) {
        bestIoU = iou;
        bestIdx = i;
      }
    }

    if (bestIdx != -1) return bestIdx;

    double bestDist = double.infinity;
    for (int i = 0; i < faces.length; i++) {
      final Rect bb = faces[i].boundingBox as Rect;
      final dx = bb.center.dx - targetBox.center.dx;
      final dy = bb.center.dy - targetBox.center.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestDist) {
        bestDist = d2;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  double _rectIoU(Rect a, Rect b) {
    final double x1 = (a.left > b.left) ? a.left : b.left;
    final double y1 = (a.top > b.top) ? a.top : b.top;
    final double x2 = (a.right < b.right) ? a.right : b.right;
    final double y2 = (a.bottom < b.bottom) ? a.bottom : b.bottom;

    final double w = (x2 - x1);
    final double h = (y2 - y1);
    if (w <= 0 || h <= 0) return 0.0;

    final double inter = w * h;
    final double union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  Future<(double?, double?)> _calculateRotationAngleAndScalePregnancy(
      String rawPhotoPath) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath =
        await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    List<Pose>? poses;
    try {
      final InputImage inputImage = InputImage.fromFilePath(pngPath);
      poses = await _poseDetector?.processImage(inputImage);
    } catch (e) {
      LogService.instance.log("Error caught => $e");
    }
    if (poses == null || poses.isEmpty) return (null, null);

    final Pose pose = poses.first;
    final Point rightAnklePos = Point(
        pose.landmarks[PoseLandmarkType.rightAnkle]!.x,
        pose.landmarks[PoseLandmarkType.rightAnkle]!.y);
    final Point nosePos = Point(pose.landmarks[PoseLandmarkType.nose]!.x,
        pose.landmarks[PoseLandmarkType.nose]!.y);

    originalRightAnkleX = rightAnklePos.x.toDouble();
    originalRightAnkleY = rightAnklePos.y.toDouble();
    final double verticalDistance = (originalRightAnkleY - nosePos.y).abs();
    final double horizontalDistance = (originalRightAnkleX - nosePos.x).abs();
    double hypotenuse =
        sqrt(pow2(verticalDistance, 2) + pow2(horizontalDistance, 2));
    double scaleFactor = bodyDistanceGoal / hypotenuse;
    double rotationDegreesRaw =
        90 - (atan2(verticalDistance, horizontalDistance) * (180 / pi));
    double rotationGoal = 6;
    double rotationDegrees = (rotationGoal - rotationDegreesRaw);

    return (scaleFactor, rotationDegrees);
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleMusc(
      String rawPhotoPath) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath =
        await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    List<Pose>? poses;
    try {
      final InputImage inputImage = InputImage.fromFilePath(pngPath);
      poses = await _poseDetector?.processImage(inputImage);
    } catch (e) {
      LogService.instance.log("Error caught => $e");
    }
    if (poses == null || poses.isEmpty) return (null, null);

    final Pose pose = poses.first;
    final Point leftHipPos = Point(pose.landmarks[PoseLandmarkType.leftHip]!.x,
        pose.landmarks[PoseLandmarkType.leftHip]!.y);
    final Point rightHipPos = Point(
        pose.landmarks[PoseLandmarkType.rightHip]!.x,
        pose.landmarks[PoseLandmarkType.rightHip]!.y);

    originalRightHipX = rightHipPos.x.toDouble();
    originalRightHipY = rightHipPos.y.toDouble();
    final num verticalDistance = (rightHipPos.y - leftHipPos.y).abs();
    final num horizontalDistance = (rightHipPos.x - leftHipPos.x).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) *
        (180 / pi) *
        (rightHipPos.y > leftHipPos.y ? -1 : 1);
    double hypotenuse = sqrt(pow2(verticalDistance.toDouble(), 2) +
        pow2(horizontalDistance.toDouble(), 2));
    double scaleFactor = eyeDistanceGoal / hypotenuse;

    return (scaleFactor, rotationDegrees);
  }

  Future<void> flipAndTryAgain(String rawPhotoPath, userRanOutOfSpaceCallback,
      {CancellationToken? token}) async {
    final String newPath;
    if (rawPhotoPath.contains("rotated")) return;

    if (rawPhotoPath.contains("_flipped")) {
      newPath = rawPhotoPath.replaceAll("_flipped", "_flipped_flipped");
    } else {
      final File flippedImgFile =
          await StabUtils.flipImageHorizontally(rawPhotoPath);
      newPath = flippedImgFile.path;
    }

    await stabilize(newPath, token, userRanOutOfSpaceCallback);
  }

  static String getStabThumbnailPath(String stabilizedPhotoPath) {
    final String dirname = path.dirname(stabilizedPhotoPath);
    final String basenameWithoutExt =
        path.basenameWithoutExtension(stabilizedPhotoPath);
    return path.join(
        dirname, DirUtils.thumbnailDirname, "$basenameWithoutExt.jpg");
  }

  (double?, double?) _calculateTranslateData(
      double scaleFactor, double rotationDegrees, int imgWidth, int imgHeight) {
    num goalX;
    num goalY;
    if (projectType == "face") {
      goalX = leftEyeXGoal;
      goalY = bothEyesYGoal;
    } else if (projectType == "pregnancy") {
      goalX = pregRightAnkleXGoal;
      goalY = pregRightAnkleYGoal;
    } else {
      goalX = muscRightHipXGoal;
      goalY = muscRightHipYGoal;
    }
    Map<String, double> transformedPoint =
        transformPoint(scaleFactor, rotationDegrees, imgWidth, imgHeight);
    double? translateX = (goalX - transformedPoint['x']!);
    double? translateY = (goalY - transformedPoint['y']!);
    return (translateX, translateY);
  }

  static Future<String> saveBytesToPngFileInIsolate(
      Uint8List imageBytes, String saveToPath) async {
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
      Point<double> goalRightEye) {
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
      double overshotRightY) {
    final double overshotAverageX = (overshotLeftX + overshotRightX) / 2;
    final double overshotAverageY = (overshotLeftY + overshotRightY) / 2;
    final double newTranslateX = translateX - overshotAverageX.toDouble();
    final double newTranslateY = translateY - overshotAverageY.toDouble();
    return (newTranslateX, newTranslateY);
  }

  List<Point<double>?> _filterAndCenterEyes(List<dynamic> stabFaces) {
    final List<Point<double>?> allEyes = getEyesFromFaces(stabFaces);
    final List<Point<double>> validPairs = <Point<double>>[];
    final List<dynamic> validFaces = <dynamic>[];

    for (int faceIdx = 0; faceIdx < stabFaces.length; faceIdx++) {
      final int li = 2 * faceIdx;
      final int ri = li + 1;
      if (ri >= allEyes.length) break;

      final Point<double>? leftEye = allEyes[li];
      final Point<double>? rightEye = allEyes[ri];
      if (leftEye == null || rightEye == null) continue;

      if ((rightEye.x - leftEye.x).abs() > 0.75 * eyeDistanceGoal) {
        validPairs
          ..add(leftEye)
          ..add(rightEye);
        validFaces.add(stabFaces[faceIdx]);
      }
    }

    if (validFaces.length > 1 && validPairs.length > 2) {
      return getCentermostEyes(
          validPairs, validFaces, canvasWidth, canvasHeight);
    }

    return validPairs;
  }

  String _cleanUpPhotoPath(String photoPath) {
    return photoPath
        .replaceAll('_flipped', '')
        .replaceAll('_rotated_counter_clockwise', '')
        .replaceAll('_rotated_clockwise', '');
  }

  List<Point<double>> getCentermostEyes(List<Point<double>?> eyes,
      List<dynamic> faces, int imgWidth, int imgHeight) {
    double smallestDistance = double.infinity;
    List<Point<double>> centeredEyes = [];

    // All platforms now use face_detection_tflite which returns FaceLike objects
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

      final double distance =
          calculateHorizontalProximityToCenter(leftEye, imgWidth) +
              calculateHorizontalProximityToCenter(rightEye, imgWidth);

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

  double calculateHorizontalProximityToCenter(
      Point<double> point, int imageWidth) {
    final int centerX = imageWidth ~/ 2;
    final double horizontalDistance = (point.x.toDouble() - centerX).abs();
    return horizontalDistance;
  }

  Future<List<dynamic>?> getFacesFromRawPhotoPath(
      String rawPhotoPath, int width,
      {bool filterByFaceSize = true}) async {
    await _ensureReady();
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath =
        await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    return await StabUtils.getFacesFromFilepath(
      pngPath,
      filterByFaceSize: filterByFaceSize,
      imageWidth: width,
    );
  }

  List<Point<double>?> getEyesFromFaces(dynamic faces) {
    // All platforms now use face_detection_tflite which returns FaceLike objects
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
          projectId, await DB.instance.getNewestVideoByProjectId(projectId));

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp, projectId);

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
      await SettingsUtil.loadProjectOrientation(projectId.toString()),
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

  double calculateStabScore(List<Point<double>?> eyes,
      Point<double> goalLeftEye, Point<double> goalRightEye) {
    final double distanceLeftEye = calculateDistance(eyes[0]!, goalLeftEye);
    final double distanceRightEye = calculateDistance(eyes[1]!, goalRightEye);
    return ((distanceLeftEye + distanceRightEye) * 1000 / 2) / canvasHeight;
  }

  double calculateDistance(Point<double> point1, Point<double> point2) {
    return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2));
  }

  bool correctionIsNeeded(double score, double overshotLeftX,
      double overshotRightX, double overshotLeftY, double overshotRightY) {
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
      double scaleFactor, double rotationDegrees, int imgWidth, int imgHeight) {
    final double originalPointX;
    final double originalPointY;
    if (projectType == "face") {
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
    double hypotenuse =
        sqrt(pow(verticalDistance, 2) + pow(horizontalDistance, 2));
    double scaleFactor = eyeDistanceGoal / hypotenuse;

    return (scaleFactor, rotationDegrees);
  }

  double pow2(double x, double n) {
    double res = 1;
    for (int i = 0; i < n; i++) {
      res *= x;
    }
    return res;
  }
}
