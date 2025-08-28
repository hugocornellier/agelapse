import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum FaceIndex { leftEye, rightEye, noseTip, mouth, leftEyeTragion, rightEyeTragion }
enum FaceDetectionModel { frontCamera, backCamera, shortRange, full, fullSparse }

const _modelNameBack = 'face_detection_back.tflite';
const _modelNameFront = 'face_detection_front.tflite';
const _modelNameShort = 'face_detection_short_range.tflite';
const _modelNameFull = 'face_detection_full_range.tflite';
const _modelNameFullSparse = 'face_detection_full_range_sparse.tflite';
const _faceLandmarkModel = 'face_landmark.tflite';
const _irisLandmarkModel = 'iris_landmark.tflite';

const _rawScoreLimit = 80.0;
const _minScore = 0.5;
const _minSuppressionThreshold = 0.3;

const _ssdFront = {
  'num_layers': 4,
  'input_size_height': 128,
  'input_size_width': 128,
  'anchor_offset_x': 0.5,
  'anchor_offset_y': 0.5,
  'strides': [8, 16, 16, 16],
  'interpolated_scale_aspect_ratio': 1.0,
};
const _ssdBack = {
  'num_layers': 4,
  'input_size_height': 256,
  'input_size_width': 256,
  'anchor_offset_x': 0.5,
  'anchor_offset_y': 0.5,
  'strides': [16, 32, 32, 32],
  'interpolated_scale_aspect_ratio': 1.0,
};
const _ssdShort = {
  'num_layers': 4,
  'input_size_height': 128,
  'input_size_width': 128,
  'anchor_offset_x': 0.5,
  'anchor_offset_y': 0.5,
  'strides': [8, 16, 16, 16],
  'interpolated_scale_aspect_ratio': 1.0,
};
const _ssdFull = {
  'num_layers': 1,
  'input_size_height': 192,
  'input_size_width': 192,
  'anchor_offset_x': 0.5,
  'anchor_offset_y': 0.5,
  'strides': [4],
  'interpolated_scale_aspect_ratio': 0.0,
};

class RectF {
  final double xmin, ymin, xmax, ymax;
  const RectF(this.xmin, this.ymin, this.xmax, this.ymax);
  double get w => xmax - xmin;
  double get h => ymax - ymin;
  RectF scale(double sx, double sy) => RectF(xmin * sx, ymin * sy, xmax * sx, ymax * sy);
  RectF expand(double frac) {
    final cx = (xmin + xmax) * 0.5;
    final cy = (ymin + ymax) * 0.5;
    final hw = (w * (1.0 + frac)) * 0.5;
    final hh = (h * (1.0 + frac)) * 0.5;
    return RectF(cx - hw, cy - hh, cx + hw, cy + hh);
  }
}

class Detection {
  final RectF bbox;
  final double score;
  final List<double> keypointsXY;
  Detection({required this.bbox, required this.score, required this.keypointsXY});
  double operator [](int i) => keypointsXY[i];
}

class ImageTensor {
  final Float32List tensorNHWC;
  final List<double> padding;
  final int width, height;
  ImageTensor(this.tensorNHWC, this.padding, this.width, this.height);
}

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
double _sigmoidClipped(double x, {double limit = _rawScoreLimit}) {
  final v = _clip(x, -limit, limit);
  return 1.0 / (1.0 + math.exp(-v));
}

ImageTensor _imageToTensor(img.Image src, {required int outW, required int outH}) {
  final inW = src.width, inH = src.height;
  final scale = (outW / inW < outH / inH) ? outW / inW : outH / inH;
  final newW = (inW * scale).round();
  final newH = (inH * scale).round();

  final resized = img.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );

  final dx = (outW - newW) ~/ 2;
  final dy = (outH - newH) ~/ 2;

  final canvas = img.Image(width: outW, height: outH);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final px = resized.getPixel(x, y);
      canvas.setPixel(x + dx, y + dy, px);
    }
  }

  final t = Float32List(outW * outH * 3);
  var k = 0;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final px = canvas.getPixel(x, y) as img.Pixel;
      t[k++] = (px.r / 127.5) - 1.0;
      t[k++] = (px.g / 127.5) - 1.0;
      t[k++] = (px.b / 127.5) - 1.0;
    }
  }

  final padTop = dy / outH;
  final padBottom = (outH - dy - newH) / outH;
  final padLeft = dx / outW;
  final padRight = (outW - dx - newW) / outW;

  return ImageTensor(t, [padTop, padBottom, padLeft, padRight], outW, outH);
}

List<Detection> _detectionLetterboxRemoval(List<Detection> dets, List<double> padding) {
  final pt = padding[0], pb = padding[1], pl = padding[2], pr = padding[3];
  final sx = 1.0 - (pl + pr);
  final sy = 1.0 - (pt + pb);
  RectF unpad(RectF r) => RectF((r.xmin - pl) / sx, (r.ymin - pt) / sy, (r.xmax - pl) / sx, (r.ymax - pt) / sy);
  List<double> unpadKp(List<double> kps) {
    final out = List<double>.from(kps);
    for (var i = 0; i < out.length; i += 2) {
      out[i] = (out[i] - pl) / sx;
      out[i + 1] = (out[i + 1] - pt) / sy;
    }
    return out;
  }
  return dets
      .map((d) => Detection(bbox: unpad(d.bbox), score: d.score, keypointsXY: unpadKp(d.keypointsXY)))
      .toList();
}

double _iou(RectF a, RectF b) {
  final x1 = math.max(a.xmin, b.xmin);
  final y1 = math.max(a.ymin, b.ymin);
  final x2 = math.min(a.xmax, b.xmax);
  final y2 = math.min(a.ymax, b.ymax);
  final iw = math.max(0.0, x2 - x1);
  final ih = math.max(0.0, y2 - y1);
  final inter = iw * ih;
  final areaA = math.max(0.0, a.w) * math.max(0.0, a.h);
  final areaB = math.max(0.0, b.w) * math.max(0.0, b.h);
  final uni = areaA + areaB - inter;
  return uni <= 0 ? 0.0 : inter / uni;
}

List<Detection> _nms(List<Detection> dets, double iouThresh, double scoreThresh, {bool weighted = true}) {
  final kept = <Detection>[];
  final cand = dets.where((d) => d.score >= scoreThresh).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  while (cand.isNotEmpty) {
    final base = cand.removeAt(0);
    final merged = <Detection>[base];
    cand.removeWhere((d) {
      if (_iou(base.bbox, d.bbox) >= iouThresh) {
        merged.add(d);
        return true;
      }
      return false;
    });
    if (!weighted || merged.length == 1) {
      kept.add(base);
    } else {
      double sw = 0, xmin = 0, ymin = 0, xmax = 0, ymax = 0;
      for (final m in merged) {
        sw += m.score;
        xmin += m.bbox.xmin * m.score;
        ymin += m.bbox.ymin * m.score;
        xmax += m.bbox.xmax * m.score;
        ymax += m.bbox.ymax * m.score;
      }
      kept.add(Detection(
        bbox: RectF(xmin / sw, ymin / sw, xmax / sw, ymax / sw),
        score: base.score,
        keypointsXY: base.keypointsXY,
      ));
    }
  }
  return kept;
}

Float32List _ssdGenerateAnchors(Map<String, Object> opts) {
  final numLayers = opts['num_layers'] as int;
  final strides = (opts['strides'] as List).cast<int>();
  final inputH = opts['input_size_height'] as int;
  final inputW = opts['input_size_width'] as int;
  final ax = (opts['anchor_offset_x'] as num).toDouble();
  final ay = (opts['anchor_offset_y'] as num).toDouble();
  final interp = (opts['interpolated_scale_aspect_ratio'] as num).toDouble();
  final anchors = <double>[];
  var layerId = 0;
  while (layerId < numLayers) {
    var lastSameStride = layerId;
    var repeats = 0;
    while (lastSameStride < numLayers && strides[lastSameStride] == strides[layerId]) {
      lastSameStride++;
      repeats += (interp == 1.0) ? 2 : 1;
    }
    final stride = strides[layerId];
    final fmH = inputH ~/ stride;
    final fmW = inputW ~/ stride;
    for (var y = 0; y < fmH; y++) {
      final yCenter = (y + ay) / fmH;
      for (var x = 0; x < fmW; x++) {
        final xCenter = (x + ax) / fmW;
        for (var r = 0; r < repeats; r++) {
          anchors.add(xCenter);
          anchors.add(yCenter);
        }
      }
    }
    layerId = lastSameStride;
  }
  return Float32List.fromList(anchors);
}

Map<String, Object> _optsFor(FaceDetectionModel m) {
  switch (m) {
    case FaceDetectionModel.frontCamera:
      return _ssdFront;
    case FaceDetectionModel.backCamera:
      return _ssdBack;
    case FaceDetectionModel.shortRange:
      return _ssdShort;
    case FaceDetectionModel.full:
      return _ssdFull;
    case FaceDetectionModel.fullSparse:
      return _ssdFull;
  }
}

String _nameFor(FaceDetectionModel m) {
  switch (m) {
    case FaceDetectionModel.frontCamera:
      return _modelNameFront;
    case FaceDetectionModel.backCamera:
      return _modelNameBack;
    case FaceDetectionModel.shortRange:
      return _modelNameShort;
    case FaceDetectionModel.full:
      return _modelNameFull;
    case FaceDetectionModel.fullSparse:
      return _modelNameFullSparse;
  }
}

class FaceDetection {
  final Interpreter _itp;
  final int _inW, _inH;
  final int _bboxIndex = 0, _scoreIndex = 1;

  final Float32List _anchors;
  final bool _assumeMirrored;

  FaceDetection._(this._itp, this._inW, this._inH, this._anchors, this._assumeMirrored);

  static Future<FaceDetection> create(FaceDetectionModel model, {InterpreterOptions? options}) async {
    final opts = _optsFor(model);
    final inW = opts['input_size_width'] as int;
    final inH = opts['input_size_height'] as int;
    final anchors = _ssdGenerateAnchors(opts);
    final itp = await Interpreter.fromAsset(
      'assets/models/${_nameFor(model)}',
      options: options ?? InterpreterOptions(),
    );
    final assumeMirrored = switch (model) {
      FaceDetectionModel.backCamera => false,
      _ => true,
    };
    return FaceDetection._(itp, inW, inH, anchors, assumeMirrored);
  }

  Future<List<Detection>> call(Uint8List imageBytes, {RectF? roi}) async {
    final src = img.decodeImage(imageBytes)!;
    final img.Image srcRoi = (roi == null) ? src : cropFromRoi(src, roi);
    final pack = _imageToTensor(srcRoi, outW: _inW, outH: _inH);

    int inputIdx = 0;
    for (final i in [0, 1, 2, 3]) {
      try {
        final s = _itp.getInputTensor(i).shape;
        if (s.length == 4) {
          inputIdx = i;
          break;
        }
      } catch (_) {}
    }
    _itp.resizeInputTensor(inputIdx, [1, _inH, _inW, 3]);
    _itp.allocateTensors();

    int _numElements(List<int> s) => s.fold(1, (a, b) => a * b);
    final boxesShape = _itp.getOutputTensor(_bboxIndex).shape;
    final scoresShape = _itp.getOutputTensor(_scoreIndex).shape;

    final input4d = List.generate(1, (_) => List.generate(_inH, (y) => List.generate(_inW, (x) {
      final base = (y * _inW + x) * 3;
      return [pack.tensorNHWC[base], pack.tensorNHWC[base + 1], pack.tensorNHWC[base + 2]];
    })));

    dynamic outBoxes;
    if (boxesShape.length == 3) {
      outBoxes = List.generate(boxesShape[0], (_) =>
          List.generate(boxesShape[1], (_) => List.filled(boxesShape[2], 0.0)));
    } else if (boxesShape.length == 2) {
      outBoxes = List.generate(boxesShape[0], (_) => List.filled(boxesShape[1], 0.0));
    } else {
      outBoxes = List.filled(boxesShape[0], 0.0);
    }

    dynamic outScores;
    if (scoresShape.length == 3) {
      outScores = List.generate(scoresShape[0], (_) =>
          List.generate(scoresShape[1], (_) => List.filled(scoresShape[2], 0.0)));
    } else if (scoresShape.length == 2) {
      outScores = List.generate(scoresShape[0], (_) => List.filled(scoresShape[1], 0.0));
    } else {
      outScores = List.filled(scoresShape[0], 0.0);
    }

    _itp.runForMultipleInputs([input4d], {
      _bboxIndex: outBoxes,
      _scoreIndex: outScores,
    });

    final rawBoxes = Float32List(_numElements(boxesShape));
    var k = 0;
    if (boxesShape.length == 3) {
      for (var i = 0; i < boxesShape[0]; i++) {
        for (var j = 0; j < boxesShape[1]; j++) {
          for (var l = 0; l < boxesShape[2]; l++) {
            rawBoxes[k++] = (outBoxes[i][j][l] as num).toDouble();
          }
        }
      }
    } else if (boxesShape.length == 2) {
      for (var i = 0; i < boxesShape[0]; i++) {
        for (var j = 0; j < boxesShape[1]; j++) {
          rawBoxes[k++] = (outBoxes[i][j] as num).toDouble();
        }
      }
    } else {
      for (var i = 0; i < boxesShape[0]; i++) {
        rawBoxes[k++] = (outBoxes[i] as num).toDouble();
      }
    }

    final rawScores = Float32List(_numElements(scoresShape));
    k = 0;
    if (scoresShape.length == 3) {
      for (var i = 0; i < scoresShape[0]; i++) {
        for (var j = 0; j < scoresShape[1]; j++) {
          for (var l = 0; l < scoresShape[2]; l++) {
            rawScores[k++] = (outScores[i][j][l] as num).toDouble();
          }
        }
      }
    } else if (scoresShape.length == 2) {
      for (var i = 0; i < scoresShape[0]; i++) {
        for (var j = 0; j < scoresShape[1]; j++) {
          rawScores[k++] = (outScores[i][j] as num).toDouble();
        }
      }
    } else {
      for (var i = 0; i < scoresShape[0]; i++) {
        rawScores[k++] = (outScores[i] as num).toDouble();
      }
    }

    final boxes = _decodeBoxes(rawBoxes, boxesShape);
    final scores = _decodeScores(rawScores, scoresShape);

    final dets = _toDetections(boxes, scores);
    final pruned = _nms(dets, _minSuppressionThreshold, _minScore, weighted: true);
    final fixed = _detectionLetterboxRemoval(pruned, pack.padding);

    List<Detection> mapped;
    if (roi != null) {
      final dx = roi.xmin;
      final dy = roi.ymin;
      final sx = roi.w;
      final sy = roi.h;
      mapped = fixed.map((d) {
        RectF mapRect(RectF r) =>
            RectF(dx + r.xmin * sx, dy + r.ymin * sy, dx + r.xmax * sx, dy + r.ymax * sy);
        List<double> mapKp(List<double> k) {
          final o = List<double>.from(k);
          for (int i = 0; i < o.length; i += 2) {
            o[i] = dx + o[i] * sx;
            o[i + 1] = dy + o[i + 1] * sy;
          }
          return o;
        }
        return Detection(bbox: mapRect(d.bbox), score: d.score, keypointsXY: mapKp(d.keypointsXY));
      }).toList();
    } else {
      mapped = fixed;
    }

    if (_assumeMirrored) {
      mapped = mapped.map((d) {
        final xmin = 1.0 - d.bbox.xmax;
        final xmax = 1.0 - d.bbox.xmin;
        final ymin = d.bbox.ymin;
        final ymax = d.bbox.ymax;
        final kp = List<double>.from(d.keypointsXY);
        for (int i = 0; i < kp.length; i += 2) {
          kp[i] = 1.0 - kp[i];
        }
        return Detection(bbox: RectF(xmin, ymin, xmax, ymax), score: d.score, keypointsXY: kp);
      }).toList();
    }

    for (final det in mapped) {
      final bbox = det.bbox;
      final xminPx = (bbox.xmin * src.width).toInt();
      final yminPx = (bbox.ymin * src.height).toInt();
      final xmaxPx = (bbox.xmax * src.width).toInt();
      final ymaxPx = (bbox.ymax * src.height).toInt();
      print("BBox -> xmin: $xminPx, ymin: $yminPx, xmax: $xmaxPx, ymax: $ymaxPx, score: ${det.score}");
    }
    return mapped;
  }

  List<_DecodedBox> _decodeBoxes(Float32List raw, List<int> shape) {
    final n = shape[1], k = shape[2];
    final scale = _inH.toDouble();
    final out = <_DecodedBox>[];
    final tmp = Float32List(k);
    for (var i = 0; i < n; i++) {
      final base = i * k;
      for (var j = 0; j < k; j++) {
        tmp[j] = raw[base + j] / scale;
      }
      final ax = _anchors[i * 2 + 0];
      final ay = _anchors[i * 2 + 1];
      tmp[0] += ax;
      tmp[1] += ay;
      for (var j = 4; j < k; j += 2) {
        tmp[j + 0] += ax;
        tmp[j + 1] += ay;
      }
      final xc = tmp[0], yc = tmp[1], w = tmp[2], h = tmp[3];
      final xmin = xc - w * 0.5, ymin = yc - h * 0.5, xmax = xc + w * 0.5, ymax = yc + h * 0.5;
      final kp = <double>[];
      for (var j = 4; j < k; j += 2) {
        kp.add(tmp[j + 0]);
        kp.add(tmp[j + 1]);
      }
      out.add(_DecodedBox(RectF(xmin, ymin, xmax, ymax), kp));
    }
    return out;
  }

  Float32List _decodeScores(Float32List raw, List<int> shape) {
    final n = shape[1];
    final scores = Float32List(n);
    for (var i = 0; i < n; i++) {
      scores[i] = _sigmoidClipped(raw[i]);
    }
    return scores;
  }

  List<Detection> _toDetections(List<_DecodedBox> boxes, Float32List scores) {
    final res = <Detection>[];
    final n = math.min(boxes.length, scores.length);
    for (var i = 0; i < n; i++) {
      final b = boxes[i].bbox;
      if (b.xmax <= b.xmin || b.ymax <= b.ymin) continue;
      res.add(Detection(bbox: b, score: scores[i], keypointsXY: boxes[i].keypointsXY));
    }
    return res;
  }
}

class _DecodedBox {
  final RectF bbox;
  final List<double> keypointsXY;
  _DecodedBox(this.bbox, this.keypointsXY);
}

class FaceLandmark {
  final Interpreter _itp;
  final int _inW, _inH;

  FaceLandmark._(this._itp, this._inW, this._inH);

  static Future<FaceLandmark> create({InterpreterOptions? options}) async {
    final itp = await Interpreter.fromAsset(
      'assets/models/$_faceLandmarkModel',
      options: options ?? InterpreterOptions(),
    );
    final ishape = itp.getInputTensor(0).shape;
    final inH = ishape[1];
    final inW = ishape[2];
    return FaceLandmark._(itp, inW, inH);
  }

  Future<List<List<double>>> call(img.Image faceCrop) async {
    final pack = _imageToTensor(faceCrop, outW: _inW, outH: _inH);

    _itp.resizeInputTensor(0, [1, _inH, _inW, 3]);
    _itp.allocateTensors();

    int _numElements(List<int> s) => s.fold(1, (a, b) => a * b);

    final input4d = List.generate(
      1,
          (_) => List.generate(
        _inH,
            (y) => List.generate(
          _inW,
              (x) {
            final base = (y * _inW + x) * 3;
            return [pack.tensorNHWC[base], pack.tensorNHWC[base + 1], pack.tensorNHWC[base + 2]];
          },
        ),
      ),
    );

    final outputs = <int, dynamic>{};
    final shapes = <int, List<int>>{};
    for (var i = 0;; i++) {
      try {
        final s = _itp.getOutputTensor(i).shape;
        shapes[i] = s;
        outputs[i] = _zerosForShape(s);
      } catch (_) {
        break;
      }
    }

    _itp.runForMultipleInputs([input4d], outputs.cast<int, Object>());

    int? bestIdx;
    int bestLen = -1;
    for (final entry in shapes.entries) {
      final len = _numElements(entry.value);
      if (len > bestLen && len % 3 == 0) {
        bestLen = len;
        bestIdx = entry.key;
      }
    }
    if (bestIdx == null) return const <List<double>>[];

    final flat = _flattenToFloat32List(outputs[bestIdx], bestLen);

    final pt = pack.padding[0], pb = pack.padding[1], pl = pack.padding[2], pr = pack.padding[3];
    final sx = 1.0 - (pl + pr);
    final sy = 1.0 - (pt + pb);

    final n = (flat.length / 3).floor();
    final lm = <List<double>>[];
    for (var i = 0; i < n; i++) {
      var x = flat[i * 3 + 0] / _inW;
      var y = flat[i * 3 + 1] / _inH;
      final z = flat[i * 3 + 2];
      x = (x - pl) / sx;
      y = (y - pt) / sy;
      if (x < 0) x = 0; else if (x > 1) x = 1;
      if (y < 0) y = 0; else if (y > 1) y = 1;
      lm.add([x, y, z]);
    }
    return lm;
  }
}

Object _zerosForShape(List<int> shape) {
  if (shape.isEmpty) return 0.0;
  if (shape.length == 1) return List<double>.filled(shape[0], 0.0);
  return List.generate(shape[0], (_) => _zerosForShape(shape.sublist(1)));
}

Float32List _flattenToFloat32List(dynamic nested, int totalLen) {
  final out = Float32List(totalLen);
  int k = 0;
  void walk(dynamic v) {
    if (v is List) {
      for (final e in v) {
        walk(e);
      }
    } else {
      out[k++] = (v as num).toDouble();
    }
  }
  walk(nested);
  return out;
}

class IrisLandmark {
  final Interpreter _itp;
  final int _inW, _inH;

  IrisLandmark._(this._itp, this._inW, this._inH);

  static Future<IrisLandmark> create({InterpreterOptions? options}) async {
    final itp = await Interpreter.fromAsset(
      'assets/models/$_irisLandmarkModel',
      options: options ?? InterpreterOptions(),
    );
    final ishape = itp.getInputTensor(0).shape;
    final inH = ishape[1];
    final inW = ishape[2];
    return IrisLandmark._(itp, inW, inH);
  }

  Future<List<List<double>>> call(img.Image eyeCrop) async {
    final pack = _imageToTensor(eyeCrop, outW: _inW, outH: _inH);

    _itp.resizeInputTensor(0, [1, _inH, _inW, 3]);
    _itp.allocateTensors();

    int _numElements(List<int> s) => s.fold(1, (a, b) => a * b);

    final input4d = List.generate(
      1,
          (_) => List.generate(
        _inH,
            (y) => List.generate(
          _inW,
              (x) {
            final base = (y * _inW + x) * 3;
            return [pack.tensorNHWC[base], pack.tensorNHWC[base + 1], pack.tensorNHWC[base + 2]];
          },
        ),
      ),
    );

    final outputs = <int, dynamic>{};
    final shapes = <int, List<int>>{};
    for (var i = 0;; i++) {
      try {
        final s = _itp.getOutputTensor(i).shape;
        shapes[i] = s;
        outputs[i] = _zerosForShape(s);
      } catch (_) {
        break;
      }
    }

    _itp.runForMultipleInputs([input4d], outputs.cast<int, Object>());

    final lm = <List<double>>[];
    final pt = pack.padding[0], pb = pack.padding[1], pl = pack.padding[2], pr = pack.padding[3];
    final sx = 1.0 - (pl + pr);
    final sy = 1.0 - (pt + pb);

    for (final entry in outputs.entries) {
      final shape = shapes[entry.key]!;
      final flat = _flattenToFloat32List(entry.value, _numElements(shape));
      final n = (flat.length / 3).floor();
      for (var i = 0; i < n; i++) {
        var x = flat[i * 3 + 0] / _inW;
        var y = flat[i * 3 + 1] / _inH;
        final z = flat[i * 3 + 2];
        x = (x - pl) / sx;
        y = (y - pt) / sy;
        lm.add([x, y, z]);
      }
    }

    return lm;
  }

  Future<List<List<double>>> runOnImage(img.Image src, RectF eyeRoi) async {
    final eyeCrop = cropFromRoi(src, eyeRoi);
    final lmNorm = await call(eyeCrop);
    final imgW = src.width.toDouble();
    final imgH = src.height.toDouble();
    final dx = eyeRoi.xmin * imgW;
    final dy = eyeRoi.ymin * imgH;
    final sx = eyeRoi.w * imgW;
    final sy = eyeRoi.h * imgH;
    final mapped = <List<double>>[];
    for (final p in lmNorm) {
      final x = dx + p[0] * sx;
      final y = dy + p[1] * sy;
      mapped.add([x, y, p[2]]);
    }
    return mapped;
  }
}

RectF faceDetectionToRoi(RectF bbox, {double expandFraction = 0.6}) {
  final e = bbox.expand(expandFraction);
  final cx = (e.xmin + e.xmax) * 0.5;
  final cy = (e.ymin + e.ymax) * 0.5;
  final s = math.max(e.w, e.h) * 0.5;
  return RectF(cx - s, cy - s, cx + s, cy + s);
}

img.Image cropFromRoi(img.Image src, RectF roi) {
  final w = src.width.toDouble(), h = src.height.toDouble();
  final x0 = (roi.xmin * w).clamp(0.0, w - 1).toInt();
  final y0 = (roi.ymin * h).clamp(0.0, h - 1).toInt();
  final x1 = (roi.xmax * w).clamp(0.0, w.toDouble()).toInt();
  final y1 = (roi.ymax * h).clamp(0.0, h.toDouble()).toInt();
  final cw = math.max(1, x1 - x0);
  final ch = math.max(1, y1 - y0);
  return img.copyCrop(src, x: x0, y: y0, width: cw, height: ch);
}

class AlignedRoi {
  final double cx;
  final double cy;
  final double size;
  final double theta;
  const AlignedRoi(this.cx, this.cy, this.size, this.theta);
}

img.Image extractAlignedSquare(img.Image src, double cx, double cy, double size, double theta) {
  final side = math.max(1, size.round());
  final half = size * 0.5;
  final ct = math.cos(theta);
  final st = math.sin(theta);
  final out = img.Image(width: side, height: side);
  for (int y = 0; y < side; y++) {
    final vy = ((y + 0.5) / side - 0.5) * size;
    for (int x = 0; x < side; x++) {
      final vx = ((x + 0.5) / side - 0.5) * size;
      final sx = cx + vx * ct - vy * st;
      final sy = cy + vx * st + vy * ct;
      final px = _bilinearSampleRgb8(src, sx, sy);
      out.setPixel(x, y, px);
    }
  }
  return out;
}

img.ColorRgb8 _bilinearSampleRgb8(img.Image src, double fx, double fy) {
  final x0 = fx.floor();
  final y0 = fy.floor();
  final x1 = x0 + 1;
  final y1 = y0 + 1;
  final ax = fx - x0;
  final ay = fy - y0;

  int cx0 = x0.clamp(0, src.width - 1);
  int cx1 = x1.clamp(0, src.width - 1);
  int cy0 = y0.clamp(0, src.height - 1);
  int cy1 = y1.clamp(0, src.height - 1);

  final p00 = src.getPixel(cx0, cy0) as img.Pixel;
  final p10 = src.getPixel(cx1, cy0) as img.Pixel;
  final p01 = src.getPixel(cx0, cy1) as img.Pixel;
  final p11 = src.getPixel(cx1, cy1) as img.Pixel;

  final r0 = p00.r * (1 - ax) + p10.r * ax;
  final g0 = p00.g * (1 - ax) + p10.g * ax;
  final b0 = p00.b * (1 - ax) + p10.b * ax;

  final r1 = p01.r * (1 - ax) + p11.r * ax;
  final g1 = p01.g * (1 - ax) + p11.g * ax;
  final b1 = p01.b * (1 - ax) + p11.b * ax;

  final r = (r0 * (1 - ay) + r1 * ay).round().clamp(0, 255);
  final g = (g0 * (1 - ay) + g1 * ay).round().clamp(0, 255);
  final b = (b0 * (1 - ay) + b1 * ay).round().clamp(0, 255);

  return img.ColorRgb8(r, g, b);
}