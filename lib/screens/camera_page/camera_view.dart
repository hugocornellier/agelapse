import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/async_mutex.dart';
import '../../services/database_helper.dart';
import '../../services/log_service.dart';
import '../../styles/styles.dart';
import '../../utils/camera_utils.dart';
import '../../utils/utils.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import '../../utils/platform_utils.dart';
import '../../utils/settings_utils.dart';
import '../guide_mode_tutorial_page.dart';
import '../took_first_photo_page.dart';
import 'grid_mode.dart';
import 'camera_grid.dart';
import 'countdown_overlay.dart';
import 'capture_flash_overlay.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:camera_desktop/camera_desktop.dart';

class RotatingIconButton extends StatelessWidget {
  final Widget child;
  final double rotationTurns;
  final VoidCallback onPressed;
  final Duration duration;
  const RotatingIconButton({
    super.key,
    required this.child,
    required this.rotationTurns,
    required this.onPressed,
    this.duration = const Duration(milliseconds: 300),
  });
  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: rotationTurns,
      duration: duration,
      curve: Curves.easeInOut,
      child: IconButton(
        icon: child,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}

double getRotation(String orientation) {
  if (orientation == 'Landscape Left') return 0.25;
  if (orientation == 'Landscape Right') return -0.25;
  return 0.0;
}

class CameraView extends StatefulWidget {
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;
  final int projectId;
  final String projectName;
  final bool? takingGuidePhoto;
  final int? forceGridModeEnum;
  final VoidCallback openGallery;
  final Future<void> Function() refreshSettings;
  final void Function(int index) goToPage;

  const CameraView({
    super.key,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
    this.initialCameraLensDirection = CameraLensDirection.front,
    required this.projectId,
    required this.projectName,
    this.takingGuidePhoto,
    this.forceGridModeEnum,
    required this.openGallery,
    required this.refreshSettings,
    required this.goToPage,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  static List<CameraDescription> _cameras = [];
  static final AsyncMutex _cameraLifecycleMutex = AsyncMutex();
  CameraController? _controller;
  int _cameraIndex = -1;
  int? frontFacingLensIndex;
  int? backFacingLensIndex;
  bool _changingCameraLens = false;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  bool backIndexSet = false;

  // Capture flash overlay key for triggering flash animation
  final GlobalKey<CaptureFlashOverlayState> _flashKey = GlobalKey();
  bool closingCamera = false;
  bool _draggingRight = false;
  bool flashEnabled = true;
  bool enableGrid = false;
  bool modifyGridMode = false;
  double offsetX = 0;
  double offsetY = 0;
  Timer? _timer;
  late final bool takingGuidePhoto;
  bool _isDraggingVertical = false;
  bool _isDraggingHorizontal = false;
  bool showGuidePhoto = false;
  double _widgetHeight = 0.0;
  final GlobalKey _widgetKey = GlobalKey();
  GridMode _gridMode = GridMode.none;
  Completer<void>? _pictureTakingCompleter;
  bool _isInfoWidgetVisible = true;
  bool isMirrored = false;
  String _orientation = '';

  // Timer state
  int _timerDuration = 0; // 0 = off, 3 = 3s, 10 = 10s
  bool _isCountingDown = false;
  int _countdownValue = 0;
  Timer? _countdownTimer;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeTimerAnimation();
    _initialize();

    if (isMobile) {
      _accelerometerSubscription = accelerometerEventStream().listen((
        AccelerometerEvent event,
      ) {
        final potentialOrientation = event.x.abs() > event.y.abs()
            ? (event.x > 0 ? "Landscape Left" : "Landscape Right")
            : (event.y > 0 ? "Portrait Up" : "Portrait Down");

        if (potentialOrientation == "Portrait Down" &&
            (_orientation == "Landscape Left" ||
                _orientation == "Landscape Right")) {
          return;
        }

        if (potentialOrientation != _orientation) {
          setState(() {
            _orientation = potentialOrientation;
          });

          resetOffsetValues(potentialOrientation);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getWidgetHeight();
    });
  }

  void _getWidgetHeight() {
    final RenderBox? renderBox =
        _widgetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      setState(() {
        _widgetHeight = renderBox.size.height;
      });
    }
  }

  void _initialize() async {
    final bool hasSeenGuideModeTut = await SettingsUtil.hasSeenGuideModeTut(
      widget.projectId.toString(),
    );
    final bool hasTakenFirstPhoto = await SettingsUtil.hasTakenFirstPhoto(
      widget.projectId.toString(),
    );
    final bool mirrorSettingBool = await SettingsUtil.loadCameraMirror(
      widget.projectId.toString(),
    );
    if (!mounted) return;

    final String mirrorSetting = mirrorSettingBool.toString();

    if (mirrorSetting.isNotEmpty) {
      setState(() => isMirrored = mirrorSetting == 'true');
    }

    if (hasTakenFirstPhoto && !hasSeenGuideModeTut) {
      if (!mounted) return;
      Utils.navigateToScreenNoAnim(
        context,
        GuideModeTutorialPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          goToPage: widget.goToPage,
          sourcePage: "CameraView",
        ),
      );

      return;
    }

    final int gridModeIndex = await SettingsUtil.loadGridModeIndex(
      widget.projectId.toString(),
    );
    setStateIfMounted(() {
      _gridMode = GridMode.values[gridModeIndex];
    });

    final projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final hasStabPhotos = await DB.instance.hasStabilizedPhotos(
      widget.projectId,
      projectOrientation,
    );
    if (!mounted) return;
    if (hasStabPhotos) {
      setState(() {
        showGuidePhoto = true;
      });
    }

    // On desktop platforms, load grid offsets based on project orientation
    // (mobile uses accelerometer to detect orientation and load offsets)
    if (isDesktop) {
      // projectOrientation is lowercase ("landscape" or "portrait") from loadProjectOrientation()
      final customOrientation = projectOrientation.toLowerCase() == "landscape"
          ? "landscape"
          : "portrait";
      final offsetXStr = await SettingsUtil.loadGuideOffsetXCustomOrientation(
        widget.projectId.toString(),
        customOrientation,
      );
      final offsetYStr = await SettingsUtil.loadGuideOffsetYCustomOrientation(
        widget.projectId.toString(),
        customOrientation,
      );
      setStateIfMounted(() {
        _orientation = projectOrientation;
        offsetX = double.parse(offsetXStr);
        offsetY = double.parse(offsetYStr);
      });
    }

    takingGuidePhoto = widget.takingGuidePhoto ?? false;

    final String flashSetting = await SettingsUtil.loadCameraFlash(
      widget.projectId.toString(),
    );
    if (flashSetting == 'off') flashEnabled = false;

    await _loadTimerSetting();

    if (widget.forceGridModeEnum != null) {
      _gridMode = GridMode.values[widget.forceGridModeEnum!];
    } else if (!takingGuidePhoto) {
      final bool enableGridSetting = await SettingsUtil.loadEnableGrid();
      if (!mounted) return;
      setState(() => enableGrid = enableGridSetting);
    }

    // Unified camera initialization for ALL platforms
    _cameras = await availableCameras();
    if (!mounted) return;

    for (var i = 0; i < _cameras.length; i++) {
      CameraDescription camera = _cameras[i];

      if (camera.lensDirection == CameraLensDirection.front) {
        frontFacingLensIndex = i;
      }

      if (camera.lensDirection == CameraLensDirection.back && !backIndexSet) {
        backFacingLensIndex = i;
        backIndexSet = true;
      }

      if (camera.lensDirection == widget.initialCameraLensDirection) {
        _cameraIndex = i;
      }
    }
    // Fallback: if no front-facing camera found (common on Linux desktop),
    // use the first available camera.
    if (_cameraIndex == -1 && _cameras.isNotEmpty) {
      _cameraIndex = 0;
    }
    if (_cameraIndex != -1) {
      await _startLiveFeed();
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();
    _timer?.cancel();
    _countdownTimer?.cancel();
    _pulseController?.dispose();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  // ==================== Timer Methods ====================

  /// Initialize the pulse animation controller for countdown
  void _initializeTimerAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeOut),
    );
  }

  /// Load timer setting from database
  Future<void> _loadTimerSetting() async {
    final int duration = await SettingsUtil.loadCameraTimer(
      widget.projectId.toString(),
    );
    if (mounted) {
      setState(() {
        _timerDuration = duration;
      });
    }
  }

  /// Cycle through timer durations: OFF -> 3s -> 10s -> OFF
  void _cycleTimerDuration() {
    setState(() {
      if (_timerDuration == 0) {
        _timerDuration = 3;
      } else if (_timerDuration == 3) {
        _timerDuration = 10;
      } else {
        _timerDuration = 0;
      }
    });
    _saveTimerSetting();
  }

  /// Save timer setting to database
  Future<void> _saveTimerSetting() async {
    await DB.instance.setSettingByTitle(
      'camera_timer_duration',
      _timerDuration.toString(),
      widget.projectId.toString(),
    );
  }

  /// Handle shutter button press - either start countdown or take photo
  void _onShutterPressed() {
    if (_isCountingDown) {
      _cancelCountdown();
    } else if (_timerDuration > 0) {
      _startCountdown();
    } else {
      _takePicture();
    }
  }

  /// Start the countdown timer
  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _countdownValue = _timerDuration;
    });

    // Trigger initial pulse and feedback
    _pulseController?.forward(from: 0.0);
    _triggerCountdownFeedback();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue <= 1) {
        // Countdown complete - take the photo
        _cancelCountdown();
        _takePicture();
      } else {
        setState(() {
          _countdownValue--;
        });
        _pulseController?.forward(from: 0.0);
        _triggerCountdownFeedback();
      }
    });
  }

  /// Cancel an active countdown
  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _pulseController?.stop();
    _pulseController?.reset();
    setState(() {
      _isCountingDown = false;
      _countdownValue = 0;
    });
  }

  /// Trigger feedback (vibration) for each countdown tick
  Future<void> _triggerCountdownFeedback() async {
    // Use shorter vibration for countdown ticks on mobile
    if (isMobile) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(duration: 100, amplitude: 128);
        }
      } catch (e) {
        // Vibration not available, continue silently
        LogService.instance.log('Vibration error: $e');
      }
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_pictureTakingCompleter != null) return; // capture already in progress
    _pictureTakingCompleter = Completer<void>();

    bool captureSuccess = false;

    try {
      final XFile image = await _controller!.takePicture();
      final Uint8List bytes = await image.readAsBytes();

      // macOS/Linux: camera_desktop mirrors at the native source — pixels in
      // the XFile are already mirrored, so no post-processing needed.
      // Windows/iOS/Android: no source-level mirror — apply in post-processing.
      final bool needsPostProcessMirror =
          isMirrored && !Platform.isMacOS && !Platform.isLinux;

      captureSuccess = await CameraUtils.savePhoto(
        image,
        widget.projectId,
        false,
        null,
        bytes: bytes,
        applyMirroring: needsPostProcessMirror,
        deviceOrientation: _orientation,
        refreshSettings: widget.refreshSettings,
      );

      // Trigger visual and haptic feedback only on successful capture
      if (captureSuccess) {
        _flashKey.currentState?.flash();
        CameraUtils.triggerCaptureHaptic();
      }

      final bool hasTakenFirstPhoto = await SettingsUtil.hasTakenFirstPhoto(
        widget.projectId.toString(),
      );
      if (!hasTakenFirstPhoto) {
        await SettingsUtil.setHasTakenFirstPhotoToTrue(
          widget.projectId.toString(),
        );
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => TookFirstPhotoPage(
              projectId: widget.projectId,
              projectName: widget.projectName,
              goToPage: widget.goToPage,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      }
    } finally {
      _pictureTakingCompleter?.complete();
      _pictureTakingCompleter = null;
    }
  }

  void _toggleModifyGridMode() {
    setState(() {
      modifyGridMode = !modifyGridMode;
    });
  }

  void _saveGridOffsets() async {
    // Handle both mobile orientations ("Landscape Left"/"Landscape Right")
    // and desktop orientations ("landscape" lowercase from project settings)
    final bool isLandscape = _orientation == "Landscape Left" ||
        _orientation == "Landscape Right" ||
        _orientation.toLowerCase() == "landscape";
    final String guideOffSetXColName =
        isLandscape ? "guideOffsetXLandscape" : "guideOffsetXPortrait";
    final String guideOffSetYColName =
        isLandscape ? "guideOffsetYLandscape" : "guideOffsetYPortrait";

    await DB.instance.setSettingByTitle(
      guideOffSetXColName,
      offsetX.toString(),
      widget.projectId.toString(),
    );
    await DB.instance.setSettingByTitle(
      guideOffSetYColName,
      offsetY.toString(),
      widget.projectId.toString(),
    );

    setStateIfMounted(() {
      modifyGridMode = false;
    });
  }

  Widget mirrorButton() => _buildButton(
        () => toggleMirror(),
        Icon(
          isMirrored ? Icons.flip : Icons.flip_outlined,
          size: 24,
          color: AppColors.textPrimary,
        ),
      );

  void toggleMirror() {
    setState(() {
      isMirrored = !isMirrored;
    });

    // Save the NEW value after toggling
    DB.instance.setSettingByTitle(
      'camera_mirror',
      isMirrored.toString(),
      widget.projectId.toString(),
    );

    // On macOS/Linux, toggle mirror at the native source — no restart needed.
    if (Platform.isMacOS || Platform.isLinux) {
      if (_controller != null) {
        CameraDesktopPlugin().setMirror(_controller!.cameraId, isMirrored);
      }
    } else if (Platform.isWindows) {
      // Windows: mirror is visual-only (Transform.scale in preview).
      // setState already triggers rebuild with new scaleX. No restart needed.
    } else {
      // Mobile: restart to apply mirror.
      _restartCameraWithCurrentSettings();
    }
  }

  Future<void> _restartCameraWithCurrentSettings() async {
    await _stopLiveFeed();
    await _startLiveFeed();
  }

  Widget _timerButton() => Container(
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: AppColors.overlay.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(10),
        ),
        child: RotatingIconButton(
          rotationTurns: getRotation(_orientation),
          onPressed: _cycleTimerDuration,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _timerDuration == 0 ? Icons.timer_off_outlined : Icons.timer,
                size: 24,
                color: AppColors.textPrimary,
              ),
              if (_timerDuration > 0)
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$_timerDuration',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppTypography.xs,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _leftSideControls() => Positioned(
        bottom: 21,
        left: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)
              Container(
                padding: const EdgeInsets.all(0),
                decoration: BoxDecoration(
                  color: AppColors.overlay.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RotatingIconButton(
                  rotationTurns: getRotation(_orientation),
                  onPressed: toggleFlash,
                  child: Icon(
                    flashEnabled ? Icons.flash_auto : Icons.flash_off,
                    size: 24,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)
              const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: AppColors.overlay.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(10),
              ),
              child: RotatingIconButton(
                rotationTurns: getRotation(_orientation),
                onPressed: _toggleGrid,
                child: _buildIcon(),
              ),
            ),
          ],
        ),
      );

  Widget _rightSideControls() => Positioned(
        bottom: 21,
        right: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _timerButton(),
            if (!isDesktop) const SizedBox(width: 12),
            if (!isDesktop)
              Container(
                padding: const EdgeInsets.all(0),
                decoration: BoxDecoration(
                  color: AppColors.overlay.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RotatingIconButton(
                  rotationTurns: getRotation(_orientation),
                  onPressed: _switchLiveCamera,
                  child: Icon(
                    Platform.isIOS
                        ? Icons.flip_camera_ios_outlined
                        : Icons.flip_camera_android_outlined,
                    color: AppColors.textPrimary,
                    size: 27,
                  ),
                ),
              ),
          ],
        ),
      );

  void _toggleGrid() {
    setState(() {
      if (showGuidePhoto) {
        _gridMode =
            GridMode.values[(_gridMode.index + 1) % GridMode.values.length];
      } else {
        if (_gridMode.index == 0) {
          _gridMode = GridMode.values[2];
        } else {
          _gridMode = GridMode.values[0];
        }
      }

      DB.instance.setSettingByTitle(
        'grid_mode_index',
        _gridMode.index.toString(),
        widget.projectId.toString(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, backgroundColor: AppColors.overlay),
      body: CaptureFlashOverlay(key: _flashKey, child: _liveFeedBody()),
    );
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty ||
        _controller == null ||
        !(_controller!.value.isInitialized)) {
      return const SizedBox.shrink();
    }

    final camera = _controller!.value;
    final size = MediaQuery.of(context).size;

    // Mobile: use "cover" logic - fill screen, crop edges
    double scale = size.aspectRatio * camera.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: ColoredBox(
        color: AppColors.overlay,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Center(
              child: _changingCameraLens
                  ? const Center(child: CircularProgressIndicator())
                  : Platform.isWindows
                      // Windows: camera_windows doesn't mirror at source, so flip in Dart.
                      ? Transform.scale(
                          scaleX: isMirrored ? 1 : -1,
                          child: AspectRatio(
                            aspectRatio: camera.aspectRatio,
                            child: CameraPreview(_controller!, child: null),
                          ),
                        )
                      : (Platform.isMacOS || Platform.isLinux)
                          // macOS/Linux: camera_desktop mirrors at source — no Dart flip needed.
                          ? AspectRatio(
                              aspectRatio: camera.aspectRatio,
                              child: CameraPreview(_controller!, child: null),
                            )
                          // Mobile: original cover/crop logic
                          : Transform.scale(
                              scale: scale,
                              child: Center(
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 3, 1.0),
                                  child:
                                      CameraPreview(_controller!, child: null),
                                ),
                              ),
                            ),
            ),
            if (_gridMode != GridMode.none)
              CameraGridOverlay(
                widget.projectId,
                _gridMode,
                offsetX,
                offsetY,
                orientation: _orientation,
                useSelectedGuidePhoto: true,
              ),
            if (_isCountingDown && _pulseAnimation != null)
              CountdownOverlay(
                countdownValue: _countdownValue,
                pulseAnimation: _pulseAnimation!,
              ),
            if (!modifyGridMode && !_isCountingDown) _leftSideControls(),
            if (!modifyGridMode && !_isCountingDown) _rightSideControls(),
            if (!modifyGridMode) _cameraControl(),
            if (modifyGridMode) gridModifierOverlay(),
            if (modifyGridMode && _isInfoWidgetVisible) ...[
              Positioned(
                bottom: 32,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.info.withAlpha(
                      179,
                    ), // Equivalent to opacity 0.7
                    borderRadius: BorderRadius.circular(
                      16,
                    ), // More rounded corners
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Drag guide lines to optimal position. Tap\n"
                        "checkmark to save changes. Note: Camera guide\n"
                        "lines don't affect output guide lines.",
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppTypography.sm,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isInfoWidgetVisible = false),
                        child: Icon(
                          Icons.close,
                          color: AppColors.textPrimary,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (modifyGridMode) saveGridButton(),
            if (!modifyGridMode &&
                !_isCountingDown &&
                (_gridMode == GridMode.gridOnly ||
                    _gridMode == GridMode.doubleGhostGrid ||
                    _gridMode == GridMode.ghostOnly))
              modifyGridButton(),
          ],
        ),
      ),
    );
  }

  Widget flashButton() => Positioned(
        bottom: 21,
        left: 16,
        child: _buildButton(
          () => toggleFlash(),
          Icon(
            flashEnabled ? Icons.flash_auto : Icons.flash_off,
            size: 24,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Widget gridButton() => Positioned(
        bottom: 21,
        left: 64,
        child: _buildButton(() => _toggleGrid(), _buildIcon()),
      );

  Widget _cameraControl() {
    return Positioned(
      bottom: 21 - 4,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring during countdown
            if (_isCountingDown && _timerDuration > 0)
              CustomPaint(
                size: const Size(84, 84),
                painter: CountdownProgressPainter(
                  progress: 1.0 - (_countdownValue / _timerDuration),
                  strokeWidth: 4,
                  color: AppColors.textPrimary,
                ),
              ),
            // Shutter button
            ElevatedButton(
              style: takePhotoRoundStyle(),
              onPressed: _onShutterPressed,
              child: Icon(
                _isCountingDown ? Icons.close : Icons.circle,
                color: AppColors.textPrimary,
                size: 70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_gridMode == GridMode.none) {
      return Icon(Icons.grid_off, size: 24, color: AppColors.textPrimary);
    } else if (_gridMode == GridMode.gridOnly) {
      return Icon(Icons.grid_3x3, size: 24, color: AppColors.textPrimary);
    } else if (_gridMode == GridMode.ghostOnly) {
      return FaIcon(
        FontAwesomeIcons.ghost,
        size: 24,
        color: AppColors.textPrimary,
      );
    } else {
      return SvgPicture.asset(
        'assets/ghost-custom.svg',
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
      );
    }
  }

  Widget modifyGridButton() => Positioned(
        bottom: 75,
        left: 16,
        child: RotatingIconButton(
          rotationTurns: getRotation(_orientation),
          onPressed: _toggleModifyGridMode,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accentLight.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "Move\nGuides",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTypography.sm),
            ),
          ),
        ),
      );

  Widget saveGridButton() => Positioned(
        top: 32,
        right: 32,
        child: _buildButton(
          () => _saveGridOffsets(),
          Icon(Icons.check, size: 24, color: AppColors.textPrimary),
        ),
      );

  Widget gridModifierOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            key: _widgetKey,
            onPanStart: (details) {
              _getWidgetHeight();
              final size = MediaQuery.of(context).size;
              final dx = details.localPosition.dx;
              final dy = details.localPosition.dy;
              final bool isLandscape = (_orientation == "Landscape Left" ||
                  _orientation == "Landscape Right");

              if (!isLandscape) {
                // PORTRAIT MODE:
                final centerX = size.width / 2;
                final leftX = centerX - offsetX * size.width;
                final rightX = centerX + offsetX * size.width;
                final centerY = _widgetHeight * offsetY;

                final distanceToLeftX = (dx - leftX).abs();
                final distanceToRightX = (dx - rightX).abs();
                final distanceToCenterY = (dy - centerY).abs();

                if (distanceToLeftX < 20 || distanceToRightX < 20) {
                  _isDraggingVertical = true;
                  _draggingRight = distanceToRightX < 20;
                } else if (distanceToCenterY < 20) {
                  _isDraggingHorizontal = true;
                }
              } else {
                // LANDSCAPE MODE:

                double verticalLineX = _orientation == "Landscape Left"
                    ? size.width * (1 - offsetY)
                    : size.width * offsetY;

                final offsetXInPixels = size.height * offsetX;
                final centerY = _widgetHeight / 2;
                final topY = centerY - offsetXInPixels;
                final bottomY = centerY + offsetXInPixels;

                final distanceToVertical = (dx - verticalLineX).abs();
                final distanceToTop = (dy - topY).abs();
                final distanceToBottom = (dy - bottomY).abs();

                if (distanceToVertical < 20) {
                  _isDraggingVertical = true;
                } else if (distanceToTop < 20 || distanceToBottom < 20) {
                  _isDraggingHorizontal = true;
                }
              }
            },
            onPanUpdate: (details) {
              final size = MediaQuery.of(context).size;
              final bool isLandscape = (_orientation == "Landscape Left" ||
                  _orientation == "Landscape Right");

              if (!isLandscape) {
                // PORTRAIT MODE:
                if (_isDraggingVertical) {
                  setState(() {
                    if (_draggingRight) {
                      offsetX += details.delta.dx / size.width;
                    } else {
                      offsetX -= details.delta.dx / size.width;
                    }
                    offsetX = offsetX.clamp(0.0, 1.0);
                  });
                } else if (_isDraggingHorizontal) {
                  setState(() {
                    offsetY += details.delta.dy / _widgetHeight;
                    offsetY = offsetY.clamp(0.0, 1.0);
                  });
                }
              } else {
                // LANDSCAPE MODE:
                if (_isDraggingVertical) {
                  setState(() {
                    if (_orientation == "Landscape Right") {
                      offsetY += details.delta.dx / size.width;
                    } else {
                      offsetY -= details.delta.dx / size.width;
                    }

                    offsetY = offsetY.clamp(0.0, 1.0);
                  });
                } else if (_isDraggingHorizontal) {
                  setState(() {
                    offsetX += details.delta.dy / _widgetHeight;
                    offsetX = offsetX.clamp(0.0, 1.0);
                  });
                }
              }
            },
            onPanEnd: (details) {
              _isDraggingVertical = false;
              _isDraggingHorizontal = false;
            },
            child: CustomPaint(
              painter: _GridPainter(offsetX, offsetY, _orientation),
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> toggleFlash() async {
    setState(() => flashEnabled = !flashEnabled);
    if (flashEnabled) {
      await _controller?.setFlashMode(FlashMode.auto);
      DB.instance.setSettingByTitle(
        'camera_flash',
        'auto',
        widget.projectId.toString(),
      );
      return;
    }
    await _controller?.setFlashMode(FlashMode.off);
    DB.instance.setSettingByTitle(
      'camera_flash',
      'off',
      widget.projectId.toString(),
    );
  }

  Widget _buildButton(VoidCallback onTap, Widget child, {Color? color}) {
    color ??= AppColors.overlay.withValues(alpha: 0.54);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }

  Future _startLiveFeed() async {
    await _cameraLifecycleMutex.acquire();
    try {
      final camera = _cameras[_cameraIndex];
      _controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await _controller?.initialize();
      } catch (e) {
        debugPrint('Camera initialization failed: $e');
        await _controller?.dispose();
        _controller = null;
        return;
      }

      if (!mounted) {
        return;
      }

      _controller?.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Apply mirror setting via camera_desktop on macOS/Linux.
      if (Platform.isMacOS || Platform.isLinux) {
        try {
          await CameraDesktopPlugin().setMirror(
            _controller!.cameraId,
            isMirrored,
          );
        } catch (e) {
          // Non-fatal — continue with default mirror state.
        }
      }

      // Windows and Linux don't need image streaming (callback is a no-op)
      if (Platform.isWindows || Platform.isLinux) {
        if (widget.onCameraFeedReady != null) {
          widget.onCameraFeedReady!();
        }
        if (widget.onCameraLensDirectionChanged != null) {
          widget.onCameraLensDirectionChanged!(camera.lensDirection);
        }
      } else {
        _controller?.startImageStream(_processCameraImage).then((value) {
          if (!mounted) return;
          if (widget.onCameraFeedReady != null) {
            widget.onCameraFeedReady!();
          }
          if (widget.onCameraLensDirectionChanged != null) {
            widget.onCameraLensDirectionChanged!(camera.lensDirection);
          }
        });
      }
      _controller?.getMinZoomLevel().then((value) {});
      _controller?.getMaxZoomLevel().then((value) {});
      if (mounted) setState(() {});
    } finally {
      _cameraLifecycleMutex.release();
    }
  }

  Future<void> _stopLiveFeed() async {
    await _cameraLifecycleMutex.acquire();
    try {
      if (_pictureTakingCompleter != null) {
        await _pictureTakingCompleter!.future;
      }
      if (!Platform.isWindows && _controller?.value.isInitialized == true) {
        try {
          await _controller?.stopImageStream();
        } catch (_) {
          // Camera may already be stopped or never started streaming.
        }
      }
      await _controller?.dispose();
      _controller = null;
    } finally {
      _cameraLifecycleMutex.release();
    }
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex == frontFacingLensIndex
        ? backFacingLensIndex
        : frontFacingLensIndex)!;

    await _stopLiveFeed();
    await _startLiveFeed();
    if (mounted) setState(() => _changingCameraLens = false);
  }

  Future<void> setFocusPoint(Offset point) async {
    if (_controller!.value.isInitialized &&
        _controller!.value.focusPointSupported) {
      await _controller?.setFocusPoint(point);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {}

  Future<void> resetOffsetValues(String potentialOrientation) async {
    String customOrientation;
    if (potentialOrientation == "Landscape Left" ||
        potentialOrientation == "Landscape Right") {
      customOrientation = "landscape";
    } else {
      customOrientation = "portrait";
    }

    final String offsetXStr =
        await SettingsUtil.loadGuideOffsetXCustomOrientation(
      widget.projectId.toString(),
      customOrientation,
    );
    final String offsetYStr =
        await SettingsUtil.loadGuideOffsetYCustomOrientation(
      widget.projectId.toString(),
      customOrientation,
    );

    setStateIfMounted(() {
      offsetX = double.parse(offsetXStr);
      offsetY = double.parse(offsetYStr);
    });
  }
}

class _GridPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final String orientation;

  _GridPainter(this.offsetX, this.offsetY, this.orientation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentLight
      ..strokeWidth = 2;

    final bool isLandscape =
        (orientation == "Landscape Left" || orientation == "Landscape Right");

    if (!isLandscape) {
      final offsetXInPixels = size.width * offsetX;
      final centerX = size.width / 2;
      final leftX = centerX - offsetXInPixels;
      final rightX = centerX + offsetXInPixels;

      canvas.drawLine(Offset(leftX, 0), Offset(leftX, size.height), paint);
      canvas.drawLine(Offset(rightX, 0), Offset(rightX, size.height), paint);

      final y = size.height * offsetY;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      double verticalLineX = orientation == "Landscape Left"
          ? size.width * (1 - offsetY)
          : size.width * offsetY;
      canvas.drawLine(
        Offset(verticalLineX, 0),
        Offset(verticalLineX, size.height),
        paint,
      );

      final offsetYInPixels = size.height * offsetX;
      final centerY = size.height / 2;
      final topY = centerY - offsetYInPixels;
      final bottomY = centerY + offsetYInPixels;
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), paint);
      canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return offsetX != oldDelegate.offsetX ||
        offsetY != oldDelegate.offsetY ||
        orientation != oldDelegate.orientation;
  }
}
