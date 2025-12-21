import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter(this.faces, this.imageSize, this.rotation,
      this.cameraLensDirection, this.projectId);

  final List<Face> faces;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final int projectId;

  TextPainter createTextPainter(String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontFamily: 'Futura',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter;
  }

  TextPainter createIconPainter(IconData iconData, double size) {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: iconData.fontFamily,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return iconPainter;
  }

  void drawTranslucentBox(
      Canvas canvas, Size size, IconData iconData, String text) {
    final Paint boxPaint = Paint()
      ..color = Colors.black.withAlpha(179) // Equivalent to opacity 0.7
      ..style = PaintingStyle.fill;

    const double iconSize = 16;
    final TextPainter textPainter = createTextPainter(text);
    final TextPainter iconPainter = createIconPainter(iconData, iconSize);

    final double boxWidth = textPainter.width + iconPainter.width + 20;
    final double boxHeight = max(textPainter.height, iconPainter.height) + 10;

    final Offset boxPosition = Offset(
      (size.width - boxWidth) / 2,
      size.height - boxHeight - 60,
    );

    final RRect boxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        boxPosition.dx,
        boxPosition.dy,
        boxWidth,
        boxHeight,
      ),
      const Radius.circular(10),
    );

    canvas.drawRRect(boxRect, boxPaint);

    textPainter.paint(
      canvas,
      Offset(
        boxPosition.dx + 10,
        boxPosition.dy + (boxHeight - textPainter.height) / 2,
      ),
    );

    iconPainter.paint(
      canvas,
      Offset(
        boxPosition.dx + 10 + textPainter.width,
        boxPosition.dy + (boxHeight - iconPainter.height) / 2,
      ),
    );
  }

  bool translucentBoxActive = false;

  @override
  void paint(Canvas canvas, Size size) {
    (int? x, int? y) getLandmarkPosition(
            Face face, FaceLandmarkType landmarkType) =>
        (
          face.landmarks[landmarkType]?.position.x,
          face.landmarks[landmarkType]?.position.y
        );

    var (rightEarXPos, rightEarYPos) =
        getLandmarkPosition(faces[0], FaceLandmarkType.rightEar);
    var (rightEyeXPos, rightEyeYPos) =
        getLandmarkPosition(faces[0], FaceLandmarkType.rightEye);
    var (leftEarXPos, leftEarYPos) =
        getLandmarkPosition(faces[0], FaceLandmarkType.leftEar);
    var (leftEyeXPos, leftEyeYPos) =
        getLandmarkPosition(faces[0], FaceLandmarkType.leftEye);

    // Scale the landmark positions to match the canvas size
    double scaleX = size.width / imageSize.width;
    double scaleY = size.height / imageSize.height;

    rightEarXPos = (rightEarXPos! * scaleX).toInt();
    rightEarYPos = (rightEarYPos! * scaleY).toInt();
    rightEyeXPos = (rightEyeXPos! * scaleX).toInt();
    rightEyeYPos = (rightEyeYPos! * scaleY).toInt();
    leftEarXPos = (leftEarXPos! * scaleX).toInt();
    leftEarYPos = (leftEarYPos! * scaleY).toInt();
    leftEyeXPos = (leftEyeXPos! * scaleX).toInt();
    leftEyeYPos = (leftEyeYPos! * scaleY).toInt();

    double rightEarToEyeDistance = calculateDistance(
        rightEarXPos, rightEyeXPos, rightEarYPos, rightEyeYPos);
    double leftEarToEyeDistance =
        calculateDistance(leftEarXPos, leftEyeXPos, leftEarYPos, leftEyeYPos);

    final int verticalDistance = (rightEyeYPos - leftEyeYPos).abs();
    final int horizontalDistance = (rightEyeXPos - leftEyeXPos).abs();
    double rotationDegrees = atan2(verticalDistance, horizontalDistance) *
        (180 / pi) *
        (rightEyeYPos > leftEyeYPos ? -1 : 1);

    const double turnedHeadThreshold = 1.5;
    double ratio = leftEarToEyeDistance / rightEarToEyeDistance;
    ratio = ratio < 1 ? -1 / ratio : ratio;

    bool isLeftTurned = ratio < -turnedHeadThreshold;
    bool isRightTurned = ratio > turnedHeadThreshold;

    final double centerX = size.width / 2;
    double leftEyeToCenterDistance = (leftEyeXPos - centerX).abs();
    double rightEyeToCenterDistance = (rightEyeXPos - centerX).abs();
    double distanceDifference =
        (leftEyeToCenterDistance - rightEyeToCenterDistance).abs();
    double distanceDifferencePercentage =
        (distanceDifference / size.width) * 100;

    if (isLeftTurned && !translucentBoxActive) {
      translucentBoxActive = true;
      drawTranslucentBox(canvas, size, Icons.arrow_forward, "Turn head right ");
    } else if (isRightTurned && !translucentBoxActive) {
      translucentBoxActive = true;
      drawTranslucentBox(canvas, size, Icons.arrow_back, "Turn head left ");
    }

    final bool headOverRotated = rotationDegrees.abs() > 8;
    if (headOverRotated && !translucentBoxActive) {
      translucentBoxActive = true;
      drawTranslucentBox(canvas, size, Icons.straighten, "Straighten head ");
    }

    final bool headNotCentered = distanceDifferencePercentage > 10;
    if (headNotCentered && !translucentBoxActive) {
      translucentBoxActive = true;
      drawTranslucentBox(
          canvas, size, Icons.center_focus_strong, "Center head ");
    }

    // If no issues, don't show the warning/tips box
    if (!isLeftTurned &&
        !isRightTurned &&
        !headOverRotated &&
        !headNotCentered) {
      translucentBoxActive = false;
    }
  }

  double calculateDistance2(double x1, double x2, double y1, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  }

  double calculateDistance(int? x1, int? x2, int? y1, int? y2) {
    int deltaX = x1! - x2!;
    int deltaY = y1! - y2!;
    return sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.faces != faces;
  }
}
