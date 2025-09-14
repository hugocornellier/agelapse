import 'dart:math';
import 'dart:ui';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/dir_utils.dart';

class WindowsTFLiteFaceDetector {
  static final WindowsTFLiteFaceDetector instance = WindowsTFLiteFaceDetector._();
  WindowsTFLiteFaceDetector._();

  late Interpreter _det;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _det = await Interpreter.fromAsset('models/face_detection_short_range.tflite');
    _ready = true;
  }

  Future<List<_DetFace>> detectOnPath(String rawPath, {required int imageWidth}) async {
    await init();
    await StabUtils.preparePNG(rawPath);
    final String png = await DirUtils.getPngPathFromRawPhotoPath(rawPath);
    return [];
  }
}

class _DetFace {
  final Rect boundingBox;
  final Point<int>? leftEye;
  final Point<int>? rightEye;
  _DetFace(this.boundingBox, this.leftEye, this.rightEye);
}
