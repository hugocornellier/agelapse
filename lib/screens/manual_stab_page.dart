import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/face_stabilizer.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/image_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../widgets/grid_painter_se.dart';

class ManualStabilizationPage extends StatefulWidget {
  final String imagePath;
  final int projectId;

  const ManualStabilizationPage({
    super.key,
    required this.imagePath,
    required this.projectId,
  });

  @override
  ManualStabilizationPageState createState() => ManualStabilizationPageState();
}

class ManualStabilizationPageState extends State<ManualStabilizationPage> {
  String rawPhotoPath = "";
  Uint8List? _stabilizedImageBytes;
  FaceStabilizer? _faceStabilizer;
  int? _canvasWidth;
  int? _canvasHeight;
  double? _leftEyeXGoal;
  double? _rightEyeXGoal;
  int _currentRequestId = 0;
  double? _bothEyesYGoal;
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
  Uint8List? _rawImageBytes;
  int? _rawImageWidth;

  final Map<String, Timer?> _holdTimers = {};
  final Map<String, bool> _recentlyHeld = {};
  bool _suppressListener = false;
  DateTime? _lastApplyAt;
  final Duration _applyThrottle = const Duration(milliseconds: 140);
  final Duration _repeatInterval = const Duration(milliseconds: 60);

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
    for (final t in _holdTimers.values) {
      t?.cancel();
    }
    _holdTimers.clear();
    _inputController1.removeListener(_onParamChanged);
    _inputController2.removeListener(_onParamChanged);
    _inputController3.removeListener(_onParamChanged);
    _inputController4.removeListener(_onParamChanged);
    _inputController1.dispose();
    _inputController2.dispose();
    _inputController3.dispose();
    _inputController4.dispose();
    _faceStabilizer?.dispose();
    super.dispose();
  }

  Future<void> init() async {
    projectOrientation =
        await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    String resolution =
        await SettingsUtil.loadVideoResolution(widget.projectId.toString());
    aspectRatio =
        await SettingsUtil.loadAspectRatio(widget.projectId.toString());
    double? aspectRatioDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);

    final double? shortSideDouble = StabUtils.getShortSide(resolution);
    final int longSide = (aspectRatioDecimal! * shortSideDouble!).toInt();
    final int shortSide = shortSideDouble.toInt();

    canvasWidth = projectOrientation == "landscape" ? longSide : shortSide;
    canvasHeight = projectOrientation == "landscape" ? shortSide : longSide;

    String localRawPath;
    if (widget.imagePath.contains('/stabilized/') ||
        widget.imagePath.contains('\\stabilized\\')) {
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

    final File rawFile = File(localRawPath);
    if (await rawFile.exists()) {
      _rawImageBytes = await rawFile.readAsBytes();
      // Get dimensions in isolate to avoid blocking UI
      final dims =
          await ImageUtils.getImageDimensionsInIsolate(_rawImageBytes!);
      if (dims != null) {
        _rawImageWidth = dims.$1;
        final double defaultScale = canvasWidth / _rawImageWidth!.toDouble();
        _baseScale = defaultScale;
        _inputController3.text = '1';
      }
    }

    _faceStabilizer =
        FaceStabilizer(widget.projectId, () => LogService.instance.log("Test"));
    await _faceStabilizer!.init();

    await _loadSavedTransformAndBootPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.settingsBackground,
      appBar: _buildAppBar(),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double minPreviewHeight = 300;
            const double controlsEstimatedHeight = 220; // controls + spacing
            final double availableForPreview = constraints.maxHeight - 32 - controlsEstimatedHeight; // 32 for padding

            if (availableForPreview >= minPreviewHeight) {
              // Enough space - use Expanded layout
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControlsSection(),
                    const SizedBox(height: 20),
                    Expanded(child: _buildPreviewSection()),
                  ],
                ),
              );
            } else {
              // Not enough space - use scrollable layout with min height
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControlsSection(),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: minPreviewHeight,
                      child: _buildPreviewSection(),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
      bottomNavigationBar: _buildToolbar(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: AppColors.settingsBackground,
      title: const Text(
        'Manual Stabilization',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.arrow_back,
            color: AppColors.settingsTextPrimary,
            size: 20,
          ),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: _showHelpDialog,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.settingsCardBorder,
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.settingsTextSecondary,
              size: 20,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: AppColors.settingsDivider,
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.settingsAccent,
              size: 24,
            ),
            SizedBox(width: 12),
            Text(
              'Quick Guide',
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Goal: Center each pupil on its vertical line and place both pupils exactly on the horizontal line.\n\n'
            'Horiz. Offset (whole number, +/-)\nShifts the image left/right. Increase to move the face right, decrease to move left.\n\n'
            'Vert. Offset (whole number, +/-)\nShifts the image up/down. Increase to move the face up, decrease to move down.\n\n'
            'Scale Factor (positive decimal)\nZooms in or out. Values > 1 enlarge, values between 0 and 1 shrink.\n\n'
            'Rotation (decimal, +/-)\nTilts the image. Positive values rotate clockwise, negative counter-clockwise.\n\n'
            'Use the toolbar arrows or type exact numbers. Keep adjusting until the pupils touch all three guides.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: AppColors.settingsAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: AppColors.settingsTextSecondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'TRANSFORM CONTROLS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      controller: _inputController1,
                      label: 'Horiz. Offset',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInputField(
                      controller: _inputController2,
                      label: 'Vert. Offset',
                      icon: Icons.swap_vert_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      controller: _inputController3,
                      label: 'Scale Factor',
                      icon: Icons.zoom_in_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInputField(
                      controller: _inputController4,
                      label: 'Rotation',
                      icon: Icons.rotate_right_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: AppColors.settingsTextTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.settingsTextTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.settingsCardBorder,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            onEditingComplete: _validateInputs,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.settingsTextPrimary,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: InputBorder.none,
              hintText: '0',
              hintStyle: TextStyle(
                color: AppColors.settingsTextTertiary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    if (_stabilizedImageBytes == null ||
        _canvasWidth == null ||
        _canvasHeight == null ||
        _leftEyeXGoal == null ||
        _rightEyeXGoal == null ||
        _bothEyesYGoal == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreviewHeader(),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.settingsCardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.settingsCardBorder,
                  width: 1,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.settingsAccent,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading preview...',
                      style: TextStyle(
                        color: AppColors.settingsTextSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double aspectRatioValue = _canvasHeight! / _canvasWidth!;
              final double availableWidth = (constraints.maxWidth - 24).clamp(0.0, double.infinity);
              final double availableHeight = (constraints.maxHeight - 24).clamp(0.0, double.infinity);

              if (availableWidth == 0 || availableHeight == 0) {
                return const SizedBox.shrink();
              }

              double previewWidth = availableWidth;
              double previewHeight = previewWidth * aspectRatioValue;

              if (previewHeight > availableHeight) {
                previewHeight = availableHeight;
                previewWidth = previewHeight / aspectRatioValue;
              }

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.settingsCardBorder,
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
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
                              (_rightEyeXGoal! - _leftEyeXGoal!) /
                                  (2 * _canvasWidth!),
                              _bothEyesYGoal! / _canvasHeight!,
                              null,
                              null,
                              null,
                              aspectRatio,
                              projectOrientation,
                              hideToolTip: true),
                          child: SizedBox(
                            width: previewWidth,
                            height: previewHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(
            Icons.preview_rounded,
            size: 18,
            color: AppColors.settingsTextSecondary,
          ),
          const SizedBox(width: 8),
          const Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_isProcessing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.settingsAccent,
              ),
            ),
        ],
      ),
    );
  }

  bool _isWholeNumber(String s) => RegExp(r'^-?\d+$').hasMatch(s);
  bool _isPositiveDecimal(String s) =>
      RegExp(r'^\d+(\.\d+)?$').hasMatch(s) && double.parse(s) > 0;
  bool _isSignedDecimal(String s) => RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s);

  void _showInvalidInputDialog(List<String> fields) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.orange,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Invalid Input',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Please check these fields:\n\n${fields.map((f) => '• $f').join('\n')}\n\n'
            'Horiz./Vert. Offset: whole numbers like -10 or 25\n'
            'Scale Factor: positive numbers like 1 or 2.5\n'
            'Rotation: any number like -1.5 or 30',
            style: const TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: AppColors.settingsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSavedTransformAndBootPreview() async {
    final String timestamp = p.basenameWithoutExtension(rawPhotoPath);
    final Map<String, dynamic>? row =
        await DB.instance.getPhotoByTimestamp(timestamp, widget.projectId);
    final String prefix = DB.instance.getStabilizedColumn(projectOrientation);

    double tx = 0;
    double ty = 0;
    double rot = 0;
    double sc = _baseScale;

    if (row != null) {
      final dynamic vTx = row['${prefix}TranslateX'];
      final dynamic vTy = row['${prefix}TranslateY'];
      final dynamic vRot = row['${prefix}RotationDegrees'];
      final dynamic vSc = row['${prefix}ScaleFactor'];
      if (vTx != null) tx = (vTx as num).toDouble();
      if (vTy != null) ty = (vTy as num).toDouble();
      if (vRot != null) rot = (vRot as num).toDouble();
      if (vSc != null) sc = (vSc as num).toDouble();
    }

    final double mult = sc / _baseScale;

    _suppressListener = true;
    _inputController1.text = tx.round().toString();
    _inputController2.text = ty.round().toString();
    _inputController3.text = mult.toStringAsFixed(2);
    _inputController4.text = rot.toStringAsFixed(2);
    _suppressListener = false;

    await processRequest(tx, ty, sc, rot, save: false);

    setState(() {
      _lastTx = tx;
      _lastTy = ty;
      _lastMult = mult;
      _lastRot = rot;
    });
  }

  void _validateInputs() {
    FocusScope.of(context).unfocus();
    final List<String> invalid = [];
    if (!_isWholeNumber(_inputController1.text)) invalid.add('Horiz. Offset');
    if (!_isWholeNumber(_inputController2.text)) invalid.add('Vert. Offset');
    if (!_isPositiveDecimal(_inputController3.text)) {
      invalid.add('Scale Factor');
    }
    if (!_isSignedDecimal(_inputController4.text)) invalid.add('Rotation');
    if (invalid.isNotEmpty) {
      _showInvalidInputDialog(invalid);
    }
  }

  Future<void> processRequest(double? translateX, double? translateY,
      double? scaleFactor, double? rotationDegrees,
      {bool save = false}) async {
    final int requestId = ++_currentRequestId;
    if (mounted) {
      setState(() {
        _isProcessing = true;
      });
    }
    try {
      if (_rawImageBytes == null) {
        return;
      }

      final Uint8List? imageBytesStabilized =
          await StabUtils.generateStabilizedImageBytesCVAsync(
        _rawImageBytes!,
        rotationDegrees ?? 0,
        scaleFactor ?? 1,
        translateX ?? 0,
        translateY ?? 0,
        this.canvasWidth,
        this.canvasHeight,
      );
      if (imageBytesStabilized == null) {
        return;
      }

      if (requestId != _currentRequestId || !mounted) {
        return;
      }

      setState(() {
        _stabilizedImageBytes = imageBytesStabilized;
      });

      if (save && _faceStabilizer != null) {
        final String projectOrientation =
            await SettingsUtil.loadProjectOrientation(
                widget.projectId.toString());
        final String stabilizedPhotoPath =
            await StabUtils.getStabilizedImagePath(
                rawPhotoPath, widget.projectId, projectOrientation);
        final String stabThumbPath =
            FaceStabilizer.getStabThumbnailPath(stabilizedPhotoPath);

        final File stabImageFile = File(stabilizedPhotoPath);
        final File stabThumbFile = File(stabThumbPath);
        if (await stabImageFile.exists()) await stabImageFile.delete();
        if (await stabThumbFile.exists()) await stabThumbFile.delete();

        await _faceStabilizer!.saveStabilizedImage(
          imageBytesStabilized,
          rawPhotoPath,
          stabilizedPhotoPath,
          0.0,
          translateX: translateX,
          translateY: translateY,
          rotationDegrees: rotationDegrees,
          scaleFactor: scaleFactor,
        );
        await _faceStabilizer!.createStabThumbnail(
            stabilizedPhotoPath.replaceAll('.jpg', '.png'));
      }

      if (requestId != _currentRequestId ||
          !mounted ||
          _faceStabilizer == null) {
        return;
      }

      final int canvasHeight = _faceStabilizer!.canvasHeight;
      final int canvasWidth = _faceStabilizer!.canvasWidth;
      final double leftEyeXGoal = _faceStabilizer!.leftEyeXGoal;
      final double rightEyeXGoal = _faceStabilizer!.rightEyeXGoal;
      final double bothEyesYGoal = _faceStabilizer!.bothEyesYGoal;

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
    } catch (_) {
    } finally {
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
    _suppressListener = true;
    _inputController3.text = mult.toStringAsFixed(2);
    _suppressListener = false;

    final now = DateTime.now();
    if (_lastApplyAt == null ||
        now.difference(_lastApplyAt!) >= _applyThrottle) {
      _lastApplyAt = now;
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
      double? rot = double.tryParse(_inputController4.text);
      double? sc = _baseScale * mult;
      processRequest(tx, ty, sc, rot);
    }
  }

  void _onParamChanged() {
    if (_suppressListener) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
      double mult = double.tryParse(_inputController3.text) ?? 1.0;
      double? rot = double.tryParse(_inputController4.text);
      double sc = _baseScale * mult;

      const double tolerance = 0.0001;
      bool changed =
          (_lastTx == null || (_lastTx! - (tx ?? 0)).abs() > tolerance) ||
              (_lastTy == null || (_lastTy! - (ty ?? 0)).abs() > tolerance) ||
              (_lastMult == null || (_lastMult! - mult).abs() > tolerance) ||
              (_lastRot == null || (_lastRot! - (rot ?? 0)).abs() > tolerance);

      if (changed) {
        processRequest(tx, ty, sc, rot, save: true);
      }
    });
  }

  void _adjustOffsets({int dx = 0, int dy = 0}) {
    double tx = double.tryParse(_inputController1.text) ?? 0;
    double ty = double.tryParse(_inputController2.text) ?? 0;

    tx += dx;
    ty += dy;

    _suppressListener = true;
    _inputController1.text = tx.toString();
    _inputController2.text = ty.toString();
    _suppressListener = false;

    final now = DateTime.now();
    if (_lastApplyAt == null ||
        now.difference(_lastApplyAt!) >= _applyThrottle) {
      _lastApplyAt = now;
      double mult = double.tryParse(_inputController3.text) ?? 1.0;
      double? rot = double.tryParse(_inputController4.text);
      double? sc = _baseScale * mult;
      processRequest(tx, ty, sc, rot);
    }
  }

  Widget _buildToolbar(BuildContext context) {
    void forceApplyNow() {
      final now = DateTime.now();
      if (_lastApplyAt != null &&
          now.difference(_lastApplyAt!) < const Duration(milliseconds: 50)) {
        return;
      }
      _lastApplyAt = now;
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
      double mult = double.tryParse(_inputController3.text) ?? 1.0;
      double? rot = double.tryParse(_inputController4.text);
      double sc = _baseScale * mult;
      processRequest(tx, ty, sc, rot, save: true);
    }

    void startHold(String key, VoidCallback onTick) {
      _recentlyHeld[key] = false;
      _holdTimers[key]?.cancel();
      _holdTimers[key] = Timer.periodic(_repeatInterval, (t) {
        if (_recentlyHeld[key] == false) {
          _recentlyHeld[key] = true;
        }
        onTick();
      });
    }

    void stopHold(String key) {
      _holdTimers[key]?.cancel();
      _holdTimers.remove(key);
      forceApplyNow();
    }

    Widget buildToolbarButton({
      required String key,
      required IconData icon,
      required VoidCallback onTap,
      required VoidCallback onHold,
      String? label,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => startHold(key, onHold),
        onTapUp: (_) => stopHold(key),
        onTapCancel: () => stopHold(key),
        onPanEnd: (_) => stopHold(key),
        onPanCancel: () => stopHold(key),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          child: IconButton(
            icon: Icon(icon, size: 22),
            color: AppColors.settingsTextPrimary,
            onPressed: () {
              if (_recentlyHeld[key] == true) {
                _recentlyHeld[key] = false;
                return;
              }
              onTap();
              forceApplyNow();
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.settingsBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.settingsDivider,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Scale controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    buildToolbarButton(
                      key: 'scaleMinus',
                      icon: Icons.remove_rounded,
                      onTap: () => _adjustScale(-0.01),
                      onHold: () => _adjustScale(-0.01),
                    ),
                    const SizedBox(width: 4),
                    buildToolbarButton(
                      key: 'scalePlus',
                      icon: Icons.add_rounded,
                      onTap: () => _adjustScale(0.01),
                      onHold: () => _adjustScale(0.01),
                    ),
                  ],
                ),
              ),
              // Direction controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    buildToolbarButton(
                      key: 'left',
                      icon: Icons.arrow_back_rounded,
                      onTap: () => _adjustOffsets(dx: -1),
                      onHold: () => _adjustOffsets(dx: -1),
                    ),
                    const SizedBox(width: 4),
                    buildToolbarButton(
                      key: 'right',
                      icon: Icons.arrow_forward_rounded,
                      onTap: () => _adjustOffsets(dx: 1),
                      onHold: () => _adjustOffsets(dx: 1),
                    ),
                    const SizedBox(width: 4),
                    buildToolbarButton(
                      key: 'up',
                      icon: Icons.arrow_upward_rounded,
                      onTap: () => _adjustOffsets(dy: -1),
                      onHold: () => _adjustOffsets(dy: -1),
                    ),
                    const SizedBox(width: 4),
                    buildToolbarButton(
                      key: 'down',
                      icon: Icons.arrow_downward_rounded,
                      onTap: () => _adjustOffsets(dy: 1),
                      onHold: () => _adjustOffsets(dy: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
