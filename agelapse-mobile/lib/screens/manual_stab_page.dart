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
import '../widgets/grid_painter_se.dart';

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
  int _currentRequestId = 0;
  int? _bothEyesYGoal;
  late String aspectRatio;
  late String projectOrientation;
  late int canvasHeight;
  late int canvasWidth;

  final TextEditingController _inputController1 = TextEditingController();
  final TextEditingController _inputController2 = TextEditingController();
  final TextEditingController _inputController3 = TextEditingController();
  final TextEditingController _inputController4 = TextEditingController();

  bool _isProcessing = false;
  Timer? _debounce;
  double _baseScale = 1.0;
  double? _lastTx;
  double? _lastTy;
  double? _lastMult;
  double? _lastRot;

  @override
  void initState() {

    super.initState();
    _inputController1.text = '0';
    _inputController2.text = '0';
    _inputController3.text = '1';
    _inputController4.text = '0';

    _lastValid = {
      _inputController1: _inputController1.text,
      _inputController2: _inputController2.text,
      _inputController3: _inputController3.text,
      _inputController4: _inputController4.text,
    };

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
    projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    String resolution = await SettingsUtil.loadVideoResolution(widget.projectId.toString());
    aspectRatio = await SettingsUtil.loadAspectRatio(widget.projectId.toString());
    double? aspectRatioDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);

    print("Project orientation => '${projectOrientation}'");

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
      _baseScale = defaultScale;
      _inputController3.text = '1';
      original.dispose();
    }

    faceStabilizer = FaceStabilizer(widget.projectId, () => print("Test"));
    await faceStabilizer.init();

    double? tx = double.tryParse(_inputController1.text);
    double? ty = double.tryParse(_inputController2.text);
    double? mult = double.tryParse(_inputController3.text) ?? 1.0;
    double? rot = double.tryParse(_inputController4.text);
    double? sc = _baseScale * mult;
    processRequest(tx, ty, sc, rot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,           // let the body draw underneath the bottom bar
      appBar: AppBar(
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text(
          'Manual Stabilization',
          style: TextStyle(fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Quick Guide'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '• Goal: Center each pupil on its vertical line and place both pupils exactly on the horizontal line.\n'
                          '• Horiz. Offset (whole number, ±): Shifts the image left/right. Increase to move the face right, decrease to move left.\n'
                          '• Vert. Offset (whole number, ±): Shifts the image up/down. Increase to move the face up, decrease to move down.\n'
                          '• Scale Factor (positive decimal): Zooms in or out. Values > 1 enlarge, values between 0 and 1 shrink.\n'
                          '• Rotation (decimal, ±): Tilts the image. Positive values rotate clockwise, negative counter-clockwise.\n\n'
                          'Use the toolbar arrows or type exact numbers. Keep adjusting until the pupils touch all three guides.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: Colors.grey.shade700.withOpacity(0.5),
          ),
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
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController1,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onEditingComplete: _validateInputs,
                      decoration: const InputDecoration(
                        labelText: 'Horiz. Offset',
                        labelStyle: TextStyle(fontSize: 15),
                        floatingLabelStyle: TextStyle(fontSize: 14),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _inputController2,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onEditingComplete: _validateInputs,
                      decoration: const InputDecoration(
                        labelText: 'Vert. Offset',
                        labelStyle: TextStyle(fontSize: 15),
                        floatingLabelStyle: TextStyle(fontSize: 14),
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
                      onEditingComplete: _validateInputs,
                      decoration: const InputDecoration(
                        labelText: 'Scale Factor',
                        labelStyle: TextStyle(fontSize: 15),
                        floatingLabelStyle: TextStyle(fontSize: 14),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _inputController4,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onEditingComplete: _validateInputs,
                      decoration: const InputDecoration(
                        labelText: 'Rotation (Deg)',
                        labelStyle: TextStyle(fontSize: 15),
                        floatingLabelStyle: TextStyle(fontSize: 14),
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
                Builder(builder: (context) {
                  final double fullWidth = MediaQuery.of(context).size.width;
                  final bool isPortrait = projectOrientation == 'portrait';
                  final double previewWidth = isPortrait ? fullWidth * 0.8 : fullWidth;
                  final double previewHeight = previewWidth * _canvasHeight! / _canvasWidth!;
                  return Center(
                    child: Stack(
                      children: [
                        Image.memory(
                          _stabilizedImageBytes!,
                          width: previewWidth,
                          height: previewHeight,
                          fit: BoxFit.fill,
                        ),
                        CustomPaint(
                          painter: GridPainterSE(
                              (_rightEyeXGoal! - _leftEyeXGoal!) / (2 * _canvasWidth!),
                              _bothEyesYGoal! / _canvasHeight!,
                              null,
                              null,
                              null,
                              aspectRatio,
                              projectOrientation,
                              hideToolTip: true
                          ),
                          child: SizedBox(
                            width: previewWidth,
                            height: previewHeight,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 88),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildToolbar(context),
    );
  }

  Map<TextEditingController, String> _lastValid = {};

  bool _isWholeNumber(String s) => RegExp(r'^-?\d+$').hasMatch(s);
  bool _isPositiveDecimal(String s) => RegExp(r'^\d+(\.\d+)?$').hasMatch(s) && double.parse(s) > 0;
  bool _isSignedDecimal(String s) => RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s);

  void _showInvalidInputDialog(List<String> fields) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Invalid input'),
          content: Text(
            'Please check these fields:\n• ${fields.join('\n• ')}\n\n'
                'Horiz./Vert. Offset: whole numbers like -10 or 25\n'
                'Scale Factor: positive numbers like 1 or 2.5\n'
                'Rotation: any number like -1.5 or 30',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _validateInputs() {
    FocusScope.of(context).unfocus();
    final List<String> invalid = [];
    if (!_isWholeNumber(_inputController1.text)) invalid.add('Horiz. Offset');
    if (!_isWholeNumber(_inputController2.text)) invalid.add('Vert. Offset');
    if (!_isPositiveDecimal(_inputController3.text)) invalid.add('Scale Factor');
    if (!_isSignedDecimal(_inputController4.text)) invalid.add('Rotation');
    if (invalid.isNotEmpty) {
      _showInvalidInputDialog(invalid);
    }
  }

  Future<void> processRequest(double? translateX, double? translateY, double? scaleFactor, double? rotationDegrees) async {
    final int requestId = ++_currentRequestId;
    setState(() {
      _isProcessing = true;
    });
    try {
      final ui.Image? img = await StabUtils.loadImageFromFile(File(rawPhotoPath));
      if (img == null) {
        return;
      }

      final Uint8List? imageBytesStabilized = await faceStabilizer.generateStabilizedImageBytes(
        img,
        rotationDegrees,
        scaleFactor,
        translateX,
        translateY,
      );
      if (imageBytesStabilized == null) {
        img.dispose();
        return;
      }

      if (requestId != _currentRequestId) {
        img.dispose();
        return;
      }

      setState(() {
        _stabilizedImageBytes = imageBytesStabilized;
      });

      final String projectOrientation =
      await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
      final String stabilizedPhotoPath =
      await StabUtils.getStabilizedImagePath(rawPhotoPath, widget.projectId, projectOrientation);
      final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(stabilizedPhotoPath);

      final File stabImageFile = File(stabilizedPhotoPath);
      final File stabThumbFile = File(stabThumbPath);
      if (await stabImageFile.exists()) await stabImageFile.delete();
      if (await stabThumbFile.exists()) await stabThumbFile.delete();

      await faceStabilizer.saveStabilizedImage(
        imageBytesStabilized,
        rawPhotoPath,
        stabilizedPhotoPath,
        0.0,
      );
      await faceStabilizer.createStabThumbnail(stabilizedPhotoPath.replaceAll('.jpg', '.png'));

      if (requestId != _currentRequestId) {
        img.dispose();
        return;
      }

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
        _lastMult = scaleFactor == null ? null : scaleFactor / _baseScale;
        _lastRot = rotationDegrees;
      });

      img.dispose();
    } catch (_) {} finally {
      if (mounted && requestId == _currentRequestId) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _adjustScale(double delta) {
    double mult = double.tryParse(_inputController3.text) ?? 1.0;
    mult += delta;
    if (mult < 0.01) mult = 0.01;
    _inputController3.text = mult.toStringAsFixed(2);
  }

  void _onParamChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
      double mult = double.tryParse(_inputController3.text) ?? 1.0;
      double? rot = double.tryParse(_inputController4.text);
      double? sc = _baseScale * mult;

      const double tolerance = 0.0001;
      bool changed = (_lastTx == null || (_lastTx! - (tx ?? 0)).abs() > tolerance) ||
          (_lastTy == null || (_lastTy! - (ty ?? 0)).abs() > tolerance) ||
          (_lastMult == null || (_lastMult! - mult).abs() > tolerance) ||
          (_lastRot == null || (_lastRot! - (rot ?? 0)).abs() > tolerance);

      if (changed) {
        processRequest(tx, ty, sc, rot);
      }
    });
  }

  void _adjustOffsets({int dx = 0, int dy = 0}) {
    double tx = double.tryParse(_inputController1.text) ?? 0;
    double ty = double.tryParse(_inputController2.text) ?? 0;

    tx += dx;
    ty += dy;

    _inputController1.text = tx.toString();
    _inputController2.text = ty.toString();
  }

  Widget _buildToolbar(BuildContext context) {
    final Color barColor = Colors.black.withAlpha((0.75 * 255).round());
    return ColoredBox(
      color: barColor,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.remove),       onPressed: () => _adjustScale(-0.01)),
              IconButton(icon: const Icon(Icons.add),          onPressed: () => _adjustScale(0.01)),
              IconButton(icon: const Icon(Icons.arrow_left),   onPressed: () => _adjustOffsets(dx: -1)),
              IconButton(icon: const Icon(Icons.arrow_right),  onPressed: () => _adjustOffsets(dx: 1)),
              IconButton(icon: const Icon(Icons.arrow_upward), onPressed: () => _adjustOffsets(dy: 1)),
              IconButton(icon: const Icon(Icons.arrow_downward), onPressed: () => _adjustOffsets(dy: -1)),
            ],
          ),
        ),
      ),
    );
  }
}