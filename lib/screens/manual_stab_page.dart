import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../services/face_stabilizer.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/menu_bar_service.dart';
import '../services/stabilization_service.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/image_utils.dart';
import '../utils/platform_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/utils.dart';
import '../widgets/collapsible_section_header.dart';
import '../widgets/desktop_icon_button.dart';
import '../widgets/grid_painter_se.dart';
import '../widgets/help_icon_button.dart';
import '../widgets/info_tooltip_icon.dart';
import '../widgets/desktop_page_scaffold.dart';
import '../widgets/quick_guide_dialog.dart';
import '../widgets/transform_tool/transform_tool_exports.dart';
import '../widgets/unsaved_changes_dialog.dart';

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

enum ManualStabOutcome { success, cancelled, invalidImage, saveFailed, stale }

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
  bool _lossless = false;

  // Init error state
  String? _initError;

  // Viewport zoom state (visual only — does NOT affect stabilization params)
  double _viewZoom = 1.0;
  Offset _viewPanOffset = Offset.zero;
  Size? _lastPreviewSize;
  static const double _minViewZoom = 1.0;
  static const double _maxViewZoom = 5.0;
  static const double _viewZoomStep = 0.25;
  static final String _modKey = Platform.isMacOS ? '⌘' : 'Ctrl+';

  void _log(String msg) => LogService.instance.log('[ManualStab] $msg');

  void _adjustViewZoom(double delta) {
    setState(() {
      _viewZoom = (_viewZoom + delta).clamp(_minViewZoom, _maxViewZoom);
      if (_viewZoom == _minViewZoom) {
        _viewPanOffset = Offset.zero;
      } else {
        _viewPanOffset = _clampPanOffset(_viewPanOffset);
      }
    });
  }

  void _resetViewZoom() {
    setState(() {
      _viewZoom = 1.0;
      _viewPanOffset = Offset.zero;
    });
  }

  Offset _clampPanOffset(Offset offset) {
    if (_viewZoom <= 1.0) return Offset.zero;
    if (_lastPreviewSize == null) return offset;
    final maxPanX = _lastPreviewSize!.width * (_viewZoom - 1) / 2;
    final maxPanY = _lastPreviewSize!.height * (_viewZoom - 1) / 2;
    return Offset(
      offset.dx.clamp(-maxPanX, maxPanX),
      offset.dy.clamp(-maxPanY, maxPanY),
    );
  }

  void _handlePreviewPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (isCtrlOrCmd) {
        final delta = event.scrollDelta.dy > 0 ? -_viewZoomStep : _viewZoomStep;
        _adjustViewZoom(delta);
      } else if (_viewZoom > 1.0) {
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        setState(() {
          _viewPanOffset = _clampPanOffset(
            Offset(
              _viewPanOffset.dx - (isShift ? event.scrollDelta.dy : 0),
              _viewPanOffset.dy - (!isShift ? event.scrollDelta.dy : 0),
            ),
          );
        });
      }
    }
  }

  /// Handle trackpad two-finger pan/zoom gestures.
  /// On macOS, these fire as PointerPanZoom events (separate from scroll events).
  void _handleTrackpadPanZoom(PointerPanZoomUpdateEvent event) {
    if (_viewZoom > 1.0) {
      setState(() {
        _viewPanOffset = _clampPanOffset(
          Offset(
            _viewPanOffset.dx + event.panDelta.dx,
            _viewPanOffset.dy + event.panDelta.dy,
          ),
        );
      });
    }
  }

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
    ]).animate(
      CurvedAnimation(
        parent: _checkmarkAnimController,
        curve: Curves.easeOut,
      ),
    );

    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        MenuBarService.instance.registerToolsMenu(
          onZoomIn: () => _adjustViewZoom(_viewZoomStep),
          onZoomOut: () => _adjustViewZoom(-_viewZoomStep),
          onResetZoom: _resetViewZoom,
        );
      });
    }

    init().catchError((e, st) {
      _log('init() FAILED: $e\n$st');
      if (mounted) {
        setState(
          () => _initError = e is FileSystemException
              ? 'Could not load photo file.'
              : 'Failed to load editor.',
        );
      }
    });
  }

  @override
  void dispose() {
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MenuBarService.instance.unregisterToolsMenu();
      });
    }
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
    _log('init() started, imagePath=${widget.imagePath}');
    projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    String resolution = await SettingsUtil.loadVideoResolution(
      widget.projectId.toString(),
    );
    aspectRatio = await SettingsUtil.loadAspectRatio(
      widget.projectId.toString(),
    );
    _lossless = await SettingsUtil.loadLosslessStorage(
      widget.projectId.toString(),
    );

    final dims = StabUtils.getOutputDimensions(
      resolution,
      aspectRatio,
      projectOrientation,
    );
    if (dims == null) {
      throw StateError('Failed to calculate output dimensions');
    }
    canvasWidth = dims.$1;
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
      _log('Raw image loaded: ${_rawImageBytes!.length} bytes');
      final dims = await ImageUtils.getImageDimensionsInIsolate(
        _rawImageBytes!,
      );
      if (dims != null) {
        _rawImageWidth = dims.$1;
        _rawImageHeight = dims.$2;
        final double defaultScale = canvasWidth / _rawImageWidth!.toDouble();
        _baseScale = defaultScale;
        _log(
          'Image dims: ${_rawImageWidth}x$_rawImageHeight, baseScale=$_baseScale, canvas: ${canvasWidth}x$canvasHeight',
        );
        _inputController3.text = '1';
      } else {
        throw StateError('Failed to decode image dimensions');
      }
    } else {
      throw FileSystemException('Raw photo not found', localRawPath);
    }

    _faceStabilizer = FaceStabilizer(
      widget.projectId,
      () => LogService.instance.log("Test"),
    );
    await _faceStabilizer!.init();
    _log('FaceStabilizer initialized');

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
          bool? saveChanges = await showUnsavedChangesDialog(context);

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
      child: _initError != null
          ? _buildInitErrorView()
          : Stack(
              children: [
                // Main content - absorb pointer during save
                AbsorbPointer(absorbing: isSaving, child: _buildPageScaffold()),
                // Save overlay
                if (isSaving) _buildSaveOverlay(),
              ],
            ),
    );
  }

  Widget _buildPageBody() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
            _adjustViewZoom(_viewZoomStep),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
            _adjustViewZoom(-_viewZoomStep),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            _resetViewZoom,
        // Ctrl variants for Windows/Linux
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _adjustViewZoom(_viewZoomStep),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _adjustViewZoom(-_viewZoomStep),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            _resetViewZoom,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: () {
            _log('Page body tapped (unfocusing all fields)');
            FocusScope.of(context).unfocus();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double minPreviewHeight = 300;
              const double controlsEstimatedHeight = 160; // controls + spacing
              final double availableForPreview = constraints.maxHeight -
                  24 -
                  controlsEstimatedHeight; // 24 for padding
              final double previewHeight =
                  availableForPreview >= minPreviewHeight
                      ? availableForPreview
                      : minPreviewHeight;
              final bool shouldEnableScroll =
                  availableForPreview < minPreviewHeight;

              _log(
                'Layout: maxHeight=${constraints.maxHeight}, availableForPreview=$availableForPreview, previewHeight=$previewHeight, mode=stable-scrollable, scrollEnabled=$shouldEnableScroll',
              );

              // Keep one stable widget tree to avoid TextField destruction
              // when keyboard insets change parent constraints.
              return SingleChildScrollView(
                physics: shouldEnableScroll
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControlsSection(),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: previewHeight,
                      child: _buildPreviewSection(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPageScaffold() {
    if (hasCustomTitleBar) {
      return DesktopPageScaffold(
        title: 'Manual Stabilization',
        onBack: _handleBackTap,
        backgroundColor: AppColors.settingsBackground,
        showBottomDivider: true,
        actions: _buildAppBarActions(),
        body: Column(
          children: [
            Expanded(child: _buildPageBody()),
            _buildToolbar(context),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.settingsBackground,
      appBar: _buildAppBar(),
      body: _buildPageBody(),
      bottomNavigationBar: _buildToolbar(context),
    );
  }

  void _handleBackTap() {
    // Block back during save
    if (_savePhase != _SavePhase.idle) return;

    if (_hasUnsavedChanges) {
      showUnsavedChangesDialog(context).then((saveChanges) async {
        if (saveChanges == true) {
          await _saveChanges();
        } else if (saveChanges == false) {
          if (mounted) Navigator.of(context).pop();
        }
      });
    } else {
      Navigator.pop(context);
    }
  }

  List<Widget> _buildAppBarActions() {
    const size = DesktopPageScaffold.navButtonSize;
    const iconSize = DesktopPageScaffold.navIconSize;
    const radius = DesktopPageScaffold.navButtonRadius;

    return [
      // Help button
      HelpIconButton(onTap: _showHelpDialog),
      // Reset button (only when unsaved changes exist and not saving)
      if (_hasUnsavedChanges && _savePhase == _SavePhase.idle)
        DesktopIconButton(
          icon: Icons.restore_rounded,
          onTap: () async {
            final bool? shouldReset = await _showResetConfirmDialog();
            if (shouldReset == true) {
              await _resetChanges();
            }
          },
          iconColor: AppColors.settingsTextSecondary,
          backgroundColor: AppColors.settingsCardBorder.withValues(alpha: 0.5),
          borderColor: AppColors.settingsCardBorder,
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
                  height: size,
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 12 : 8),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: AppColors.settingsAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(radius),
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
                        size: iconSize,
                      ),
                      if (isWide) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Save Changes',
                          style: TextStyle(
                            color: AppColors.settingsAccent,
                            fontSize: AppTypography.sm,
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
    ];
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
        return Transform.scale(scale: _checkmarkScaleAnim.value, child: child);
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

  Widget _buildInitErrorView() {
    return Scaffold(
      backgroundColor: AppColors.settingsBackground,
      appBar: AppBar(
        backgroundColor: AppColors.settingsBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.settingsTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manual Stabilization',
          style: TextStyle(
            fontSize: AppTypography.lg,
            fontWeight: FontWeight.w600,
            color: AppColors.settingsTextPrimary,
          ),
        ),
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.danger, size: 48),
              const SizedBox(height: 16),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.md,
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Go Back',
                  style: TextStyle(
                    color: AppColors.settingsAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    const iconSize = DesktopPageScaffold.navIconSize;
    const radius = DesktopPageScaffold.navButtonRadius;

    return AppBar(
      toolbarHeight: DesktopPageScaffold.navBarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: AppColors.settingsBackground,
      title: Text(
        'Manual Stabilization',
        style: TextStyle(
          fontSize: AppTypography.lg,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _handleBackTap,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            child: Icon(
              Icons.arrow_back,
              color: AppColors.settingsTextPrimary,
              size: iconSize,
            ),
          ),
        ),
      ),
      actions: _buildAppBarActions(),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.settingsDivider),
      ),
    );
  }

  void _showHelpDialog() => showQuickGuideDialog(
        context,
        'Goal: Center each pupil on its vertical line and place both pupils exactly on the horizontal line.\n\n'
        'Horiz. Offset (decimal, +/-)\nShifts the image left/right. Increase to move the face right, decrease to move left.\n\n'
        'Vert. Offset (decimal, +/-)\nShifts the image up/down. Increase to move the face up, decrease to move down.\n\n'
        'Scale Factor (positive decimal)\nZooms in or out. Values > 1 enlarge, values between 0 and 1 shrink.\n\n'
        'Rotation (decimal, +/-)\nTilts the image. Positive values rotate clockwise, negative counter-clockwise.\n\n'
        'Use the toolbar arrows or type exact numbers. Keep adjusting until the pupils touch all three guides.',
      );

  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollapsibleSectionHeader(
          label: 'CONTROLS',
          isExpanded: _controlsExpanded,
          onTap: () => setState(() => _controlsExpanded = !_controlsExpanded),
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
                  border: Border.all(
                    color: AppColors.settingsCardBorder,
                    width: 1,
                  ),
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
            if (tooltip != null) InfoTooltipIcon(content: tooltip, size: 14),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.settingsCardBorder,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Focus(
            onFocusChange: (hasFocus) {
              _log('TextField "$label" focus=${hasFocus ? "gained" : "lost"}');
            },
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
      _log(
        'Preview waiting: rawBytes=${_rawImageBytes != null}, dims=${_rawImageWidth}x$_rawImageHeight, canvas=${_canvasWidth}x$_canvasHeight, eyes=$_leftEyeXGoal/$_rightEyeXGoal/$_bothEyesYGoal',
      );
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
              final double availableWidth = (constraints.maxWidth - 16).clamp(
                0.0,
                double.infinity,
              );
              final double availableHeight = (constraints.maxHeight - 16).clamp(
                0.0,
                double.infinity,
              );

              if (availableWidth == 0 || availableHeight == 0) {
                _log(
                  'Preview HIDDEN: zero available size (${availableWidth}x$availableHeight)',
                );
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

              // Track preview size for viewport pan clamping
              _lastPreviewSize = Size(previewWidth, previewHeight);

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.settingsCardBorder,
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Center(
                  // SizedBox with calculated dimensions forces FittedBox to
                  // expand and fill available space (scales UP, not just down)
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: ClipRect(
                      child: Listener(
                        onPointerSignal: _handlePreviewPointerSignal,
                        onPointerPanZoomUpdate: _handleTrackpadPanZoom,
                        child: Transform.translate(
                          offset: _viewPanOffset,
                          child: Transform.scale(
                            scale: _viewZoom,
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: _canvasWidth!.toDouble(),
                                height: _canvasHeight!.toDouble(),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: TransformTool(
                                        imageBytes: _rawImageBytes!,
                                        canvasSize: Size(
                                          _canvasWidth!.toDouble(),
                                          _canvasHeight!.toDouble(),
                                        ),
                                        imageSize: Size(
                                          _rawImageWidth!.toDouble(),
                                          _rawImageHeight!.toDouble(),
                                        ),
                                        baseScale: _baseScale,
                                        controller: _transformController,
                                        onChanged: _onTransformChanged,
                                        onChangeEnd: _onTransformChangeEnd,
                                        showRotationHandle: true,
                                        maintainAspectRatio: true,
                                        displayScale: displayScale,
                                      ),
                                    ),
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
    _log(
      '_onTransformControllerChanged: tx=${state.translateX}, ty=${state.translateY}, sc=${state.scale}, rot=${state.rotation}',
    );

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
    final minSavingDisplayFuture = Future.delayed(
      const Duration(milliseconds: 500),
    );

    try {
      final tx = double.tryParse(_inputController1.text) ?? 0;
      final ty = double.tryParse(_inputController2.text) ?? 0;
      final mult = double.tryParse(_inputController3.text) ?? 1;
      final rot = double.tryParse(_inputController4.text) ?? 0;
      final sc = mult * _baseScale;

      // Save via processRequest
      final outcome = await processRequest(tx, ty, sc, rot, save: true);
      if (outcome != ManualStabOutcome.success) {
        setState(() => _savePhase = _SavePhase.idle);
        if (mounted) {
          final msg = switch (outcome) {
            ManualStabOutcome.saveFailed => 'Failed to save changes',
            ManualStabOutcome.invalidImage =>
              'Could not generate stabilized image',
            ManualStabOutcome.stale => 'Save outdated — please try again',
            _ => 'Failed to save changes',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
        return;
      }

      // Update saved state — parse from formatted text fields to match
      // what _checkForUnsavedChanges() will compare against
      _savedTx = double.tryParse(_inputController1.text) ?? 0;
      _savedTy = double.tryParse(_inputController2.text) ?? 0;
      _savedMult = double.tryParse(_inputController3.text) ?? 1;
      _savedRot = double.tryParse(_inputController4.text) ?? 0;
      _hasUnsavedChanges = false;

      // Notify gallery to reload with updated images
      await widget.onSaveComplete?.call();

      // Trigger auto-compile video check (mirrors retry stabilization behavior)
      await DB.instance.setNewVideoNeeded(widget.projectId);

      // If stabilization batch is already active, the flag is enough - video will
      // compile when batch finishes. Otherwise, trigger compilation directly.
      if (!StabilizationService.instance.isActive) {
        unawaited(
          StabilizationService.instance.startStabilization(widget.projectId),
        );
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
    } catch (e, st) {
      _log('_saveChanges ERROR: $e\n$st');
      setState(() => _savePhase = _SavePhase.idle);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save changes')));
      }
    }
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

    _viewZoom = 1.0;
    _viewPanOffset = Offset.zero;

    setState(() => _hasUnsavedChanges = false);
  }

  Widget _buildPreviewHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          if (_viewZoom > 1.0) ...[
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _resetViewZoom,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.settingsAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(_viewZoom * 100).round()}%',
                    style: TextStyle(
                      fontSize: AppTypography.xs,
                      fontWeight: FontWeight.w600,
                      color: AppColors.settingsAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
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

    _log(
      'Loaded saved transform: tx=$tx, ty=$ty, rot=$rot, sc=$sc, mult=$mult',
    );

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
      // Parse from formatted text fields to avoid floating-point round-trip
      // mismatch with _checkForUnsavedChanges()
      _savedTx = double.tryParse(_inputController1.text) ?? 0;
      _savedTy = double.tryParse(_inputController2.text) ?? 0;
      _savedMult = double.tryParse(_inputController3.text) ?? 1;
      _savedRot = double.tryParse(_inputController4.text) ?? 0;
      _hasUnsavedChanges = false;
    });
  }

  void _validateInputs() {
    _log('_validateInputs called (will unfocus)');
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

  Future<ManualStabOutcome> processRequest(
    double? translateX,
    double? translateY,
    double? scaleFactor,
    double? rotationDegrees, {
    bool save = false,
  }) async {
    final int requestId = ++_currentRequestId;
    _log(
      'processRequest(tx=$translateX, ty=$translateY, sc=$scaleFactor, rot=$rotationDegrees, save=$save, reqId=$requestId)',
    );
    if (mounted) {
      setState(() {
        _isProcessing = true;
      });
    }
    try {
      if (_rawImageBytes == null) {
        _log('processRequest ABORTED: _rawImageBytes is null');
        return ManualStabOutcome.invalidImage;
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
        preserveBitDepth: _lossless,
      );
      if (imageBytesStabilized == null) {
        _log(
          'processRequest ABORTED: generateStabilizedImageBytesCVAsync returned null',
        );
        return ManualStabOutcome.invalidImage;
      }

      if (requestId != _currentRequestId || !mounted) {
        _log(
          'processRequest ABORTED: stale request ($requestId vs $_currentRequestId) or not mounted',
        );
        return ManualStabOutcome.stale;
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

        // Do not pre-delete stabilizedPhotoPath / stabThumbPath here.
        // saveBytesToPngFileInIsolate writes atomically (temp + rename), so
        // the existing stabilized PNG is preserved if saveStabilizedImage
        // returns (false, null). Pre-deleting would leave the user with no
        // file when save fails (e.g. out-of-space or infinite transform
        // guard), silently destroying their previous manual-stab work.
        final (saveOk, savedBytes) = await _faceStabilizer!.saveStabilizedImage(
          imageBytesStabilized,
          rawPhotoPath,
          stabilizedPhotoPath,
          0.0,
          translateX: translateX,
          translateY: translateY,
          rotationDegrees: rotationDegrees,
          scaleFactor: scaleFactor,
        );
        if (!saveOk) {
          return ManualStabOutcome.saveFailed;
        }
        await _faceStabilizer!.createStabThumbnail(
          p.setExtension(stabilizedPhotoPath, '.png'),
          imageBytes: savedBytes,
        );

        // Clear caches so gallery shows updated images.
        // Must use clearFlutterImageCache (not just FileImage.evict) because
        // evict() only clears the persistent cache, not live images held by
        // mounted Image widgets behind this route.
        Utils.clearFlutterImageCache();
        ThumbnailService.instance.clearCache(stabThumbPath);
      }

      if (requestId != _currentRequestId ||
          !mounted ||
          _faceStabilizer == null) {
        _log(
          'processRequest ABORTED post-save: stale/unmounted/null stabilizer',
        );
        return ManualStabOutcome.stale;
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
      return ManualStabOutcome.success;
    } catch (e, st) {
      _log('processRequest ERROR: $e\n$st');
      return ManualStabOutcome.saveFailed;
    } finally {
      if (mounted && requestId == _currentRequestId) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _updateTransformSafely(
    double? tx,
    double? ty,
    double mult,
    double? rot,
  ) {
    _updatingFromTextField = true;
    _transformController?.setTransform(
      translateX: tx ?? 0,
      translateY: ty ?? 0,
      scale: mult,
      rotation: rot ?? 0,
    );
    _updatingFromTextField = false;
    _checkForUnsavedChanges();
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

    _updateTransformSafely(
      double.tryParse(_inputController1.text),
      double.tryParse(_inputController2.text),
      mult,
      double.tryParse(_inputController4.text),
    );

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
    _log('_adjustRotation(delta=$delta)');
    // Commit to history before making changes (for undo support)
    _transformController?.commitToHistory();

    double rot = double.tryParse(_inputController4.text) ?? 0.0;
    rot += delta;
    _suppressListener = true;
    _inputController4.text = rot.toStringAsFixed(2);
    _suppressListener = false;

    double mult = double.tryParse(_inputController3.text) ?? 1.0;

    _updateTransformSafely(
      double.tryParse(_inputController1.text),
      double.tryParse(_inputController2.text),
      mult,
      rot,
    );

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
    _log('_onParamChanged fired (debounce starting)');
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
        _log('Debounce applied: tx=$tx, ty=$ty, mult=$mult, rot=$rot');
        // Commit to history before making changes (for undo support)
        _transformController?.commitToHistory();

        _updateTransformSafely(tx, ty, mult, rot);
        processRequest(tx, ty, sc, rot, save: false);
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

    _updateTransformSafely(tx, ty, mult, rot);

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
      _updateTransformSafely(tx, ty, mult, rot);
      processRequest(tx, ty, sc, rot, save: false);
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

    void stopHold(String key, {bool apply = true}) {
      _holdTimers[key]?.cancel();
      _holdTimers.remove(key);
      if (apply) forceApplyNow();
    }

    Widget buildToolbarButton({
      required String key,
      required IconData icon,
      required VoidCallback onTap,
      required VoidCallback onHold,
      String? tooltip,
      bool affectsTransform = true,
    }) {
      Widget button = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => startHold(key, onHold),
          onTapUp: (_) => stopHold(key, apply: affectsTransform),
          onTapCancel: () => stopHold(key, apply: affectsTransform),
          onPanEnd: (_) => stopHold(key, apply: affectsTransform),
          onPanCancel: () => stopHold(key, apply: affectsTransform),
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
                  _log('Toolbar button "$key" tap suppressed (was held)');
                  return;
                }
                _log('Toolbar button "$key" tapped');
                onTap();
                if (affectsTransform) forceApplyNow();
              },
            ),
          ),
        ),
      );

      if (tooltip != null) {
        button = Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: button,
        );
      }

      return button;
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Direction controls (matches Horiz. + Vert. Offset)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
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
                        tooltip: 'Move Left (←)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'right',
                        icon: Icons.arrow_forward_rounded,
                        onTap: () => _adjustOffsets(dx: 1),
                        onHold: () => _adjustOffsets(dx: 1),
                        tooltip: 'Move Right (→)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'up',
                        icon: Icons.arrow_upward_rounded,
                        onTap: () => _adjustOffsets(dy: -1),
                        onHold: () => _adjustOffsets(dy: -1),
                        tooltip: 'Move Up (↑)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'down',
                        icon: Icons.arrow_downward_rounded,
                        onTap: () => _adjustOffsets(dy: 1),
                        onHold: () => _adjustOffsets(dy: 1),
                        tooltip: 'Move Down (↓)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Scale controls (matches Scale Factor)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
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
                        tooltip: 'Scale Down (−)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'scalePlus',
                        icon: Icons.add_rounded,
                        onTap: () => _adjustScale(0.01),
                        onHold: () => _adjustScale(0.01),
                        tooltip: 'Scale Up (+)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Rotation controls (matches Rotation)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
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
                        tooltip: 'Rotate CCW ([)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'rotateCW',
                        icon: Icons.rotate_right_rounded,
                        onTap: () => _adjustRotation(0.1),
                        onHold: () => _adjustRotation(0.1),
                        tooltip: 'Rotate CW (])',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // View zoom controls (visual only — does not affect stabilization)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.settingsCardBorder.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      buildToolbarButton(
                        key: 'viewZoomOut',
                        icon: Icons.zoom_out_rounded,
                        onTap: () => _adjustViewZoom(-_viewZoomStep),
                        onHold: () => _adjustViewZoom(-_viewZoomStep),
                        affectsTransform: false,
                        tooltip: 'Zoom Out ($_modKey−)',
                      ),
                      const SizedBox(width: 4),
                      buildToolbarButton(
                        key: 'viewZoomIn',
                        icon: Icons.zoom_in_rounded,
                        onTap: () => _adjustViewZoom(_viewZoomStep),
                        onHold: () => _adjustViewZoom(_viewZoomStep),
                        affectsTransform: false,
                        tooltip: 'Zoom In ($_modKey+)',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
