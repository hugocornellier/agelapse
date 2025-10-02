import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as imglib;
import '../utils/camera_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_painter.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/video_utils.dart';
import 'database_helper.dart';

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
  FaceDetector? _faceDetector;
  PoseDetector? _poseDetector;
  late double eyeOffsetX;
  late double eyeOffsetY;

  final VoidCallback userRanOutOfSpaceCallbackIn;

  FaceStabilizer(this.projectId, this.userRanOutOfSpaceCallbackIn);

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
    String? rawProjectType = await DB.instance.getProjectTypeByProjectId(projectId);

    projectType = rawProjectType!.toLowerCase();
    projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(projectId.toString());
    aspectRatioDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);

    if (projectType == "face") {
      if (Platform.isAndroid || Platform.isIOS) {
        final FaceDetector faceDetector = FaceDetector(options: FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          performanceMode: FaceDetectorMode.accurate,
        ));
        _faceDetector = faceDetector;
      } else {
        _faceDetector = null;
      }
    } else {
      final PoseDetector poseDetector = PoseDetector(options: PoseDetectorOptions(
          mode: PoseDetectionMode.single,
          model: PoseDetectionModel.accurate
      ));
      _poseDetector = poseDetector;
    }

    final double? shortSideDouble = StabUtils.getShortSide(resolution);
    final int longSide = (aspectRatioDecimal! * shortSideDouble!).toInt();
    final int shortSide = shortSideDouble.toInt();

    canvasWidth = projectOrientation == "landscape" ? longSide : shortSide;
    canvasHeight = projectOrientation == "landscape" ? shortSide : longSide;

    await _initializeGoalsAndOffsets();
  }

  Future<void> _initializeGoalsAndOffsets() async {
    final String offsetX = await SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString());
    final String offsetY = await SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString());
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

  Future<bool> stabilize(
    String rawPhotoPath,
    bool cancelStabilization,
    void Function() userRanOutOfSpaceCallback,
    { Face? targetFace, Rect? targetBoundingBox, }
  ) async {
    try {
      await _ensureReady();

      rawPhotoPath = await _convertHeicToJpgIfNeeded(rawPhotoPath);
      if (rawPhotoPath.contains("_flipped_flipped")) {
        return await tryRotation(rawPhotoPath, userRanOutOfSpaceCallback);
      }

      double? rotationDegrees, scaleFactor, translateX, translateY;

      await StabUtils.preparePNG(rawPhotoPath);
      final String canonicalPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);
      final ui.Image? img = await StabUtils.loadImageFromFile(File(canonicalPath));
      if (img == null) return false;

      (scaleFactor, rotationDegrees) = await _calculateRotationAndScale(
          rawPhotoPath,
          img,
          targetFace,
          targetBoundingBox,
          userRanOutOfSpaceCallback
      );
      if (rotationDegrees == null || scaleFactor == null || cancelStabilization) return false;

      (translateX, translateY) = _calculateTranslateData(scaleFactor, rotationDegrees, img);
      if (translateX == null || translateY == null || cancelStabilization) return false;

      if (projectType == "musc") translateY = 0;

      final Uint8List? imageBytesStabilized = await generateStabilizedImageBytes(img, rotationDegrees, scaleFactor, translateX, translateY);
      if (imageBytesStabilized == null) return false;

      String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, projectId, projectOrientation);
      stabilizedPhotoPath = _cleanUpPhotoPath(stabilizedPhotoPath);
      rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

      await StabUtils.writeImagesBytesToJpgFile(imageBytesStabilized, stabilizedPhotoPath);
      final bool result = await _finalizeStabilization(rawPhotoPath, stabilizedPhotoPath, img, translateX, translateY, rotationDegrees, scaleFactor, imageBytesStabilized);

      print("Result => '${result}'");

      if (result) await createStabThumbnail(stabilizedPhotoPath.replaceAll('.jpg', '.png'));

      img.dispose();
      return result;
    } catch (e) {
      print("Caught error: $e");
      return false;
    }
  }

  Future<bool> _finalizeStabilization(String rawPhotoPath, String stabilizedJpgPhotoPath, ui.Image? img, double translateX, double translateY, double rotationDegrees, double scaleFactor, Uint8List imageBytesStabilized) async {
    if (projectType != "face") {
      return await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        0.0,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
    }

    rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

    if (Platform.isMacOS) {
      final Point<double> goalLeftEye  = Point(leftEyeXGoal,  bothEyesYGoal);
      final Point<double> goalRightEye = Point(rightEyeXGoal, bothEyesYGoal);

      final stabFaces = await StabUtils.getFacesFromFilepath(
        stabilizedJpgPhotoPath,
        null,
        filterByFaceSize: false,
        imageWidth: canvasWidth,
      );

      if (stabFaces != null && stabFaces.isNotEmpty) {
        final eyes = _filterAndCenterEyes(stabFaces);
        if (eyes.length >= 2 && eyes[0] != null && eyes[1] != null) {
          final toDelete = [
            await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath),
            stabilizedJpgPhotoPath,
          ];
          final ok = await _performTwoPassFixIfNeeded(
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
            img,
          );
          await DirUtils.tryDeleteFiles(toDelete);
          return ok;
        }
      }

      final eyesXY = _estimatedEyesAfterTransform(
        img!, scaleFactor, rotationDegrees,
        translateX: translateX, translateY: translateY,
      );
      final score = calculateStabScore(eyesXY, goalLeftEye, goalRightEye);
      return await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        score,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
    }

    final stabFaces = await StabUtils.getFacesFromFilepath(
      stabilizedJpgPhotoPath,
      _faceDetector,
      filterByFaceSize: false,
      imageWidth: canvasWidth,
    );
    if (stabFaces == null) {
      return false;
    }

    if (stabFaces.isEmpty) {
      await DB.instance.setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      return false;
    }

    List<Point<double>?> eyes = _filterAndCenterEyes(stabFaces);

    if (eyes.length < 2 || eyes[0] == null || eyes[1] == null) {
      await DB.instance.setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      return false;
    }

    final Point<double> goalLeftEye = Point(leftEyeXGoal, bothEyesYGoal);
    final Point<double> goalRightEye = Point(rightEyeXGoal, bothEyesYGoal);

    print("EYE POS GOALS: $goalLeftEye $goalRightEye");
    print("POST-STAB POS: ${eyes[0]} ${eyes[1]}");

    List<String> toDelete = [await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath), stabilizedJpgPhotoPath];

    bool successfulStabilization = await _performTwoPassFixIfNeeded(stabFaces, eyes, goalLeftEye, goalRightEye, translateX, translateY, rotationDegrees, scaleFactor, imageBytesStabilized, rawPhotoPath, stabilizedJpgPhotoPath, toDelete, img);

    await DirUtils.tryDeleteFiles(toDelete);
    return successfulStabilization;
  }

  List<Point<double>> _estimatedEyesAfterTransform(
      ui.Image img,
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
      originalWidth: img.width.toDouble(),
      originalHeight: img.height.toDouble(),
    );
    final b = transformPointByCanvasSize(
      originalPointX: right0.x.toDouble(),
      originalPointY: right0.y.toDouble(),
      scale: scale,
      rotationDegrees: rotationDegrees,
      canvasWidth: canvasWidth.toDouble(),
      canvasHeight: canvasHeight.toDouble(),
      originalWidth: img.width.toDouble(),
      originalHeight: img.height.toDouble(),
    );

    final ax = (a['x']! + translateX);
    final ay = (a['y']! + translateY);
    final bx = (b['x']! + translateX);
    final by = (b['y']! + translateY);

    return [Point(ax, ay), Point(bx, by)];
  }

  Future<bool> _performTwoPassFixIfNeeded(
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
    ui.Image? img
  ) async {
    bool successfulStabilization = false;

    final double score = calculateStabScore(eyes, goalLeftEye, goalRightEye);
    final (double overshotLeftX, double overshotLeftY, double overshotRightX, double overshotRightY)
    = _calculateOvershots(eyes, goalLeftEye, goalRightEye);

    if (!correctionIsNeeded(score, overshotLeftX, overshotRightX, overshotLeftY, overshotRightY)) {
      successfulStabilization = await saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedJpgPhotoPath,
        score,
        translateX: translateX,
        translateY: translateY,
        rotationDegrees: rotationDegrees,
        scaleFactor: scaleFactor,
      );
    } else {
      print("Attempting to correct with two-pass. Initial score = $score...");

      final (double newTranslateX, double newTranslateY) = _calculateNewTranslations(
        translateX,
        translateY,
        overshotLeftX,
        overshotRightX,
        overshotLeftY,
        overshotRightY,
      );

      final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, projectId, projectOrientation);
      Uint8List? newImageBytesStabilized = await generateStabilizedImageBytes(
        img,
        rotationDegrees,
        scaleFactor,
        newTranslateX,
        newTranslateY,
      );
      if (newImageBytesStabilized == null) return false;

      await StabUtils.writeImagesBytesToJpgFile(newImageBytesStabilized, stabilizedPhotoPath);

      final newStabFaces = await StabUtils.getFacesFromFilepath(
        stabilizedPhotoPath,
        _faceDetector,
        filterByFaceSize: false,
        imageWidth: canvasWidth,
      );
      if (newStabFaces == null) return false;

      final List<Point<double>?> newEyes = _filterAndCenterEyes(newStabFaces);

      double newScore;
      bool usedTwoPass = true;

      if (newEyes.length < 2 || newEyes[0] == null || newEyes[1] == null) {
        newImageBytesStabilized = imageBytesStabilized;
        newScore = score;
        usedTwoPass = false;
      } else {
        newScore = calculateStabScore(newEyes, goalLeftEye, goalRightEye);
        if (score - newScore <= 0) {
          newImageBytesStabilized = imageBytesStabilized;
          newScore = score;
          usedTwoPass = false;
        }
      }

      if (newScore < 20) {
        final double finalTX = usedTwoPass ? newTranslateX : translateX;
        final double finalTY = usedTwoPass ? newTranslateY : translateY;

        successfulStabilization = await saveStabilizedImage(
          newImageBytesStabilized,
          rawPhotoPath,
          stabilizedPhotoPath,
          newScore,
          translateX: finalTX,
          translateY: finalTY,
          rotationDegrees: rotationDegrees,
          scaleFactor: scaleFactor,
        );
      } else {
        print("STAB FAILURE. STAB SCORE: $newScore");
        await _handleStabilizationFailure(rawPhotoPath, stabilizedJpgPhotoPath, toDelete);
        successfulStabilization = false;
      }
    }

    return successfulStabilization;
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
    final imglib.Image? rawImage = await compute(imglib.decodeImage, imageBytes);

    final imglib.Image blackBackground = imglib.Image(
      width: rawImage!.width,
      height: rawImage.height,
    );
    imglib.fill(blackBackground, color: imglib.ColorRgb8(0, 0, 0));
    imglib.compositeImage(blackBackground, rawImage);
    final Uint8List blackBackgroundBytes = imglib.encodePng(blackBackground);

    final String result = await saveBytesToPngFileInIsolate(
      blackBackgroundBytes,
      stabilizedPhotoPath.replaceAll('.jpg', '.png'),
    );

    if (result != "success") {
      if (result == "NoSpaceLeftError") {
        print("User is out of space...");
        userRanOutOfSpaceCallbackIn();
      }
      return false;
    }

    final tx = translateX ?? 0;
    final ty = translateY ?? 0;
    final rot = rotationDegrees ?? 0;
    final sc  = scaleFactor ?? 1;

    await setPhotoStabilized(
      rawPhotoPath,
      translateX: tx,
      translateY: ty,
      rotationDegrees: rot,
      scaleFactor: sc,
    );

    print("SUCCESS! STAB SCORE: $score (closer to 0 is better)");
    print("FINAL TRANSFORM -> translateX: $tx, translateY: $ty, rotationDegrees: $rot, scaleFactor: $sc");

    return true;
  }

  Future<void> _handleStabilizationFailure(String rawPhotoPath, String stabilizedJpgPhotoPath, List<String> toDelete) async {
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
    await DB.instance.setPhotoStabFailed(timestamp);

    final String failureDir = await DirUtils.getFailureDirPath(projectId);
    final String failureImgPath = path.join(failureDir, path.basename(stabilizedJpgPhotoPath));
    await DirUtils.createDirectoryIfNotExists(failureImgPath);
    await copyFile(stabilizedJpgPhotoPath, failureImgPath);

    final String stabilizedPngPath = stabilizedJpgPhotoPath.replaceAll(".jpg", ".png");
    toDelete.add(stabilizedPngPath);
  }

  Future<String> _convertHeicToJpgIfNeeded(String rawPhotoPath) async {
    if (path.extension(rawPhotoPath).toLowerCase() == ".heic") {
      if (heicToJpgMap.containsKey(rawPhotoPath)) {
        return heicToJpgMap[rawPhotoPath]!;
      } else {
        final String basename = path.basename(rawPhotoPath.replaceAll(".heic", ".jpg"));
        final String tempDir = await DirUtils.getTemporaryDirPath();
        final String tempJpgPath = path.join(tempDir, basename);

        await HeifConverter.convert(rawPhotoPath, output: tempJpgPath, format: 'jpeg');
        heicToJpgMap[rawPhotoPath] = tempJpgPath;
        return tempJpgPath;
      }
    }
    return rawPhotoPath;
  }

  Future<bool> tryRotation(String rawPhotoPath, void Function() userRanOutOfSpaceCallback) async {
    print("Tried mirroring, but faces were still not found. Trying rotation.");
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath.replaceAll("_flipped_flipped", ""));
    rawPhotoPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);
    rawPhotoPath = await _convertHeicToJpgIfNeeded(rawPhotoPath);

    final File rotatedCounterClockwiseImage = await StabUtils.rotateImageCounterClockwise(rawPhotoPath);
    if (await stabilize(rotatedCounterClockwiseImage.path, false, userRanOutOfSpaceCallback)) return true;

    final File rotatedClockwiseImage = await StabUtils.rotateImageClockwise(rawPhotoPath);
    if (await stabilize(rotatedClockwiseImage.path, false, userRanOutOfSpaceCallback)) return true;

    await DB.instance.setPhotoNoFacesFound(timestamp);
    return false;
  }

  Future<void> createStabThumbnail(String stabilizedPhotoPath) async {
    final String stabThumbnailPath = getStabThumbnailPath(stabilizedPhotoPath);
    await DirUtils.createDirectoryIfNotExists(stabThumbnailPath);
    final bytes = await CameraUtils.readBytesInIsolate(stabilizedPhotoPath);
    final imglib.Image? rawImage = await compute(imglib.decodeImage, bytes!);

    // Use .jpgs to store thumbnails to save space, but we also need to
    // composite the transparency with a black background to ensure the thumbnails
    // have a dark background in gallery
    final imglib.Image blackBackground = imglib.Image(
      width: rawImage!.width,
      height: rawImage.height,
      numChannels: 4,
    );

    imglib.fill(blackBackground, color: imglib.ColorRgb8(0, 0, 0));
    imglib.compositeImage(blackBackground, rawImage);

    final imglib.Image thumbnail = imglib.copyResize(blackBackground, width: 500);
    final thumbnailBytes = imglib.encodeJpg(thumbnail);

    await File(stabThumbnailPath).writeAsBytes(thumbnailBytes);
  }

  Future<(double?, double?)> _calculateRotationAndScale(
    String rawPhotoPath,
    ui.Image? img,
    Face? targetFace,
    Rect? targetBoundingBox,
    userRanOutOfSpaceCallback
  ) async {
    try {
      if (projectType == "face") {
        return await _calculateRotationAngleAndScaleFace(
          rawPhotoPath,
          img,
          targetFace,
          targetBoundingBox,
          userRanOutOfSpaceCallback
        );
      } else if (projectType == "pregnancy") {
        return await _calculateRotationAngleAndScalePregnancy(rawPhotoPath);
      } else if (projectType == "musc") {
        return await _calculateRotationAngleAndScaleMusc(rawPhotoPath);
      } else {
        return (null, null);
      }
    } catch (e) {
      print("Error caught: $e");
      return (null, null);
    }
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleFace(
      String rawPhotoPath,
      ui.Image? img,
      Face? targetFace,
      Rect? targetBoundingBox,
      userRanOutOfSpaceCallback
      ) async {
    List<Point<double>?> eyes;

    if (targetFace != null && !Platform.isMacOS) {
      eyes = getEyesFromFaces([targetFace]);
    } else {
      final bool noFaceSizeFilter = targetBoundingBox != null;
      final faces = await getFacesFromRawPhotoPath(
        rawPhotoPath,
        img!.width,
        filterByFaceSize: !noFaceSizeFilter,
      );
      if (faces == null || faces.isEmpty) {
        print("No faces found. Attempting to flip...");
        await flipAndTryAgain(rawPhotoPath, userRanOutOfSpaceCallback);
        return (null, null);
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
        eyes = getCentermostEyes(eyes, facesToUse, img.width, img.height);
      }
    }

    if (eyes.length < 2 || eyes[0] == null || eyes[1] == null) {
      await DB.instance.setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      return (null, null);
    }

    originalEyePositions = eyes;
    return _calculateEyeMetrics(eyes);
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
    final double y1 = (a.top  > b.top ) ? a.top  : b.top;
    final double x2 = (a.right  < b.right ) ? a.right  : b.right;
    final double y2 = (a.bottom < b.bottom) ? a.bottom : b.bottom;

    final double w = (x2 - x1);
    final double h = (y2 - y1);
    if (w <= 0 || h <= 0) return 0.0;

    final double inter = w * h;
    final double union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  Future<(double?, double?)> _calculateRotationAngleAndScalePregnancy(String rawPhotoPath) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    List<Pose>? poses;
    try {
      final InputImage inputImage = InputImage.fromFilePath(pngPath);
      poses = await _poseDetector?.processImage(inputImage);
    } catch (e) {
      print("Error caught => $e");
    } finally {
      _poseDetector?.close();
    }
    if (poses!.isEmpty) return (null, null);

    final Pose pose = poses.first;
    final Point rightAnklePos = Point(pose.landmarks[PoseLandmarkType.rightAnkle]!.x, pose.landmarks[PoseLandmarkType.rightAnkle]!.y);
    final Point nosePos = Point(pose.landmarks[PoseLandmarkType.nose]!.x, pose.landmarks[PoseLandmarkType.nose]!.y);

    originalRightAnkleX = rightAnklePos.x.toDouble();
    originalRightAnkleY = rightAnklePos.y.toDouble();
    final double verticalDistance = (originalRightAnkleY - nosePos.y).abs();
    final double horizontalDistance = (originalRightAnkleX - nosePos.x).abs();
    double hypotenuse = sqrt(pow2(verticalDistance, 2) + pow2(horizontalDistance, 2));
    double scaleFactor = bodyDistanceGoal / hypotenuse;
    double rotationDegreesRaw = 90 - (atan2(verticalDistance, horizontalDistance) * (180 / pi));
    double rotationGoal = 6;
    double rotationDegrees = (rotationGoal - rotationDegreesRaw);

    return (scaleFactor, rotationDegrees);
  }

  Future<(double?, double?)> _calculateRotationAngleAndScaleMusc(String rawPhotoPath) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    List<Pose>? poses;
    try {
      final InputImage inputImage = InputImage.fromFilePath(pngPath);
      poses = await _poseDetector?.processImage(inputImage);
    } catch (e) {
      print("Error caught => $e");
    } finally {
      _poseDetector?.close();
    }
    if (poses!.isEmpty) return (null, null);

    final Pose pose = poses.first;
    final Point leftHipPos = Point(pose.landmarks[PoseLandmarkType.leftHip]!.x, pose.landmarks[PoseLandmarkType.leftHip]!.y);
    final Point rightHipPos = Point(pose.landmarks[PoseLandmarkType.rightHip]!.x, pose.landmarks[PoseLandmarkType.rightHip]!.y);

    originalRightHipX = rightHipPos.x.toDouble();
    originalRightHipY = rightHipPos.y.toDouble();
    final num verticalDistance = (rightHipPos.y - leftHipPos.y).abs();
    final num horizontalDistance = (rightHipPos.x - leftHipPos.x).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) * (180 / pi) * (rightHipPos.y > leftHipPos.y ? -1 : 1);
    double hypotenuse = sqrt(pow2(verticalDistance.toDouble(), 2) + pow2(horizontalDistance.toDouble(), 2));
    double scaleFactor = eyeDistanceGoal / hypotenuse;

    return (scaleFactor, rotationDegrees);
  }

  Future<void> flipAndTryAgain(String rawPhotoPath, userRanOutOfSpaceCallback) async {
    final String newPath;
    if (rawPhotoPath.contains("rotated")) return;

    if (rawPhotoPath.contains("_flipped")) {
      newPath = rawPhotoPath.replaceAll("_flipped", "_flipped_flipped");
    } else {
      final File flippedImgFile = await StabUtils.flipImageHorizontally(rawPhotoPath);
      newPath = flippedImgFile.path;
    }

    await stabilize(newPath, false, userRanOutOfSpaceCallback);
  }

  static String getStabThumbnailPath(String stabilizedPhotoPath) {
    final String dirname = path.dirname(stabilizedPhotoPath);
    final String basenameWithoutExt = path.basenameWithoutExtension(stabilizedPhotoPath);
    return path.join(dirname, DirUtils.thumbnailDirname, "$basenameWithoutExt.jpg");
  }

  (double?, double?) _calculateTranslateData(scaleFactor, rotationDegrees, ui.Image? img) {
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
    Map<String, double> transformedPoint = transformPoint(scaleFactor, rotationDegrees, img);
    double? translateX = (goalX - transformedPoint['x']!);
    double? translateY = (goalY - transformedPoint['y']!);
    return (translateX, translateY);
  }

  Future<Uint8List?> generateStabilizedImageBytes(ui.Image? image, double? rotation, double? scale, double? translateX, double? translateY) async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    final painter = StabilizerPainter(
      image: image,
      rotationAngle: rotation ?? 0,
      scaleFactor: scale ?? 1,
      translateX: translateX ?? 0,
      translateY: translateY ?? 0,
    );
    painter.paint(Canvas(recorder), Size(canvasWidth.toDouble(), canvasHeight.toDouble()));
    ui.Image img = await recorder.endRecording().toImage(canvasWidth, canvasHeight);
    ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  }

  static Future<String> saveBytesToPngFileInIsolate(Uint8List imageBytes, String saveToPath) async {
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
          print("No space left on device error caught => $e");
          sendPort.send("NoSpaceLeftError");
        } else {
          print("Error caught => $e");
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
    await Isolate.spawn(saveImageIsolateOperation, params);
    return await receivePort.first;
  }

  (double, double, double, double) _calculateOvershots(List<Point<double>?> eyes, Point<double> goalLeftEye, Point<double> goalRightEye) {
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
    double overshotRightY
  ) {
    final double overshotAverageX = (overshotLeftX + overshotRightX) / 2;
    final double overshotAverageY = (overshotLeftY + overshotRightY) / 2;
    final double newTranslateX = translateX - overshotAverageX.toDouble();
    final double newTranslateY = translateY - overshotAverageY.toDouble();
    return (newTranslateX, newTranslateY);
  }

  List<Point<double>?> _filterAndCenterEyes(List<dynamic> stabFaces) {
    final List<Point<double>?> allEyes = getEyesFromFaces(stabFaces);
    final List<Point<double>> validPairs = <Point<double>>[];
    final List<dynamic>   validFaces = <dynamic>[];

    for (int faceIdx = 0; faceIdx < stabFaces.length; faceIdx++) {
      final int li = 2 * faceIdx;
      final int ri = li + 1;
      if (ri >= allEyes.length) break;

      final Point<double>? leftEye  = allEyes[li];
      final Point<double>? rightEye = allEyes[ri];
      if (leftEye == null || rightEye == null) continue;

      if ((rightEye.x - leftEye.x).abs() > 0.75 * eyeDistanceGoal) {
        validPairs..add(leftEye)..add(rightEye);
        validFaces.add(stabFaces[faceIdx]);
      }
    }

    if (validFaces.length > 1 && validPairs.length > 2) {
      return getCentermostEyes(validPairs, validFaces, canvasWidth, canvasHeight);
    }

    return validPairs;
  }

  String _cleanUpPhotoPath(String photoPath) {
    return photoPath
        .replaceAll('_flipped', '')
        .replaceAll('_rotated_counter_clockwise', '')
        .replaceAll('_rotated_clockwise', '');
  }

  List<Point<double>> getCentermostEyes(List<Point<double>?> eyes, List<dynamic> faces, int imgWidth, int imgHeight) {
    double smallestDistance = double.infinity;
    List<Point<double>> centeredEyes = [];

    if (Platform.isAndroid || Platform.isIOS) {
      final List<Face> faceList = (faces as List).cast<Face>();
      faces = faceList.where((face) {
        final bool rightEyeNotNull = face.landmarks[FaceLandmarkType.rightEye] != null;
        final bool leftEyeNotNull = face.landmarks[FaceLandmarkType.leftEye] != null;
        return leftEyeNotNull && rightEyeNotNull;
      }).toList();
    }

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

      final double distance = calculateHorizontalProximityToCenter(leftEye, imgWidth)
          + calculateHorizontalProximityToCenter(rightEye, imgWidth);

      if (distance < smallestDistance) {
        smallestDistance = distance;
        centeredEyes = [leftEye, rightEye];
      }
    }

    if (centeredEyes.isEmpty && eyes.length >= 2 && eyes[0] != null && eyes[1] != null) {
      centeredEyes = [eyes[0]!, eyes[1]!];
    }

    eyes.clear();
    eyes.addAll(centeredEyes);
    return centeredEyes;
  }

  double calculateHorizontalProximityToCenter(Point<double> point, int imageWidth) {
    final int centerX = imageWidth ~/ 2;
    final double horizontalDistance = (point.x.toDouble() - centerX).abs();
    return horizontalDistance;
  }

  Future<List<dynamic>?> getFacesFromRawPhotoPath(String rawPhotoPath, int width, {bool filterByFaceSize = true}) async {
    await _ensureReady();
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    if (Platform.isAndroid || Platform.isIOS) {
      return await StabUtils.getFacesFromFilepath(
        pngPath,
        _faceDetector,
        filterByFaceSize: filterByFaceSize,
        imageWidth: width,
      );
    } else {
      return await StabUtils.getFacesFromFilepath(
        pngPath,
        null,
        filterByFaceSize: filterByFaceSize,
        imageWidth: width,
      );
    }
  }

  List<Point<double>?> getEyesFromFaces(dynamic faces) {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final List<Point<double>?> eyes = [];
      for (final f in (faces as List)) {
        Point<double>? a = f.leftEye == null ? null : Point<double>(f.leftEye!.x.toDouble(), f.leftEye!.y.toDouble());
        Point<double>? b = f.rightEye == null ? null : Point<double>(f.rightEye!.x.toDouble(), f.rightEye!.y.toDouble());

        if (a == null || b == null) {
          final Rect bb = f.boundingBox as Rect;
          final double ey = bb.top + bb.height * 0.42;
          a = Point((bb.left + bb.width * 0.33), ey);
          b = Point((bb.left + bb.width * 0.67), ey);
        }

        if (a.x > b.x) {
          final tmp = a; a = b; b = tmp;
        }
        eyes..add(a)..add(b);
      }
      return eyes;
    } else {
      final List<Face> typed = (faces as List).cast<Face>();
      return StabUtils.extractEyePositions(typed);
    }
  }

  Future<bool> videoSettingsChanged() async =>
      await VideoUtils.videoOutputSettingsChanged(projectId, await DB.instance.getNewestVideoByProjectId(projectId));

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);

  Future<void> setPhotoStabilized(
    String rawPhotoPath, {
      double? translateX,
      double? translateY,
      double? rotationDegrees,
      double? scaleFactor,
    }
  ) async {
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

  double calculateStabScore(List<Point<double>?> eyes, Point<double> goalLeftEye, Point<double> goalRightEye) {
    final double distanceLeftEye = calculateDistance(eyes[0]!, goalLeftEye);
    final double distanceRightEye = calculateDistance(eyes[1]!, goalRightEye);
    return ((distanceLeftEye + distanceRightEye) * 1000 / 2) / canvasHeight;
  }

  double calculateDistance(Point<double> point1, Point<double> point2) {
    return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2));
  }

  bool correctionIsNeeded(double score, double overshotLeftX, double overshotRightX, double overshotLeftY, double overshotRightY) {
    if (score > 1) return true;
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
      print('Error copying file: $e');
    }
  }

  Map<String, double> transformPoint(double scaleFactor, double rotationDegrees, ui.Image? img) {
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
      originalWidth: img!.width.toDouble(),
      originalHeight: img.height.toDouble(),
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
    double rotatedX = translatedX * cos(angleRadians) - translatedY * sin(angleRadians);
    double rotatedY = translatedX * sin(angleRadians) + translatedY * cos(angleRadians);

    double finalX = rotatedX + scaledWidth / 2 + (canvasWidth - scaledWidth) / 2;
    double finalY = rotatedY + scaledHeight / 2 + (canvasHeight - scaledHeight) / 2;

    return {
      'x': finalX,
      'y': finalY
    };
  }

  (double, double) _calculateEyeMetrics(List<Point<double>?> detectedEyes) {
    final Point<double> leftEye = detectedEyes[0]!;
    final Point<double> rightEye = detectedEyes[1]!;
    final double verticalDistance = (rightEye.y - leftEye.y).abs();
    final double horizontalDistance = (rightEye.x - leftEye.x).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) * (180 / pi) * (rightEye.y > leftEye.y ? -1 : 1);
    double hypotenuse = sqrt(pow(verticalDistance, 2) + pow(horizontalDistance, 2));
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
