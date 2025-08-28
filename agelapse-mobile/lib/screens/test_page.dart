import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../utils/fdlite_single.dart'; // uses your updated FaceDetection/FaceLandmark/IrisLandmark

class TestPage extends StatefulWidget {
  const TestPage({super.key});
  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  Uint8List? _imageBytes;

  // Results
  List<Detection> _detections = [];
  List<Offset> _faceMeshPoints = [];
  List<Offset> _irisPoints = [];

  // Models
  FaceDetection? _detector;
  FaceLandmark? _faceLm;
  IrisLandmark? _iris;

  @override
  void initState() {
    super.initState();
    _initModels();
  }

  Future<void> _initModels() async {
    final det = await FaceDetection.create(FaceDetectionModel.backCamera);
    final faceLm = await FaceLandmark.create();
    final iris = await IrisLandmark.create();
    setState(() {
      _detector = det;
      _faceLm = faceLm;
      _iris = iris;
    });
  }

  Future<void> _pickAndRun() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (_detector == null || _faceLm == null || _iris == null) return;

    // 1) face detection
    final dets = await _detector!.call(bytes);
    final decoded = img.decodeImage(bytes);

    final meshPoints = <Offset>[];
    final irisPoints = <Offset>[];

    if (decoded != null && dets.isNotEmpty) {
      // for demo, just use the most confident face
      final d = dets.first;

      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();

      final lx = d.keypointsXY[FaceIndex.leftEye.index * 2] * imgW;
      final ly = d.keypointsXY[FaceIndex.leftEye.index * 2 + 1] * imgH;
      final rx = d.keypointsXY[FaceIndex.rightEye.index * 2] * imgW;
      final ry = d.keypointsXY[FaceIndex.rightEye.index * 2 + 1] * imgH;
      final mx = d.keypointsXY[FaceIndex.mouth.index * 2] * imgW;
      final my = d.keypointsXY[FaceIndex.mouth.index * 2 + 1] * imgH;

      final eyeCenter = Offset((lx + rx) * 0.5, (ly + ry) * 0.5);
      final vEye = Offset(rx - lx, ry - ly);
      final vMouth = Offset(mx - eyeCenter.dx, my - eyeCenter.dy);

      final cx = eyeCenter.dx + vMouth.dx * 0.1;
      final cy = eyeCenter.dy + vMouth.dy * 0.1;
      final size = math.max(vMouth.distance * 3.6, vEye.distance * 4.0);
      final theta = math.atan2(vEye.dy, vEye.dx);

      final faceCrop = extractAlignedSquare(decoded, cx, cy, size, -theta);

      final lmNorm = await _faceLm!.call(faceCrop);

      final ct = math.cos(theta);
      final st = math.sin(theta);
      for (final p in lmNorm) {
        final lx2 = (p[0] - 0.5) * size;
        final ly2 = (p[1] - 0.5) * size;
        final x = cx + lx2 * ct - ly2 * st;
        final y = cy + lx2 * st + ly2 * ct;
        meshPoints.add(Offset(x.toDouble(), y.toDouble()));
      }

      // 3) (optional) iris points from mesh-derived eye ROIs
      final eyeRois = _eyeRoisFromMesh(meshPoints, decoded.width, decoded.height);
      for (final roi in eyeRois) {
        final irisLm = await _iris!.runOnImage(decoded, roi); // returns absolute image coords
        for (final p in irisLm) {
          irisPoints.add(Offset(p[0].toDouble(), p[1].toDouble()));
        }
      }
    }

    setState(() {
      _imageBytes = bytes;
      _detections = dets;
      _faceMeshPoints = meshPoints;
      _irisPoints = irisPoints;
    });
  }

  // Eye ROIs from mesh points (MediaPipe indices around eyelids)
  List<RectF> _eyeRoisFromMesh(List<Offset> meshAbs, int imgW, int imgH) {
    RectF boxFrom(List<int> idxs) {
      double xmin = double.infinity, ymin = double.infinity, xmax = -double.infinity, ymax = -double.infinity;
      for (final i in idxs) {
        final p = meshAbs[i];
        if (p.dx < xmin) xmin = p.dx;
        if (p.dy < ymin) ymin = p.dy;
        if (p.dx > xmax) xmax = p.dx;
        if (p.dy > ymax) ymax = p.dy;
      }
      final cx = (xmin + xmax) * 0.5;
      final cy = (ymin + ymax) * 0.5;
      final s = ((xmax - xmin) > (ymax - ymin) ? (xmax - xmin) : (ymax - ymin)) * 0.85;
      final half = s * 0.5;
      return RectF(
        (cx - half) / imgW,
        (cy - half) / imgH,
        (cx + half) / imgW,
        (cy + half) / imgH,
      );
    }

    return [boxFrom(_leftEyeIdx), boxFrom(_rightEyeIdx)];
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null;
    return Scaffold(
      appBar: AppBar(title: const Text('FDLite Mesh Demo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndRun,
        label: const Text('Pick Image'),
        icon: const Icon(Icons.image),
      ),
      body: Center(
        child: hasImage
            ? LayoutBuilder(
          builder: (context, constraints) {
            return FutureBuilder<Size>(
              future: _imageSize(_imageBytes!),
              builder: (context, snap) {
                if (!snap.hasData) return const CircularProgressIndicator();
                final imgSize = snap.data!;
                final fitted = _fitSize(imgSize, Size(constraints.maxWidth, constraints.maxHeight));
                return SizedBox(
                  width: fitted.width,
                  height: fitted.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_imageBytes!, fit: BoxFit.contain),
                      CustomPaint(
                        painter: _DetectionsPainter(
                          detections: _detections,
                          faceMeshPoints: _faceMeshPoints,
                          irisPoints: _irisPoints,
                          originalSize: imgSize,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        )
            : const Text('Pick an image to run detection'),
      ),
    );
  }

  Future<Size> _imageSize(Uint8List bytes) async {
    final decoded = await decodeImageFromList(bytes);
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  Size _fitSize(Size src, Size bound) {
    final scale = (bound.width / src.width < bound.height / src.height)
        ? bound.width / src.width
        : bound.height / src.height;
    return Size(src.width * scale, src.height * scale);
  }
}

// ——— Painter ————————————————————————————————————————————————————————————

class _DetectionsPainter extends CustomPainter {
  final List<Detection> detections;
  final List<Offset> faceMeshPoints;
  final List<Offset> irisPoints;
  final Size originalSize;

  _DetectionsPainter({
    required this.detections,
    required this.faceMeshPoints,
    required this.irisPoints,
    required this.originalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF00FFCC);

    final detKpPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF89CFF0);

    final meshPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 // point size for mesh
      ..color = const Color(0xFFFF00FF); // magenta like your screenshot

    final irisPtPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF89CFF0);

    // detector boxes + detector keypoints
    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.bbox.xmin * size.width,
        d.bbox.ymin * size.height,
        d.bbox.xmax * size.width,
        d.bbox.ymax * size.height,
      );
      canvas.drawRect(rect, boxPaint);

      for (int i = 0; i < d.keypointsXY.length; i += 2) {
        final x = d.keypointsXY[i] * size.width;
        final y = d.keypointsXY[i + 1] * size.height;
        canvas.drawCircle(Offset(x, y), 3, detKpPaint);
      }
    }

    // face mesh points (scaled from original image space to the fitted canvas)
    if (faceMeshPoints.isNotEmpty) {
      final scaled = faceMeshPoints
          .map((p) => Offset(p.dx * size.width / originalSize.width, p.dy * size.height / originalSize.height))
          .toList();
      print(scaled);
      canvas.drawPoints(PointMode.points, scaled, meshPaint);
    }

    // iris points (optional, same scaling)
    if (irisPoints.isNotEmpty) {
      final scaledIris = irisPoints
          .map((p) => Offset(p.dx * size.width / originalSize.width, p.dy * size.height / originalSize.height))
          .toList();
      canvas.drawPoints(PointMode.points, scaledIris, irisPtPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionsPainter old) {
    return old.detections != detections ||
        old.faceMeshPoints != faceMeshPoints ||
        old.irisPoints != irisPoints ||
        old.originalSize != originalSize;
  }
}

// ——— Mesh eye indices for ROI estimation ————————————————

const List<int> _leftEyeIdx = [
  33, 133, 160, 159, 158, 157, 173, 246, 161, 144, 145, 153
];

const List<int> _rightEyeIdx = [
  362, 263, 387, 386, 385, 384, 398, 466, 388, 373, 374, 380
];