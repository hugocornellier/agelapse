import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/face_stabilizer.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';

class ManualStabilizationPage extends StatefulWidget {
  final String imagePath;
  final int projectId;

  const ManualStabilizationPage({
    Key? key,
    required this.imagePath,
    required this.projectId,
  }) : super(key: key);

  @override
  _ManualStabilizationPageState createState() => _ManualStabilizationPageState();
}

class _ManualStabilizationPageState extends State<ManualStabilizationPage> {
  String rawPhotoPath = "";
  Uint8List? _stabilizedImageBytes;
  late FaceStabilizer faceStabilizer;
  int? _canvasWidth;
  int? _canvasHeight;
  int? _leftEyeXGoal;
  int? _rightEyeXGoal;
  int? _bothEyesYGoal;
  late String aspectRatio;
  late int canvasHeight;
  late int canvasWidth;

  final TextEditingController _inputController1 = TextEditingController();
  final TextEditingController _inputController2 = TextEditingController();
  final TextEditingController _inputController3 = TextEditingController();
  final TextEditingController _inputController4 = TextEditingController();

  bool _isProcessing = false;
  Timer? _debounce;
  double? _lastTx;
  double? _lastTy;
  double? _lastSc;
  double? _lastRot;

  @override
  void initState() {

    super.initState();
    _inputController1.text = '0';
    _inputController2.text = '0';
    _inputController3.text = '1';
    _inputController4.text = '0';

    _inputController1.addListener(_onParamChanged);
    _inputController2.addListener(_onParamChanged);
    _inputController3.addListener(_onParamChanged);
    _inputController4.addListener(_onParamChanged);

    init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputController1.dispose();
    _inputController2.dispose();
    _inputController3.dispose();
    _inputController4.dispose();
    super.dispose();
  }

  Future<void> init() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    String resolution = await SettingsUtil.loadVideoResolution(widget.projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(widget.projectId.toString());
    double? aspectRatioDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);

    final double? shortSideDouble = StabUtils.getShortSide(resolution);
    final int longSide = (aspectRatioDecimal! * shortSideDouble!).toInt();
    final int shortSide = shortSideDouble.toInt();

    canvasWidth = projectOrientation == "landscape" ? longSide : shortSide;
    canvasHeight = projectOrientation == "landscape" ? shortSide : longSide;

    String localRawPath;
    if (widget.imagePath.contains('/stabilized/')) {
      localRawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        p.basenameWithoutExtension(widget.imagePath),
        widget.projectId,
      );
    } else {
      localRawPath = widget.imagePath;
    }
    setState(() {
      rawPhotoPath = localRawPath;
    });

    final ui.Image? original = await StabUtils.loadImageFromFile(File(localRawPath));
    if (original != null) {
      final double defaultScale = canvasWidth / original.width;
      _inputController3.text = defaultScale.toStringAsFixed(2);
      original.dispose();
    }

    faceStabilizer = FaceStabilizer(widget.projectId, () => print("Test"));
    await faceStabilizer.init();

    double? tx = double.tryParse(_inputController1.text);
    double? ty = double.tryParse(_inputController2.text);
    double? sc = double.tryParse(_inputController3.text);
    double? rot = double.tryParse(_inputController4.text);
    processRequest(tx, ty, sc, rot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Stabilization'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Two inputs side by side - Translate X and Y
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController1,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Horiz. Offset',
                        labelStyle: TextStyle(fontSize: 14),
                        floatingLabelStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _inputController2,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Vert. Offset',
                        labelStyle: TextStyle(fontSize: 14),
                        floatingLabelStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController3,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Scale Factor',
                        labelStyle: TextStyle(fontSize: 14),
                        floatingLabelStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _inputController4,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Rotation (Deg)',
                        labelStyle: TextStyle(fontSize: 14),
                        floatingLabelStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isProcessing) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Please wait a moment...'),
                const SizedBox(height: 16),
              ],
              if (!_isProcessing &&
                  _stabilizedImageBytes != null &&
                  _canvasWidth != null &&
                  _canvasHeight != null &&
                  _leftEyeXGoal != null &&
                  _rightEyeXGoal != null &&
                  _bothEyesYGoal != null)
                Stack(
                  children: [
                    Image.memory(
                      _stabilizedImageBytes!,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.width * _canvasHeight! / _canvasWidth!,
                      fit: BoxFit.fill,
                    ),
                    CustomPaint(
                      painter: LineOverlayPainter(
                        canvasWidth: _canvasWidth!,
                        canvasHeight: _canvasHeight!,
                        leftEyeXGoal: _leftEyeXGoal!,
                        rightEyeXGoal: _rightEyeXGoal!,
                        bothEyesYGoal: _bothEyesYGoal!,
                      ),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width * _canvasHeight! / _canvasWidth!,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> processRequest(double? translateX, double? translateY, double? scaleFactor, double? rotationDegrees) async {
    setState(() {
      _isProcessing = true;
    });
    try {
      final ui.Image? img = await StabUtils.loadImageFromFile(File(rawPhotoPath));
      if (img == null) {
        return;
      }

      final Uint8List? imageBytesStabilized = await faceStabilizer.generateStabilizedImageBytes(img, rotationDegrees, scaleFactor, translateX, translateY);
      if (imageBytesStabilized == null) {
        return;
      }

      setState(() {
        _stabilizedImageBytes = imageBytesStabilized;
      });

      final String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
      final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, widget.projectId, projectOrientation);
      final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(stabilizedPhotoPath);

      final File stabImageFile = File(stabilizedPhotoPath);
      final File stabThumbFile = File(stabThumbPath);
      if (await stabImageFile.exists()) {
        await stabImageFile.delete();
      }
      if (await stabThumbFile.exists()) {
        await stabThumbFile.delete();
      }

      await faceStabilizer.saveStabilizedImage(imageBytesStabilized, rawPhotoPath, stabilizedPhotoPath, 0.0);
      await faceStabilizer.createStabThumbnail(stabilizedPhotoPath.replaceAll('.jpg', '.png'));

      final int canvasHeight = faceStabilizer.canvasHeight;
      final int canvasWidth = faceStabilizer.canvasWidth;
      final int leftEyeXGoal = faceStabilizer.leftEyeXGoal;
      final int rightEyeXGoal = faceStabilizer.rightEyeXGoal;
      final int bothEyesYGoal = faceStabilizer.bothEyesYGoal;

      setState(() {
        _canvasWidth = canvasWidth;
        _canvasHeight = canvasHeight;
        _leftEyeXGoal = leftEyeXGoal;
        _rightEyeXGoal = rightEyeXGoal;
        _bothEyesYGoal = bothEyesYGoal;
        _lastTx = translateX;
        _lastTy = translateY;
        _lastSc = scaleFactor;
        _lastRot = rotationDegrees;
      });

      img.dispose();
    } catch (_) {} finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _onParamChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
      double? sc = double.tryParse(_inputController3.text);
      double? rot = double.tryParse(_inputController4.text);

      const double tolerance = 0.0001;
      bool changed = (_lastTx == null || (_lastTx! - (tx ?? 0)).abs() > tolerance) ||
          (_lastTy == null || (_lastTy! - (ty ?? 0)).abs() > tolerance) ||
          (_lastSc == null || (_lastSc! - (sc ?? 0)).abs() > tolerance) ||
          (_lastRot == null || (_lastRot! - (rot ?? 0)).abs() > tolerance);

      if (changed) {
        processRequest(tx, ty, sc, rot);
      }
    });
  }
}

class LineOverlayPainter extends CustomPainter {
  final int canvasWidth;
  final int canvasHeight;
  final int leftEyeXGoal;
  final int rightEyeXGoal;
  final int bothEyesYGoal;
  LineOverlayPainter({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.leftEyeXGoal,
    required this.rightEyeXGoal,
    required this.bothEyesYGoal,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / canvasWidth;
    final double scaleY = size.height / canvasHeight;
    final paint = Paint()..color = Colors.red..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, bothEyesYGoal * scaleY), Offset(size.width, bothEyesYGoal * scaleY), paint);
    canvas.drawLine(Offset(leftEyeXGoal * scaleX, 0), Offset(leftEyeXGoal * scaleX, size.height), paint);
    canvas.drawLine(Offset(rightEyeXGoal * scaleX, 0), Offset(rightEyeXGoal * scaleX, size.height), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}