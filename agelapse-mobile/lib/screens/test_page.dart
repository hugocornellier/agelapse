// lib/test_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../utils/fdlite_single.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});
  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  Uint8List? _imageBytes;
  List<Detection> _detections = [];
  List<Offset> _irisPoints = [];
  FaceDetection? _detector;
  IrisLandmark? _iris;

  @override
  void initState() {
    super.initState();
    _initModels();
  }

  Future<void> _initModels() async {
    final det = await FaceDetection.create(FaceDetectionModel.backCamera);
    final iris = await IrisLandmark.create();
    setState(() {
      _detector = det;
      _iris = iris;
    });
  }

  Future<void> _pickAndRun() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    if (_detector == null) return;

    final dets = await _detector!.call(bytes);

    final points = <Offset>[];
    if (dets.isNotEmpty && _iris != null) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        for (final d in dets) {
          final eyeRois = _estimateEyeRoisFromDetection(d);
          for (final roi in eyeRois) {
            final irisLm = await _iris!.runOnImage(decoded, roi);
            for (final p in irisLm) {
              points.add(Offset(p[0].toDouble(), p[1].toDouble()));
            }
          }
        }
      }
    }

    setState(() {
      _imageBytes = bytes;
      _detections = dets;
      _irisPoints = points;
    });
  }

  List<RectF> _estimateEyeRoisFromDetection(Detection d) {
    final lx = d.keypointsXY[FaceIndex.leftEye.index * 2];
    final ly = d.keypointsXY[FaceIndex.leftEye.index * 2 + 1];
    final rx = d.keypointsXY[FaceIndex.rightEye.index * 2];
    final ry = d.keypointsXY[FaceIndex.rightEye.index * 2 + 1];
    final bw = d.bbox.w;
    final bh = d.bbox.h;
    final s = (bw < bh ? bw : bh) * 0.18;
    return [
      RectF(lx - s, ly - s, lx + s, ly + s),
      RectF(rx - s, ry - s, rx + s, ry + s),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null;
    return Scaffold(
      appBar: AppBar(title: const Text('FDLite Test Page')),
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
                if (!snap.hasData) {
                  return const CircularProgressIndicator();
                }
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

class _DetectionsPainter extends CustomPainter {
  final List<Detection> detections;
  final List<Offset> irisPoints;
  final Size originalSize;

  _DetectionsPainter({required this.detections, required this.irisPoints, required this.originalSize});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / originalSize.width;
    final sy = size.height / originalSize.height;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final kpPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF89CFF0);

    final irisPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF89CFF0);


    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.bbox.xmin * originalSize.width * sx / (originalSize.width / size.width),
        d.bbox.ymin * originalSize.height * sy / (originalSize.height / size.height),
        d.bbox.xmax * originalSize.width * sx / (originalSize.width / size.width),
        d.bbox.ymax * originalSize.height * sy / (originalSize.height / size.height),
      );
      canvas.drawRect(rect, boxPaint);

      for (int i = 0; i < d.keypointsXY.length; i += 2) {
        final x = d.keypointsXY[i] * size.width;
        final y = d.keypointsXY[i + 1] * size.height;
        canvas.drawCircle(Offset(x, y), 3, kpPaint);
      }
    }

    for (final p in irisPoints) {
      final x = p.dx * size.width / originalSize.width;
      final y = p.dy * size.height / originalSize.height;
      canvas.drawCircle(Offset(x, y), 2, irisPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionsPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.irisPoints != irisPoints ||
        oldDelegate.originalSize != originalSize;
  }
}
