import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:apple_vision_face/apple_vision_face.dart';

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

class AppleVisionGateway {
  AppleVisionGateway._();
  static final AppleVisionGateway instance = AppleVisionGateway._();
  final AppleVisionFaceController _controller = AppleVisionFaceController();

  Future<List<AVFaceLike>> detectFromFile(String imagePath, int imageWidth, int imageHeight) async {
    final Uint8List bytes = await File(imagePath).readAsBytes();
    final Size size = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final results = await _controller.processImage(bytes, size);
    if (results == null || results.isEmpty) return [];

    final List<AVFaceLike> faces = [];
    for (final faceData in results) {
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

      Point<double>? leftEyeCenter;
      Point<double>? rightEyeCenter;

      for (final mark in faceData.marks) {
        if (mark.location.isEmpty) continue;

        final isLeft = mark.landmark == LandMark.leftEye;
        final isRight = mark.landmark == LandMark.rightEye;

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

      bool normalized = maxX <= 1.0 && maxY <= 1.0;
      final double sx = normalized ? imageWidth.toDouble() : 1.0;
      final double sy = normalized ? imageHeight.toDouble() : 1.0;

      final Rect bbox = Rect.fromLTRB(
        (minX.isFinite ? minX : 0) * sx,
        (minY.isFinite ? minY : 0) * sy,
        (maxX.isFinite ? maxX : 0) * sx,
        (maxY.isFinite ? maxY : 0) * sy,
      );

      final Point<double>? leftScaled = leftEyeCenter == null ? null : Point<double>(leftEyeCenter!.x * sx, leftEyeCenter!.y * sy);
      final Point<double>? rightScaled = rightEyeCenter == null ? null : Point<double>(rightEyeCenter!.x * sx, rightEyeCenter!.y * sy);

      faces.add(AVFaceLike(
        boundingBox: bbox,
        leftEye: leftScaled,
        rightEye: rightScaled,
      ));
    }

    return faces;
  }
}