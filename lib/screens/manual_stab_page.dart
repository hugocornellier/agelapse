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
import '../widgets/transform_tool/transform_tool_exports.dart';

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
  bool _updatingFromTextField = false;
  DateTime? _lastApplyAt;
  final Duration _applyThrottle = const Duration(milliseconds: 140);
  final Duration _repeatInterval = const Duration(milliseconds: 60);

  // Transform tool controller
  TransformController? _transformController;
  int? _rawImageHeight;

  // Save/unsaved state management
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _showCheckmark = false;
  Timer? _checkmarkTimer;

  // Saved values (last committed to database)
  double _savedTx = 0;
  double _savedTy = 0;
  double _savedMult = 1;
  double _savedRot = 0;

  // Controls section collapsed state
  bool _controlsExpanded = true;

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
    _checkmarkTimer?.cancel();
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
    _transformController?.dispose();
    super.dispose();
  }

  Future<void> init() async {
    projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    String resolution = await SettingsUtil.loadVideoResolution(
      widget.projectId.toString(),
    );
    aspectRatio = await SettingsUtil.loadAspectRatio(
      widget.projectId.toString(),
    );

    final dims = StabUtils.getOutputDimensions(
      resolution,
      aspectRatio,
      projectOrientation,
    );
    canvasWidth = dims!.$1;
    canvasHeight = dims.$2;

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
      final dims = await ImageUtils.getImageDimensionsInIsolate(
        _rawImageBytes!,
      );
      if (dims != null) {
        _rawImageWidth = dims.$1;
        _rawImageHeight = dims.$2;
        final double defaultScale = canvasWidth / _rawImageWidth!.toDouble();
        _baseScale = defaultScale;
        _inputController3.text = '1';
      }
    }

    _faceStabilizer = FaceStabilizer(
      widget.projectId,
      () => LogService.instance.log("Test"),
    );
    await _faceStabilizer!.init();

    await _loadSavedTransformAndBootPreview();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_hasUnsavedChanges) {
          bool? saveChanges = await _showUnsavedChangesDialog();

          if (saveChanges == true) {
            await _saveChanges();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          } else if (saveChanges == false) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
          // null = user cancelled, do nothing
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.settingsBackground,
        appBar: _buildAppBar(),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double minPreviewHeight = 300;
              const double controlsEstimatedHeight = 220; // controls + spacing
              final double availableForPreview = constraints.maxHeight -
                  32 -
                  controlsEstimatedHeight; // 32 for padding

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
      ),
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
        onTap: () {
          if (_hasUnsavedChanges) {
            _showUnsavedChangesDialog().then((saveChanges) async {
              if (saveChanges == true) {
                await _saveChanges();
                if (mounted) Navigator.of(context).pop();
              } else if (saveChanges == false) {
                if (mounted) Navigator.of(context).pop();
              }
            });
          } else {
            Navigator.pop(context);
          }
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: const Icon(
            Icons.arrow_back,
            color: AppColors.settingsTextPrimary,
            size: 20,
          ),
        ),
      ),
      actions: [
        // Help button
        GestureDetector(
          onTap: _showHelpDialog,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.settingsTextSecondary,
              size: 20,
            ),
          ),
        ),
        // Reset button (only when unsaved changes exist)
        if (_hasUnsavedChanges)
          GestureDetector(
            onTap: _isSaving
                ? null
                : () async {
                    final bool? shouldReset = await _showResetConfirmDialog();
                    if (shouldReset == true) {
                      await _resetChanges();
                    }
                  },
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.settingsCardBorder.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.settingsCardBorder,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.restore_rounded,
                color: AppColors.settingsTextSecondary,
                size: 22,
              ),
            ),
          ),
        // Save button (only when unsaved changes exist)
        if (_hasUnsavedChanges)
          Builder(
            builder: (context) {
              final isWide = MediaQuery.of(context).size.width > 600;
              return GestureDetector(
                onTap: _isSaving ? null : _saveChanges,
                child: Container(
                  height: 44,
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 11),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _showCheckmark
                        ? Colors.green.withValues(alpha: 0.15)
                        : AppColors.settingsAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _showCheckmark
                          ? Colors.green.withValues(alpha: 0.3)
                          : AppColors.settingsAccent.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.settingsAccent,
                          ),
                        )
                      else
                        Icon(
                          _showCheckmark
                              ? Icons.check_circle_rounded
                              : Icons.save_rounded,
                          color: _showCheckmark
                              ? Colors.green
                              : AppColors.settingsAccent,
                          size: 22,
                        ),
                      if (isWide) ...[
                        const SizedBox(width: 8),
                        Text(
                          _showCheckmark ? 'Saved' : 'Save Changes',
                          style: TextStyle(
                            color: _showCheckmark
                                ? Colors.green
                                : AppColors.settingsAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.settingsDivider),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        // Collapsible header
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _controlsExpanded = !_controlsExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
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
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _controlsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.settingsTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Collapsible content
        AnimatedCrossFade(
          firstChild: LayoutBuilder(
            builder: (context, constraints) {
              // Use 4 columns when width > 500px (desktop/tablet landscape)
              final bool useWideLayout = constraints.maxWidth > 500;

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.settingsCardBorder, width: 1),
                ),
                padding: const EdgeInsets.all(16),
                child: useWideLayout
                    ? Row(
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
                          const SizedBox(width: 12),
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
                      )
                    : Column(
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
              );
            },
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _controlsExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
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
            Icon(icon, size: 14, color: AppColors.settingsTextTertiary),
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
              decimal: true,
              signed: true,
            ),
            onEditingComplete: _validateInputs,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.settingsTextPrimary,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
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
    // Wait for all required data
    if (_rawImageBytes == null ||
        _rawImageWidth == null ||
        _rawImageHeight == null ||
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
              final double availableWidth = (constraints.maxWidth - 24).clamp(
                0.0,
                double.infinity,
              );
              final double availableHeight = (constraints.maxHeight - 24).clamp(
                0.0,
                double.infinity,
              );

              if (availableWidth == 0 || availableHeight == 0) {
                return const SizedBox.shrink();
              }

              double previewWidth = availableWidth;
              double previewHeight = previewWidth * aspectRatioValue;

              if (previewHeight > availableHeight) {
                previewHeight = availableHeight;
                previewWidth = previewHeight / aspectRatioValue;
              }

              // Initialize transform controller with OUTPUT dimensions (not preview)
              _initTransformControllerIfNeeded();

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
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _canvasWidth!.toDouble(),
                        height: _canvasHeight!.toDouble(),
                        child: Stack(
                          children: [
                            // TransformTool at OUTPUT dimensions
                            Positioned.fill(
                              child: TransformTool(
                                imageBytes: _rawImageBytes!,
                                canvasSize: Size(_canvasWidth!.toDouble(),
                                    _canvasHeight!.toDouble()),
                                imageSize: Size(_rawImageWidth!.toDouble(),
                                    _rawImageHeight!.toDouble()),
                                baseScale: _baseScale,
                                controller: _transformController,
                                onChanged: _onTransformChanged,
                                onChangeEnd: _onTransformChangeEnd,
                                showRotationHandle: true,
                                maintainAspectRatio: true,
                              ),
                            ),
                            // Grid overlay - scales together with TransformTool
                            // IgnorePointer lets events pass through to TransformTool
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: GridPainterSE(
                                    (_rightEyeXGoal! - _leftEyeXGoal!) /
                                        (2 * _canvasWidth!),
                                    _bothEyesYGoal! / _canvasHeight!,
                                    null,
                                    null,
                                    null,
                                    aspectRatio,
                                    projectOrientation,
                                    hideToolTip: true,
                                    hideCorners: true,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  void _initTransformControllerIfNeeded() {
    if (_transformController != null) return;

    final tx = double.tryParse(_inputController1.text) ?? 0;
    final ty = double.tryParse(_inputController2.text) ?? 0;
    final mult = double.tryParse(_inputController3.text) ?? 1;
    final rot = double.tryParse(_inputController4.text) ?? 0;

    // Use OUTPUT dimensions so coordinates match database/OpenCV
    final outputWidth = _canvasWidth!.toDouble();
    final outputHeight = _canvasHeight!.toDouble();

    final initialState = TransformState(
      translateX: tx,
      translateY: ty,
      scale: mult,
      rotation: rot,
      pivot: Offset(outputWidth / 2, outputHeight / 2),
      imageSize: Size(_rawImageWidth!.toDouble(), _rawImageHeight!.toDouble()),
      canvasSize: Size(outputWidth, outputHeight),
      baseScale: _baseScale,
    );

    _transformController = TransformController(
      initialState: initialState,
      baseScale: _baseScale,
      maintainAspectRatio: true,
    );

    _transformController!.addListener(_onTransformControllerChanged);
  }

  void _onTransformControllerChanged() {
    if (_transformController == null) return;
    // Skip updating text fields if the change came from text field input
    if (_updatingFromTextField) return;

    final state = _transformController!.state;

    // Update text fields (suppress listener to prevent loop)
    _suppressListener = true;
    _inputController1.text = state.translateX.round().toString();
    _inputController2.text = state.translateY.round().toString();
    _inputController3.text = state.scale.toStringAsFixed(2);
    _inputController4.text = state.rotation.toStringAsFixed(2);
    _suppressListener = false;
  }

  void _onTransformChanged(TransformState state) {
    // Called during drag - throttled preview update
    final now = DateTime.now();
    if (_lastApplyAt == null ||
        now.difference(_lastApplyAt!) >= _applyThrottle) {
      _lastApplyAt = now;
      processRequest(
        state.translateX,
        state.translateY,
        state.scale * _baseScale,
        state.rotation,
        save: false,
      );
    }
  }

  void _onTransformChangeEnd(TransformState state) {
    // Called when gesture ends - update preview (no autosave)
    processRequest(
      state.translateX,
      state.translateY,
      state.scale * _baseScale,
      state.rotation,
      save: false,
    );
    _checkForUnsavedChanges();
  }

  void _checkForUnsavedChanges() {
    final tx = double.tryParse(_inputController1.text) ?? 0;
    final ty = double.tryParse(_inputController2.text) ?? 0;
    final mult = double.tryParse(_inputController3.text) ?? 1;
    final rot = double.tryParse(_inputController4.text) ?? 0;

    const double tolerance = 0.0001;
    final bool hasChanges = (tx - _savedTx).abs() > tolerance ||
        (ty - _savedTy).abs() > tolerance ||
        (mult - _savedMult).abs() > tolerance ||
        (rot - _savedRot).abs() > tolerance;

    if (hasChanges != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = hasChanges);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      final tx = double.tryParse(_inputController1.text) ?? 0;
      final ty = double.tryParse(_inputController2.text) ?? 0;
      final mult = double.tryParse(_inputController3.text) ?? 1;
      final rot = double.tryParse(_inputController4.text) ?? 0;
      final sc = mult * _baseScale;

      // Save via processRequest
      await processRequest(tx, ty, sc, rot, save: true);

      // Update saved state
      _savedTx = tx;
      _savedTy = ty;
      _savedMult = mult;
      _savedRot = rot;

      setState(() {
        _isSaving = false;
        _hasUnsavedChanges = false;
        _showCheckmark = true;
      });

      // Hide checkmark after 2 seconds
      _checkmarkTimer?.cancel();
      _checkmarkTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showCheckmark = false);
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save changes')),
        );
      }
    }
  }

  Future<bool?> _showUnsavedChangesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.save_outlined,
                color: AppColors.settingsAccent,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Unsaved Changes',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Text(
            'You have unsaved changes. Do you want to save them before leaving?',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Discard',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.settingsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showResetConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.restore_rounded,
                color: AppColors.orange,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Reset Changes?',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Text(
            'This will revert all changes to the last saved state.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text(
                'Reset',
                style: TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetChanges() async {
    // Restore saved values to text controllers
    _suppressListener = true;
    _inputController1.text = _savedTx.round().toString();
    _inputController2.text = _savedTy.round().toString();
    _inputController3.text = _savedMult.toStringAsFixed(2);
    _inputController4.text = _savedRot.toStringAsFixed(2);
    _suppressListener = false;

    // Update transform controller
    _transformController?.setTransform(
      translateX: _savedTx,
      translateY: _savedTy,
      scale: _savedMult,
      rotation: _savedRot,
    );

    // Regenerate preview
    await processRequest(
      _savedTx,
      _savedTy,
      _savedMult * _baseScale,
      _savedRot,
      save: false,
    );

    setState(() => _hasUnsavedChanges = false);
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
    final Map<String, dynamic>? row = await DB.instance.getPhotoByTimestamp(
      timestamp,
      widget.projectId,
    );
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

      // Store as saved values (for reset/unsaved detection)
      _savedTx = tx;
      _savedTy = ty;
      _savedMult = mult;
      _savedRot = rot;
      _hasUnsavedChanges = false;
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

  Future<void> processRequest(
    double? translateX,
    double? translateY,
    double? scaleFactor,
    double? rotationDegrees, {
    bool save = false,
  }) async {
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

      if (save && _faceStabilizer != null) {
        final String projectOrientation =
            await SettingsUtil.loadProjectOrientation(
          widget.projectId.toString(),
        );
        final String stabilizedPhotoPath =
            await StabUtils.getStabilizedImagePath(
          rawPhotoPath,
          widget.projectId,
          projectOrientation,
        );
        final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(
          stabilizedPhotoPath,
        );

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
          stabilizedPhotoPath.replaceAll('.jpg', '.png'),
        );
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
        // Update the transform controller so TransformTool re-renders
        // Use flag to prevent _onTransformControllerChanged from overwriting text fields
        _updatingFromTextField = true;
        _transformController?.setTransform(
          translateX: tx ?? 0,
          translateY: ty ?? 0,
          scale: mult,
          rotation: rot ?? 0,
        );
        _updatingFromTextField = false;
        processRequest(tx, ty, sc, rot, save: false);
        _checkForUnsavedChanges();
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

    double mult = double.tryParse(_inputController3.text) ?? 1.0;
    double? rot = double.tryParse(_inputController4.text);

    // Update transform controller so TransformTool re-renders immediately
    // Use flag to prevent _onTransformControllerChanged from overwriting text fields
    _updatingFromTextField = true;
    _transformController?.setTransform(
      translateX: tx,
      translateY: ty,
      scale: mult,
      rotation: rot ?? 0,
    );
    _updatingFromTextField = false;
    _checkForUnsavedChanges();

    final now = DateTime.now();
    if (_lastApplyAt == null ||
        now.difference(_lastApplyAt!) >= _applyThrottle) {
      _lastApplyAt = now;
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
      // Update transform controller so TransformTool re-renders
      // Use flag to prevent _onTransformControllerChanged from overwriting text fields
      _updatingFromTextField = true;
      _transformController?.setTransform(
        translateX: tx ?? 0,
        translateY: ty ?? 0,
        scale: mult,
        rotation: rot ?? 0,
      );
      _updatingFromTextField = false;
      processRequest(tx, ty, sc, rot, save: false);
      _checkForUnsavedChanges();
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
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
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
          top: BorderSide(color: AppColors.settingsDivider, width: 1),
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
