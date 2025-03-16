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
  static late int canvasHeight;
  static late int canvasWidth;
  late int leftEyeXGoal;
  late int rightEyeXGoal;
  late int bothEyesYGoal;
  late int eyeDistanceGoal;
  late double bodyDistanceGoal;
  List<Point<int>?>? originalEyePositions;
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
  late FaceDetector? _faceDetector;
  late PoseDetector? _poseDetector;
  late double eyeOffsetX;
  late double eyeOffsetY;
  final VoidCallback userRanOutOfSpaceCallbackIn;

  FaceStabilizer(this.projectId, this.userRanOutOfSpaceCallbackIn) {
    init();
  }

  Future<void> init() async {
    await initializeProjectSettings();
  }

  Future<void> initializeProjectSettings() async {
    String? rawProjectType = await DB.instance.getProjectTypeByProjectId(projectId);

    projectType = rawProjectType!.toLowerCase();
    projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(projectId.toString());
    aspectRatioDecimal = getAspectRatioAsDecimal(aspectRatio);

    if (projectType == "face") {
      final FaceDetector faceDetector = FaceDetector(options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
      ));

      _faceDetector = faceDetector;
    } else {
      final PoseDetector poseDetector = PoseDetector(options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate
      ));

      _poseDetector = poseDetector;
    }

    final double? shortSideDouble = getShortSide(resolution);
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
    leftEyeXGoal = (xAxisCenter - eyeOffsetX * canvasWidth).toInt();
    rightEyeXGoal = (xAxisCenter + eyeOffsetX * canvasWidth).toInt();
    eyeDistanceGoal = rightEyeXGoal - leftEyeXGoal;
    bothEyesYGoal = (canvasHeight * eyeOffsetY).toInt();
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
    {
      Face? targetFace
    }
  ) async {
    try {
      rawPhotoPath = await _convertHeicToJpgIfNeeded(rawPhotoPath);
      if (rawPhotoPath.contains("_flipped_flipped")) {
        return await tryRotation(rawPhotoPath, userRanOutOfSpaceCallback);
      }

      double? rotationDegrees, scaleFactor, translateX, translateY;

      final ui.Image? img = await StabUtils.loadImageFromFile(File(rawPhotoPath));
      if (img == null) return false;

      (scaleFactor, rotationDegrees) = await _calculateRotationAndScale(rawPhotoPath, img, targetFace, userRanOutOfSpaceCallback);
      if (rotationDegrees == null || scaleFactor == null || cancelStabilization) return false;

      (translateX, translateY) = _calculateTranslateData(scaleFactor, rotationDegrees, img);
      if (translateX == null || translateY == null || cancelStabilization) return false;

      if (projectType == "musc") translateY = 0;

      final Uint8List? imageBytesStabilized = await _generateStabilizedImageBytes(img, rotationDegrees, scaleFactor, translateX, translateY);
      if (imageBytesStabilized == null) return false;

      String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, projectId, projectOrientation);
      stabilizedPhotoPath = _cleanUpPhotoPath(stabilizedPhotoPath);
      rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

      await StabUtils.writeImagesBytesToJpgFile(imageBytesStabilized, stabilizedPhotoPath);
      final bool result = await _finalizeStabilization(rawPhotoPath, stabilizedPhotoPath, img, translateX, translateY, rotationDegrees, scaleFactor, imageBytesStabilized);

      if (result) await _createStabThumbnail(stabilizedPhotoPath.replaceAll('.jpg', '.png'));

      img.dispose();
      return result;
    } catch (e) {
      print("Caught error: $e");
      return false;
    }
  }

  Future<bool> _finalizeStabilization(String rawPhotoPath, String stabilizedJpgPhotoPath, ui.Image? img, double translateX, double translateY, double rotationDegrees, double scaleFactor, Uint8List imageBytesStabilized) async {
    if (projectType != "face") {
      return await _saveStabilizedImage(imageBytesStabilized, rawPhotoPath, stabilizedJpgPhotoPath, 0.0);
    }

    rawPhotoPath = _cleanUpPhotoPath(rawPhotoPath);

    List<Face>? stabFaces = await StabUtils.getFacesFromFilepath(stabilizedJpgPhotoPath, _faceDetector!, imageWidth: canvasWidth);
    if (stabFaces == null) {
      return false;
    }

    if (stabFaces.isEmpty) {
      await DB.instance.setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      return false;
    }

    List<Point<int>?> eyes = _filterAndCenterEyes(stabFaces);

    if (eyes.isEmpty && stabFaces.isNotEmpty) {
      print("Here. Eyes is empty but stab Faces is not...");
      print("stabFaces length: ${stabFaces.length}. ");
    }

    final Point<int> goalLeftEye = Point(leftEyeXGoal, bothEyesYGoal);
    final Point<int> goalRightEye = Point(rightEyeXGoal, bothEyesYGoal);

    print("EYE POS GOALS: $goalLeftEye $goalRightEye");
    print("POST-STAB POS: ${eyes[0]} ${eyes[1]}");

    List<String> toDelete = [await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath), stabilizedJpgPhotoPath];

    bool successfulStabilization = await _performTwoPassFixIfNeeded(stabFaces, eyes, goalLeftEye, goalRightEye, translateX, translateY, rotationDegrees, scaleFactor, imageBytesStabilized, rawPhotoPath, stabilizedJpgPhotoPath, toDelete, img);

    await DirUtils.tryDeleteFiles(toDelete);
    return successfulStabilization;
  }

  Future<bool> _performTwoPassFixIfNeeded(
    List<Face> stabFaces,
    List<Point<int>?> eyes,
    Point<int> goalLeftEye,
    Point<int> goalRightEye,
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
    final (int overshotLeftX, int overshotLeftY, int overshotRightX, int overshotRightY)
    = _calculateOvershots(eyes, goalLeftEye, goalRightEye);

    if (!correctionIsNeeded(score, overshotLeftX, overshotRightX, overshotLeftY, overshotRightY)) {
      successfulStabilization = await _saveStabilizedImage(imageBytesStabilized, rawPhotoPath, stabilizedJpgPhotoPath, score);
    } else {
      print("Attempting to correct with two-pass. Initial score = $score...");

      final (double newTranslateX, double newTranslateY) = _calculateNewTranslations(
        translateX,
        translateY,
        overshotLeftX,
        overshotRightX,
        overshotLeftY,
        overshotRightY
      );

      String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, projectId, projectOrientation);
      Uint8List? newImageBytesStabilized = await _generateStabilizedImageBytes(img, rotationDegrees, scaleFactor, newTranslateX, newTranslateY);
      if (newImageBytesStabilized == null) return false;

      await StabUtils.writeImagesBytesToJpgFile(newImageBytesStabilized, stabilizedPhotoPath);

      List<Face>? newStabFaces = await StabUtils.getFacesFromFilepath(stabilizedJpgPhotoPath, _faceDetector!, imageWidth: canvasWidth);
      if (newStabFaces == null) return false;

      List<Point<int>?> newEyes = _filterAndCenterEyes(newStabFaces);

      double newScore = calculateStabScore(newEyes, goalLeftEye, goalRightEye);
      if (score - newScore <= 0) {
        newImageBytesStabilized = imageBytesStabilized;
        newScore = score;
      }

      if (newScore < 5) {
        successfulStabilization = await _saveStabilizedImage(newImageBytesStabilized, rawPhotoPath, stabilizedPhotoPath, newScore);
      } else {
        print("STAB FAILURE. STAB SCORE: $newScore");
        await _handleStabilizationFailure(rawPhotoPath, stabilizedJpgPhotoPath, toDelete);
        successfulStabilization = false;
      }
    }

    return successfulStabilization;
  }

  Future<bool> _saveStabilizedImage(Uint8List imageBytes, String rawPhotoPath, String stabilizedPhotoPath, double score) async {
    final String result = await saveBytesToPngFileInIsolate(
        imageBytes,
        stabilizedPhotoPath.replaceAll('.jpg', '.png')
    );

    if (result == "NoSpaceLeftError") {
      print("User is out of space...");
      userRanOutOfSpaceCallbackIn();
      return false;
    }

    await setPhotoStabilized(rawPhotoPath);

    print("SUCCESS! STAB SCORE: $score (closer to 0 is better)");
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

  Future<void> _createStabThumbnail(String stabilizedPhotoPath) async {
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

  Future<(double?, double?)> _calculateRotationAndScale(String rawPhotoPath, ui.Image? img, Face? targetFace, userRanOutOfSpaceCallback) async {
    try {
      if (projectType == "face") {
        return await _calculateRotationAngleAndScaleFace(rawPhotoPath, img, targetFace, userRanOutOfSpaceCallback);
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

  Future<(double?, double?)> _calculateRotationAngleAndScaleFace(String rawPhotoPath, ui.Image? img, Face? targetFace, userRanOutOfSpaceCallback) async {
    List<Point<int>?> eyes;
    if (targetFace != null) {
      eyes = getEyesFromFaces([targetFace]);
    } else {
      final List<Face>? faces = await getFacesFromRawPhotoPath(rawPhotoPath, img!.width);
      if (faces == null) {
        return (null, null);
      }

      if (faces.isEmpty) {
        print("No faces found. Attempting to flip...");
        await flipAndTryAgain(rawPhotoPath, userRanOutOfSpaceCallback);
        return (null, null);
      }

      eyes = getEyesFromFaces(faces);
      if (faces.length > 1) {
        eyes = getCentermostEyes(eyes, faces, img.width, img.height);
      }
    }

    if (eyes.isEmpty) {
      await DB.instance.setPhotoNoFacesFound(path.basenameWithoutExtension(rawPhotoPath));
      return (null, null);
    }

    originalEyePositions = eyes;
    return _calculateEyeMetrics(eyes);
  }

  Future<(double?, double?)> _calculateRotationAngleAndScalePregnancy(String rawPhotoPath) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);

    List<Pose>? poses;
    try {
      final InputImage inputImage = InputImage.fromFilePath(pngPath);
      poses = await _poseDetector?.processImage(inputImage);
    } catch (e) {
      print("Caught error3 $e");
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
      print("Caught error3 $e");
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

  Future<Uint8List?>? _generateStabilizedImageBytes(ui.Image? image, double? rotation, double? scale, double? translateX, double? translateY) async {
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

  (int, int, int, int) _calculateOvershots(List<Point<int>?> eyes, Point<int> goalLeftEye, Point<int> goalRightEye) {
    final int overshotLeftX = eyes[0]!.x - goalLeftEye.x;
    final int overshotLeftY = eyes[0]!.y - goalLeftEye.y;
    final int overshotRightX = eyes[1]!.x - goalRightEye.x;
    final int overshotRightY = eyes[1]!.y - goalRightEye.y;
    return (overshotLeftX, overshotLeftY, overshotRightX, overshotRightY);
  }

  (double, double) _calculateNewTranslations(double translateX, double translateY, int overshotLeftX, int overshotRightX, int overshotLeftY, int overshotRightY) {
    final double overshotAverageX = (overshotLeftX + overshotRightX) / 2;
    final double overshotAverageY = (overshotLeftY + overshotRightY) / 2;
    final double newTranslateX = translateX - overshotAverageX.toDouble();
    final double newTranslateY = translateY - overshotAverageY.toDouble();
    return (newTranslateX, newTranslateY);
  }

  List<Point<int>?> _filterAndCenterEyes(List<Face> stabFaces) {
    List<Point<int>?> eyes = getEyesFromFaces(stabFaces);

    eyes = eyes.where((point) => point != null).toList();
    if (eyes.length <= 2) {
      return eyes;
    }

    List<Point<int>?> filteredEyes = [];
    List filteredFaces = [];
    int facePos = 0;
    for (int i = 0; i < eyes.length; i += 2) {
      Point<int> leftEye = eyes[i]!;
      Point<int> rightEye = eyes[i + 1]!;
      if ((rightEye.x - leftEye.x).abs() > 0.75 * eyeDistanceGoal) {
        filteredEyes.add(leftEye);
        filteredEyes.add(rightEye);
        filteredFaces.add(stabFaces[facePos]);
        filteredFaces.add(stabFaces[facePos]);
      }
      facePos++;
    }
    if (stabFaces.length > 1 && filteredEyes.length > 2) {
      eyes = getCentermostEyes(eyes, stabFaces, canvasWidth, canvasHeight);
    } else {
      eyes = filteredEyes;
    }
    return eyes;
  }

  String _cleanUpPhotoPath(String photoPath) {
    return photoPath
        .replaceAll('_flipped', '')
        .replaceAll('_rotated_counter_clockwise', '')
        .replaceAll('_rotated_clockwise', '');
  }

  List<Point<int>> getCentermostEyes(List<Point<int>?> eyes, List<Face> faces, int imgWidth, int imgHeight) {
    double smallestDistance = double.infinity;
    List<Point<int>> centeredEyes = [];

    faces = faces.where((face) {
      final bool rightEyeNotNull = face.landmarks[FaceLandmarkType.rightEye] != null;
      final bool leftEyeNotNull = face.landmarks[FaceLandmarkType.leftEye] != null;
      return leftEyeNotNull && rightEyeNotNull;
    }).toList();

    for (var i = 0; i < faces.length; i++) {
      final bool bordersLeft = faces[i].boundingBox.left <= 1;
      final bool bordersTop = faces[i].boundingBox.top <= 1;
      final bool bordersRight = faces[i].boundingBox.right <= 1;
      final bool bordersBottom = faces[i].boundingBox.bottom <= 1;

      if (bordersLeft || bordersTop || bordersRight || bordersBottom) continue;

      Point<int>? leftEye = eyes[2 * i];
      Point<int>? rightEye = eyes[2 * i + 1];

      if (leftEye == null || rightEye == null) continue;

      final double distance = calculateHorizontalProximityToCenter(leftEye, imgWidth)
          + calculateHorizontalProximityToCenter(rightEye, imgWidth);

      if (distance < smallestDistance) {
        smallestDistance = distance;
        centeredEyes = [leftEye, rightEye];
      }
    }

    eyes.clear();
    eyes.addAll(centeredEyes);
    return centeredEyes;
  }

  double calculateHorizontalProximityToCenter(Point<int> point, int imageWidth) {
    final int centerX = imageWidth ~/ 2;
    final double horizontalDistance = (point.x.toDouble() - centerX).abs();
    return horizontalDistance;
  }

  Future<List<Face>?> getFacesFromRawPhotoPath(String rawPhotoPath, int width, {bool filterByFaceSize = true}) async {
    await StabUtils.preparePNG(rawPhotoPath);
    final String pngPath = await DirUtils.getPngPathFromRawPhotoPath(rawPhotoPath);
    return (await StabUtils.getFacesFromFilepath(pngPath, _faceDetector!, filterByFaceSize: filterByFaceSize, imageWidth: width));
  }

  static double? getAspectRatioAsDecimal(String aspectRatio) {
    if (!aspectRatio.contains(':')) return null;
    final List<String> split = aspectRatio.split(":");
    int? dividend = int.tryParse(split[0]);
    int? divisor = int.tryParse(split[1]);
    if (dividend == null || divisor == null) return null;
    return dividend / divisor;
  }

  double? getShortSide(String resolution) {
    if (resolution == "1080p") return 1080;
    if (resolution == "2K") return 1152;
    if (resolution == "3K") return 1728;
    if (resolution == "4K") return 2304;
    return null;
  }

  List<Point<int>?> getEyesFromFaces(List<Face> faces) => StabUtils.extractEyePositions(faces);

  Future<bool> videoSettingsChanged() async =>
      await VideoUtils.videoOutputSettingsChanged(projectId, await DB.instance.getNewestVideoByProjectId(projectId));

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);

  Future<void> setPhotoStabilized(String rawPhotoPath) async {
    final String timestamp = path.basenameWithoutExtension(rawPhotoPath);
    await DB.instance.setPhotoStabilized(timestamp, await SettingsUtil.loadProjectOrientation(projectId.toString()), aspectRatio, resolution, eyeOffsetX, eyeOffsetY);
  }

  double calculateStabScore(List<Point<int>?> eyes, Point<int> goalLeftEye, Point<int> goalRightEye) {
    final double distanceLeftEye = calculateDistance(eyes[0]!, goalLeftEye);
    final double distanceRightEye = calculateDistance(eyes[1]!, goalRightEye);
    return ((distanceLeftEye + distanceRightEye) * 1000 / 2) / canvasHeight;
  }

  double calculateDistance(Point<int> point1, Point<int> point2) {
    return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2));
  }

  bool correctionIsNeeded(double score, int overshotLeftX, int overshotRightX, int overshotLeftY, int overshotRightY) {
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

  (double, double) _calculateEyeMetrics(List<Point<int>?> detectedEyes) {
    final Point<int> rightEye = detectedEyes[1]!;
    final Point<int> leftEye = detectedEyes[0]!;
    final int verticalDistance = (rightEye.y - leftEye.y).abs();
    final int horizontalDistance = (rightEye.x - leftEye.x).abs();
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
