import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class BoundingBox {
  final double xmin, ymin, xmax, ymax, score;

  BoundingBox({
    required this.xmin,
    required this.ymin,
    required this.xmax,
    required this.ymax,
    required this.score,
  });
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  final ImagePicker picker = ImagePicker();
  late Interpreter interpreter;
  String resultText = "Initializing...";
  List<Rect> detectedRects = [];
  File? capturedImageFile;
  List<BoundingBox> capturedBoxes = [];
  int imageWidth = 0, imageHeight = 0;
  List<img.Image> imageFiles = [];
  List<int> facesList = [];
  List<double> faceScores = [];
  List<Object> confidences = [];
  Uint8List? selectedImage;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  img.Image cropFromBox(img.Image src, BoundingBox b) {
    final int x = b.xmin.floor().clamp(0, src.width - 1);
    final int y = b.ymin.floor().clamp(0, src.height - 1);
    final int w = (b.xmax - b.xmin).ceil().clamp(1, src.width - x);
    final int h = (b.ymax - b.ymin).ceil().clamp(1, src.height - y);
    return img.copyCrop(src, x: x, y: y, width: w, height: h);
  }


  Future<void> initializeCamera() async {}

  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset(
      'assets/blazeface.tflite',
      options: InterpreterOptions()..threads = 2,
    );
  }

  @override
  void dispose() {
    interpreter.close();
    super.dispose();
  }

  double sigmoid(double x) => 1 / (1 + exp(-x));

  double iou(BoundingBox a, BoundingBox b) {
    final double x1 = max(a.xmin, b.xmin);
    final double y1 = max(a.ymin, b.ymin);
    final double x2 = min(a.xmax, b.xmax);
    final double y2 = min(a.ymax, b.ymax);
    final double interArea = max(0, x2 - x1) * max(0, y2 - y1);
    final double boxAArea = (a.xmax - a.xmin) * (a.ymax - a.ymin);
    final double boxBArea = (b.xmax - b.xmin) * (b.ymax - b.ymin);
    return interArea / (boxAArea + boxBArea - interArea);
  }

  double overlapOverMinArea(BoundingBox a, BoundingBox b) {
    final double x1 = max(a.xmin, b.xmin);
    final double y1 = max(a.ymin, b.ymin);
    final double x2 = min(a.xmax, b.xmax);
    final double y2 = min(a.ymax, b.ymax);
    final double interArea = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    final double areaA = (a.xmax - a.xmin) * (a.ymax - a.ymin);
    final double areaB = (b.xmax - b.xmin) * (b.ymax - b.ymin);
    final double minArea = max(1e-6, min(areaA, areaB));
    return interArea / minArea;
  }

  List<BoundingBox> nonMaximumSuppression(
      List<BoundingBox> boxes, {
        double iouThreshold = 0.3,
        double overlapMinAreaThreshold = 0.6,
        double centerDistThreshold = 0.05,
      }) {
    final int pre = boxes.length;
    final List<BoundingBox> picked = [];
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final used = List<bool>.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (used[i]) continue;
      picked.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (used[j]) continue;

        final double iouVal = iou(boxes[i], boxes[j]);
        final double overlapMin = overlapOverMinArea(boxes[i], boxes[j]);
        final bool centerInside =
            isCenterInside(boxes[j], boxes[i]) || isCenterInside(boxes[i], boxes[j]);
        final double cdr = centerDistanceRatio(boxes[i], boxes[j]); // 0..1

        final bool sameFace =
            iouVal > iouThreshold ||
                overlapMin >= overlapMinAreaThreshold ||
                centerInside ||
                cdr <= centerDistThreshold;

        if (sameFace) {
          used[j] = true;
        }
      }
    }

    print(
        'NMS iou>=$iouThreshold overlapMin>=$overlapMinAreaThreshold centerDist<=$centerDistThreshold pre=$pre post=${picked.length}');
    return picked;
  }


  Future<List<Map<String, dynamic>>> runBlazeFace(img.Image? image, {double threshold = 0.75}) async {
    if (image == null) return [];
    imageWidth = image.width;
    imageHeight = image.height;

    final int side = min(imageWidth, imageHeight);
    final int offsetX = ((imageWidth - side) / 2).floor();
    final int offsetY = ((imageHeight - side) / 2).floor();

    final resized = img.copyResizeCropSquare(image, size: 128);
    final input = [
      List.generate(
        128,
            (y) => List.generate(128, (x) {
          final p = resized.getPixel(x, y);
          return [(p.r / 127.5) - 1.0, (p.g / 127.5) - 1.0, (p.b / 127.5) - 1.0];
        }),
      ),
    ];

    final regressors = List.generate(1, (_) => List.generate(896, (_) => List.filled(16, 0.0)));
    final classificators = List.generate(1, (_) => List.generate(896, (_) => List.filled(1, 0.0)));
    final outputs = {0: regressors, 1: classificators};
    interpreter.runForMultipleInputs([input], outputs);

    final reg = (outputs[0]! as List)[0] as List;
    final cls = (outputs[1]! as List)[0] as List;

    final List<Map<String, num>> anchors = [];
    const double inputSize = 128.0;
    const strides = [8, 16];
    const anchorsPerLoc = [2, 6];

    int anchorIndex = 0;
    for (int li = 0; li < strides.length; li++) {
      final stride = strides[li];
      final fm = (inputSize / stride).ceil();
      for (int y = 0; y < fm; y++) {
        for (int x = 0; x < fm; x++) {
          for (int a = 0; a < anchorsPerLoc[li]; a++) {
            anchors.add({
              'li': li,
              'fm': fm,
              'xi': x,
              'yi': y,
              'x_center': (x + 0.5) / fm,
              'y_center': (y + 0.5) / fm,
              'w': 1.0,
              'h': 1.0,
              'idx': anchorIndex,
            });
            anchorIndex++;
          }
        }
      }
    }

    final Map<String, int> bestPerCell = {};
    final Map<String, double> bestScore = {};
    int aboveThresh = 0;
    final List<double> topScores = [];

    for (int i = 0; i < 896; i++) {
      final score = sigmoid((cls[i][0] as double));
      if (score < threshold) continue;
      aboveThresh++;
      topScores.add(score);

      final a = anchors[i];
      final key = '${a['li']}_${a['xi']}_${a['yi']}';
      final prev = bestScore[key];
      if (prev == null || score > prev) {
        bestScore[key] = score;
        bestPerCell[key] = i;
      }
    }

    List<BoundingBox> rawBoxes = [];
    for (final entry in bestPerCell.entries) {
      final i = entry.value;
      final score = bestScore[entry.key]!;
      final a = anchors[i];

      final dy = (reg[i][0] as double);
      final dx = (reg[i][1] as double);
      final dh = (reg[i][2] as double);
      final dw = (reg[i][3] as double);

      final xCenter = dx / 128.0 * (a['w'] as double) + (a['x_center'] as double);
      final yCenter = dy / 128.0 * (a['h'] as double) + (a['y_center'] as double);
      final w = dw / 128.0 * (a['w'] as double);
      final h = dh / 128.0 * (a['h'] as double);

      double xmin = (xCenter - w / 2.0) * side + offsetX.toDouble();
      double ymin = (yCenter - h / 2.0) * side + offsetY.toDouble();
      double xmax = (xCenter + w / 2.0) * side + offsetX.toDouble();
      double ymax = (yCenter + h / 2.0) * side + offsetY.toDouble();

      xmin = xmin.clamp(0.0, imageWidth.toDouble());
      ymin = ymin.clamp(0.0, imageHeight.toDouble());
      xmax = xmax.clamp(0.0, imageWidth.toDouble());
      ymax = ymax.clamp(0.0, imageHeight.toDouble());

      if (xmax > xmin && ymax > ymin) {
        rawBoxes.add(BoundingBox(xmin: xmin, ymin: ymin, xmax: xmax, ymax: ymax, score: score));
      }
    }

    final finalBoxes = nonMaximumSuppression(
      rawBoxes,
      iouThreshold: 0.45,
      overlapMinAreaThreshold: 0.6,
      centerDistThreshold: 0.03,
    );

    detectedRects = finalBoxes
        .map((b) => Rect.fromLTWH(b.xmin, b.ymin, b.xmax - b.xmin, b.ymax - b.ymin))
        .toList();

    return finalBoxes.map((b) => {'confidence': b.score, 'bbox': b}).toList();
  }


  bool isCenterInside(BoundingBox a, BoundingBox b) {
    final double cx = (a.xmin + a.xmax) * 0.5;
    final double cy = (a.ymin + a.ymax) * 0.5;
    return cx >= b.xmin && cx <= b.xmax && cy >= b.ymin && cy <= b.ymax;
  }

  double centerDistanceRatio(BoundingBox a, BoundingBox b) {
    final double acx = (a.xmin + a.xmax) * 0.5;
    final double acy = (a.ymin + a.ymax) * 0.5;
    final double bcx = (b.xmin + b.xmax) * 0.5;
    final double bcy = (b.ymin + b.ymax) * 0.5;

    final double dx = acx - bcx;
    final double dy = acy - bcy;
    final double dist2 = dx * dx + dy * dy;

    final double x1 = min(a.xmin, b.xmin);
    final double y1 = min(a.ymin, b.ymin);
    final double x2 = max(a.xmax, b.xmax);
    final double y2 = max(a.ymax, b.ymax);
    final double diag2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);

    return diag2 <= 1e-6 ? 0.0 : dist2 / diag2; // 0 = same center, 1 = far apart
  }


  Future<void> captureAndDetect() async {
    setState(() {
      resultText = "Selecting image...";
      imageFiles.clear();
      facesList.clear();
      confidences.clear();
      selectedImage = null;
    });

    final XFile? xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) {
      setState(() {
        resultText = "No image selected";
      });
      return;
    }

    final bytes = await xFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      setState(() {
        resultText = "Failed to decode image";
      });
      return;
    }

    selectedImage = bytes;

    imageFiles.clear();
    faceScores.clear();
    final faces = await runBlazeFace(image);
    for (final f in faces) {
      final b = f['bbox'] as BoundingBox;
      final c = f['confidence'] as double;
      final crop = cropFromBox(image, b);
      imageFiles.add(crop);
      faceScores.add(c);
    }
    facesList
      ..clear()
      ..add(imageFiles.length);
    confidences
      ..clear()
      ..add(faceScores.map((e) => e.toStringAsFixed(2)).toList());



    setState(() {
      resultText = "Detection complete";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BlazeFace Face Detector"),
        centerTitle: true,
        backgroundColor: Colors.black87,
      ),
      body: Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: SizedBox(
                  height: 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: selectedImage == null
                        ? const Center(
                      child: Text(
                        "No image selected",
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                        : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          selectedImage!,
                          fit: BoxFit.contain,
                        ),
                        CustomPaint(
                          painter: FaceBoxesPainter(
                            boxes: detectedRects,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ),
              const SizedBox(height: 20),
              Text(
                resultText,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: captureAndDetect,
                icon: const Icon(Icons.photo_library),
                label: const Text("Pick Image & Detect"),
                style: ElevatedButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 30),
              if (imageFiles.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: imageFiles.length,
                  itemBuilder: (context, index) {
                    final imageMem =
                    Uint8List.fromList(img.encodeJpg(imageFiles[index]));
                    final conf = faceScores[index].toStringAsFixed(2);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            "Face #${index + 1}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 256,
                            height: 256,
                            decoration: BoxDecoration(
                              border:
                              Border.all(color: Colors.deepPurple, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                imageMem,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Confidence: $conf",
                            style: const TextStyle(
                                fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),

            ],
          ),
        ),
      ),
    );
  }
}

class FaceBoxesPainter extends CustomPainter {
  final List<Rect> boxes;
  final int imageWidth;
  final int imageHeight;

  FaceBoxesPainter({
    required this.boxes,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0 || boxes.isEmpty) return;

    final double scale = (size.width / imageWidth).clamp(0, double.infinity);
    final double scaleH = (size.height / imageHeight).clamp(0, double.infinity);
    final double s = scale < scaleH ? scale : scaleH;

    final double dx = (size.width - imageWidth * s) * 0.5;
    final double dy = (size.height - imageHeight * s) * 0.5;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.redAccent;

    for (final b in boxes) {
      final rect = Rect.fromLTWH(
        b.left * s + dx,
        b.top * s + dy,
        b.width * s,
        b.height * s,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceBoxesPainter oldDelegate) {
    return oldDelegate.boxes != boxes ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
