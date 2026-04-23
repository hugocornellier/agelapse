import 'dart:math';

import 'package:flutter/material.dart';

class CachedFace {
  final Rect boundingBox;
  final Point<double>? leftEye;
  final Point<double>? rightEye;

  const CachedFace({
    required this.boundingBox,
    this.leftEye,
    this.rightEye,
  });
}

class FaceDetectionCacheResult {
  final String orientation;
  final List<CachedFace> faces;
  final int? selectedFaceIndex;

  const FaceDetectionCacheResult({
    required this.orientation,
    required this.faces,
    this.selectedFaceIndex,
  });

  bool get isNoFaces => orientation == 'no_faces';
}
