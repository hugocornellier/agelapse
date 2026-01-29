import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/face_stabilizer.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/stabilization_service.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/image_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../widgets/grid_painter_se.dart';
import '../widgets/info_tooltip_icon.dart';
import '../widgets/transform_tool/transform_tool_exports.dart';

class ManualStabilizationPage extends StatefulWidget {
  final String imagePath;
  final int projectId;
  final Future<void> Function()? onSaveComplete;

  const ManualStabilizationPage({
    super.key,
    required this.imagePath,
    required this.projectId,
    this.onSaveComplete,
  });

  @override
  ManualStabilizationPageState createState() => ManualStabilizationPageState();
}

/// Phases of the save operation for visual feedback.
enum _SavePhase { idle, saving, success }

class ManualStabilizationPageState extends State<ManualStabilizationPage>
    with SingleTickerProviderStateMixin {
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
  _SavePhase _savePhase = _SavePhase.idle;
  late AnimationController _checkmarkAnimController;
  late Animation<double> _checkmarkScaleAnim;

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

    // Initialize checkmark animation (pop/bounce effect)
    _checkmarkAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _checkmarkScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 0.9), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _checkmarkAnimController,
      curve: Curves.easeOut,
    ));

    init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _checkmarkAnimController.dispose();
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
    final bool isSaving = _savePhase != _SavePhase.idle;

    return PopScope(
      // Block back navigation during save operation
      canPop: !_hasUnsavedChanges && !isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // Don't allow any navigation during save
        if (isSaving) return;

        if (_hasUnsavedChanges) {
          bool? saveChanges = await _showUnsavedChangesDialog();

          if (saveChanges == true) {
            await _saveChanges();
            // Don't pop here - _saveChanges handles navigation
          } else if (saveChanges == false) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
          // null = user cancelled, do nothing
        }
      },
      child: Stack(
        children: [
          // Main content - absorb pointer during save
          AbsorbPointer(
            absorbing: isSaving,
            child: Scaffold(
              backgroundColor: AppColors.settingsBackground,
              appBar: _buildAppBar(),
              body: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const double minPreviewHeight = 300;
                    const double controlsEstimatedHeight =
                        220; // controls + spacing
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
          ),
          // Save overlay
          if (isSaving) _buildSaveOverlay(),
        ],
      ),
    );
  }

  /// Builds the full-screen save overlay showing "Saving..." or checkmark.
  Widget _buildSaveOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppColors.overlay.withValues(alpha: 0.6),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _savePhase == _SavePhase.saving
                ? _buildSavingIndicator()
                : _buildSuccessCheckmark(),
          ),
        ),
      ),
    );
  }

  /// "Saving..." indicator with spinner.
  Widget _buildSavingIndicator() {
    return Container(
      key: const ValueKey('saving'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.overlay.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.settingsAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Saving...',
            style: TextStyle(
              color: AppColors.settingsTextPrimary,
              fontSize: AppTypography.lg,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  /// Green checkmark badge with pop animation.
  Widget _buildSuccessCheckmark() {
    return AnimatedBuilder(
      key: const ValueKey('success'),
      animation: _checkmarkScaleAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: _checkmarkScaleAnim.value,
          child: child,
        );
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          Icons.check_rounded,
          color: AppColors.textPrimary,
          size: 44,
        ),
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
      title: Text(
        'Manual Stabilization',
        style: TextStyle(
          fontSize: AppTypography.xxl,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Block back during save
            if (_savePhase != _SavePhase.idle) return;

            if (_hasUnsavedChanges) {
              _showUnsavedChangesDialog().then((saveChanges) async {
                if (saveChanges == true) {
                  await _saveChanges();
                  // _saveChanges handles navigation
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
            child: Icon(
              Icons.arrow_back,
              color: AppColors.settingsTextPrimary,
              size: 20,
            ),
          ),
        ),
      ),
      actions: [
        // Help button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _showHelpDialog,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.settingsCardBackground,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.settingsCardBorder, width: 1),
              ),
              child: Icon(
                Icons.help_outline_rounded,
                color: AppColors.settingsTextSecondary,
                size: 20,
              ),
            ),
          ),
        ),
        // Reset button (only when unsaved changes exist and not saving)
        if (_hasUnsavedChanges && _savePhase == _SavePhase.idle)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
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
                child: Icon(
                  Icons.restore_rounded,
                  color: AppColors.settingsTextSecondary,
                  size: 22,
                ),
              ),
            ),
          ),
        // Save button (only when unsaved changes exist and not saving)
        if (_hasUnsavedChanges && _savePhase == _SavePhase.idle)
          Builder(
            builder: (context) {
              final isWide = MediaQuery.of(context).size.width > 600;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _saveChanges,
                  child: Container(
                    height: 44,
                    padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 11),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.settingsAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.settingsAccent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.save_rounded,
                          color: AppColors.settingsAccent,
                          size: 22,
                        ),
                        if (isWide) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Save Changes',
                            style: TextStyle(
                              color: AppColors.settingsAccent,
                              fontSize: AppTypography.md,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
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
        title: Row(
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
                fontSize: AppTypography.xl,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            'Goal: Center each pupil on its vertical line and place both pupils exactly on the horizontal line.\n\n'
            'Horiz. Offset (decimal, +/-)\nShifts the image left/right. Increase to move the face right, decrease to move left.\n\n'
            'Vert. Offset (decimal, +/-)\nShifts the image up/down. Increase to move the face up, decrease to move down.\n\n'
            'Scale Factor (positive decimal)\nZooms in or out. Values > 1 enlarge, values between 0 and 1 shrink.\n\n'
            'Rotation (decimal, +/-)\nTilts the image. Positive values rotate clockwise, negative counter-clockwise.\n\n'
            'Use the toolbar arrows or type exact numbers. Keep adjusting until the pupils touch all three guides.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: AppTypography.md,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
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
                  Text(
                    'TRANSFORM CONTROLS',
                    style: TextStyle(
                      fontSize: AppTypography.sm,
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
                              tooltip:
                                  'Shifts image left/right. Positive values move the face right.',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInputField(
                              controller: _inputController2,
                              label: 'Vert. Offset',
                              icon: Icons.swap_vert_rounded,
                              tooltip:
                                  'Shifts image up/down. Positive values move the face down.',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInputField(
                              controller: _inputController3,
                              label: 'Scale Factor',
                              icon: Icons.zoom_in_rounded,
                              tooltip:
                                  'Zoom level. Values greater than 1 enlarge, less than 1 shrink.',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInputField(
                              controller: _inputController4,
                              label: 'Rotation',
                              icon: Icons.rotate_right_rounded,
                              tooltip:
                                  'Tilt in degrees. Positive values rotate clockwise.',
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
                                  tooltip:
                                      'Shifts image left/right. Positive values move the face right.',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInputField(
                                  controller: _inputController2,
                                  label: 'Vert. Offset',
                                  icon: Icons.swap_vert_rounded,
                                  tooltip:
                                      'Shifts image up/down. Positive values move the face down.',
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
                                  tooltip:
                                      'Zoom level. Values greater than 1 enlarge, less than 1 shrink.',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInputField(
                                  controller: _inputController4,
                                  label: 'Rotation',
                                  icon: Icons.rotate_right_rounded,
                                  tooltip:
                                      'Tilt in degrees. Positive values rotate clockwise.',
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
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.settingsTextTertiary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  color: AppColors.settingsTextTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (tooltip != null) InfoTooltipIcon(content: tooltip),
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
            style: TextStyle(
              fontSize: AppTypography.lg,
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
              child: Center(
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
                        fontSize: AppTypography.md,
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

              // Calculate display scale for counter-scaling handle sizes
              // This ensures handles appear consistent regardless of resolution
              final displayScale = previewWidth / _canvasWidth!.toDouble();

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
                  // SizedBox with calculated dimensions forces FittedBox to
                  // expand and fill available space (scales UP, not just down)
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
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
                                  displayScale: displayScale,
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
    _inputController1.text = state.translateX.toStringAsFixed(1);
    _inputController2.text = state.translateY.toStringAsFixed(1);
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
    // Phase 1: Show "Saving..." overlay
    setState(() => _savePhase = _SavePhase.saving);

    // Track minimum display time for "Saving..." (0.5s)
    final minSavingDisplayFuture =
        Future.delayed(const Duration(milliseconds: 500));

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
      _hasUnsavedChanges = false;

      // Notify gallery to reload with updated images
      await widget.onSaveComplete?.call();

      // Trigger auto-compile video check (mirrors retry stabilization behavior)
      await DB.instance.setNewVideoNeeded(widget.projectId);

      // If stabilization batch is already active, the flag is enough - video will
      // compile when batch finishes. Otherwise, trigger compilation directly.
      if (!StabilizationService.instance.isActive) {
        unawaited(
            StabilizationService.instance.startStabilization(widget.projectId));
      }

      // Wait for minimum "Saving..." display time
      await minSavingDisplayFuture;
      if (!mounted) return;

      // Phase 2: Show success checkmark with animation
      _checkmarkAnimController.reset();
      setState(() => _savePhase = _SavePhase.success);
      await _checkmarkAnimController.forward();

      // Brief pause to admire the checkmark
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      // Phase 3: Pop back to gallery
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _savePhase = _SavePhase.idle);
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
          title: Row(
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
                  fontSize: AppTypography.xl,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'You have unsaved changes. Do you want to save them before leaving?',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: AppTypography.md,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Discard',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text(
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
          title: Row(
            children: [
              Icon(
                Icons.restore_rounded,
                color: AppColors.warningMuted,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Reset Changes?',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.xl,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'This will revert all changes to the last saved state.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: AppTypography.md,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text(
                'Reset',
                style: TextStyle(
                  color: AppColors.warningMuted,
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
    _inputController1.text = _savedTx.toStringAsFixed(1);
    _inputController2.text = _savedTy.toStringAsFixed(1);
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
          Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_isProcessing)
            SizedBox(
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
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warningMuted,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Invalid Input',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.xl,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Please check these fields:\n\n${fields.map((f) => '• $f').join('\n')}\n\n'
            'Horiz./Vert. Offset: numbers like -10.5 or 25\n'
            'Scale Factor: positive numbers like 1 or 2.5\n'
            'Rotation: any number like -1.5 or 30',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: AppTypography.md,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
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
    _inputController1.text = tx.toStringAsFixed(1);
    _inputController2.text = ty.toStringAsFixed(1);
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
    if (!_isSignedDecimal(_inputController1.text)) invalid.add('Horiz. Offset');
    if (!_isSignedDecimal(_inputController2.text)) invalid.add('Vert. Offset');
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

        // Clear caches so gallery shows updated images
        FileImage(File(stabilizedPhotoPath)).evict();
        FileImage(File(stabThumbPath)).evict();
        ThumbnailService.instance.clearCache(stabThumbPath);
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
    // Commit to history before making changes (for undo support)
    _transformController?.commitToHistory();

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

  void _adjustRotation(double delta) {
    // Commit to history before making changes (for undo support)
    _transformController?.commitToHistory();

    double rot = double.tryParse(_inputController4.text) ?? 0.0;
    rot += delta;
    _suppressListener = true;
    _inputController4.text = rot.toStringAsFixed(2);
    _suppressListener = false;

    double mult = double.tryParse(_inputController3.text) ?? 1.0;

    // Update transform controller so TransformTool re-renders immediately
    _updatingFromTextField = true;
    _transformController?.setTransform(
      translateX: double.tryParse(_inputController1.text) ?? 0,
      translateY: double.tryParse(_inputController2.text) ?? 0,
      scale: mult,
      rotation: rot,
    );
    _updatingFromTextField = false;
    _checkForUnsavedChanges();

    final now = DateTime.now();
    if (_lastApplyAt == null ||
        now.difference(_lastApplyAt!) >= _applyThrottle) {
      _lastApplyAt = now;
      double? tx = double.tryParse(_inputController1.text);
      double? ty = double.tryParse(_inputController2.text);
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
        // Commit to history before making changes (for undo support)
        _transformController?.commitToHistory();

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

  void _adjustOffsets({double dx = 0, double dy = 0}) {
    // Commit to history before making changes (for undo support)
    _transformController?.commitToHistory();

    double tx = double.tryParse(_inputController1.text) ?? 0;
    double ty = double.tryParse(_inputController2.text) ?? 0;

    tx += dx;
    ty += dy;

    _suppressListener = true;
    _inputController1.text = tx.toStringAsFixed(1);
    _inputController2.text = ty.toStringAsFixed(1);
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
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
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
              // Direction controls (matches Horiz. + Vert. Offset)
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
              // Scale controls (matches Scale Factor)
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
              // Rotation controls (matches Rotation)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    buildToolbarButton(
                      key: 'rotateCCW',
                      icon: Icons.rotate_left_rounded,
                      onTap: () => _adjustRotation(-0.1),
                      onHold: () => _adjustRotation(-0.1),
                    ),
                    const SizedBox(width: 4),
                    buildToolbarButton(
                      key: 'rotateCW',
                      icon: Icons.rotate_right_rounded,
                      onTap: () => _adjustRotation(0.1),
                      onHold: () => _adjustRotation(0.1),
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
