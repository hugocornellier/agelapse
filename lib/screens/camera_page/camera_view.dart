import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/database_helper.dart';
import '../../services/log_service.dart';
import '../../styles/styles.dart';
import '../../utils/camera_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/utils.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import '../../utils/settings_utils.dart';
import '../guide_mode_tutorial_page.dart';
import '../took_first_photo_page.dart';
import 'grid_mode.dart';
import 'countdown_overlay.dart';
import 'capture_flash_overlay.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;
import 'package:camera_macos/camera_macos.dart' as cmacos;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  cmacos.CameraMacOSController? _macController;

  // Timer state
  int _timerDuration = 0; // 0 = off, 3 = 3s, 10 = 10s
  bool _isCountingDown = false;
  int _countdownValue = 0;
  Timer? _countdownTimer;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  // macOS camera state
  String? _macOSCameraDeviceId;
  List<cmacos.CameraMacOSDevice> _macOSCameras = [];

  // Linux camera state (using media_kit)
  Player? _linuxPlayer;
  VideoController? _linuxVideoController;
  bool _linuxCameraReady = false;
  String? _linuxCameraError;

  @override
  void initState() {
    super.initState();
    _initializeTimerAnimation();
    _initialize();

    if (Platform.isAndroid || Platform.isIOS) {
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
    if (renderBox != null) {
      setState(() {
        _widgetHeight = renderBox.size.height;
      });
    }
  }

  Widget _macOSBody() {
    // Wait for camera enumeration to complete before showing camera
    final bool cameraReady =
        _macOSCameras.isNotEmpty || _macOSCameraDeviceId != null;

    return SafeArea(
      bottom: true,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: [
          if (!cameraReady)
            const Center(child: CircularProgressIndicator())
          else
            cmacos.CameraMacOSView(
              fit: BoxFit.cover,
              cameraMode: cmacos.CameraMacOSMode.photo,
              deviceId: _macOSCameraDeviceId,
              isVideoMirrored: isMirrored,
              onCameraLoading: (error) {
                return const Center(child: CircularProgressIndicator());
              },
              onCameraInizialized: (cmacos.CameraMacOSController c) {
                setState(() => _macController = c);
              },
            ),
          if (_gridMode != GridMode.none)
            CameraGridOverlay(
              widget.projectId,
              _gridMode,
              offsetX,
              offsetY,
              orientation: _orientation,
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
          if (modifyGridMode) saveGridButton(),
          if (!modifyGridMode &&
              !_isCountingDown &&
              (_gridMode == GridMode.gridOnly ||
                  _gridMode == GridMode.doubleGhostGrid ||
                  _gridMode == GridMode.ghostOnly))
            modifyGridButton(),
        ],
      ),
    );
  }

  void _initialize() async {
    if (Platform.isMacOS) {
      await _enumerateMacOSCameras();
    }

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
    if (!mounted) return;
    setState(() {
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
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
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
      if (!mounted) return;
      setState(() {
        _orientation = projectOrientation;
        offsetX = double.parse(offsetXStr);
        offsetY = double.parse(offsetYStr);
      });
    }

    takingGuidePhoto =
        (widget.takingGuidePhoto != null && widget.takingGuidePhoto == true);

    final String flashSetting = await SettingsUtil.loadCameraFlash(
      widget.projectId.toString(),
    );
    if (flashSetting == 'off') flashEnabled = false;

    await _loadTimerSetting();

    if (Platform.isLinux) {
      // Linux uses media_kit for camera capture (no flutter camera plugin available)
      if (widget.forceGridModeEnum != null) {
        _gridMode = GridMode.values[widget.forceGridModeEnum!];
      } else if (!takingGuidePhoto) {
        final bool enableGridSetting = await SettingsUtil.loadEnableGrid();
        if (!mounted) return;
        setState(() => enableGrid = enableGridSetting);
      }
      await _initLinuxCamera();
    } else if (!Platform.isMacOS) {
      _cameras = await availableCameras();
      if (!mounted) return;

      if (widget.forceGridModeEnum != null) {
        _gridMode = GridMode.values[widget.forceGridModeEnum!];
      } else if (!takingGuidePhoto) {
        final bool enableGridSetting = await SettingsUtil.loadEnableGrid();
        if (!mounted) return;
        setState(() => enableGrid = enableGridSetting);
      }

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
      if (_cameraIndex != -1) {
        _startLiveFeed();
      }
    } else {
      if (widget.forceGridModeEnum != null) {
        _gridMode = GridMode.values[widget.forceGridModeEnum!];
      } else if (!takingGuidePhoto) {
        final bool enableGridSetting = await SettingsUtil.loadEnableGrid();
        if (!mounted) return;
        setState(() => enableGrid = enableGridSetting);
      }
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();
    _disposeMacController();
    _disposeLinuxCamera();
    _timer?.cancel();
    _countdownTimer?.cancel();
    _pulseController?.dispose();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  /// Enumerate macOS cameras and select preferred device
  /// Prefers built-in camera over Continuity Camera (iPhone) which often causes grey frames
  Future<void> _enumerateMacOSCameras() async {
    try {
      final devices = await cmacos.CameraMacOS.instance.listDevices();
      if (devices.isEmpty) {
        if (mounted) {
          setState(() => _macOSCameras = []);
        }
        return;
      }

      // Select preferred camera: prefer built-in Mac camera over iPhone Continuity Camera
      cmacos.CameraMacOSDevice? selectedDevice;

      // First, try to find a built-in Mac camera (FaceTime, MacBook Pro Camera, etc.)
      for (final device in devices) {
        final name = device.localizedName?.toLowerCase() ?? '';
        final devId = device.deviceId.toLowerCase();

        if (name.contains('macbook') ||
            name.contains('facetime') ||
            name.contains('imac') ||
            devId.contains('built-in') ||
            devId.contains('facetime')) {
          selectedDevice = device;
          break;
        }
      }

      // If no built-in camera found, try to avoid iPhone/Continuity cameras
      if (selectedDevice == null) {
        for (final device in devices) {
          final name = device.localizedName?.toLowerCase() ?? '';
          final devId = device.deviceId.toLowerCase();

          if (name.contains('iphone') ||
              name.contains('continuity') ||
              devId.contains('iphone')) {
            continue;
          }

          selectedDevice = device;
          break;
        }
      }

      // Fallback to first device if no preference matched
      if (selectedDevice == null && devices.isNotEmpty) {
        selectedDevice = devices.first;
      }

      if (mounted) {
        setState(() {
          _macOSCameras = devices;
          _macOSCameraDeviceId = selectedDevice?.deviceId;
        });
      }
    } catch (e) {
      debugPrint('macOS camera enumeration failed: $e');
      if (mounted) {
        setState(() => _macOSCameras = []);
      }
    }
  }

  /// Dispose macOS camera controller if active
  void _disposeMacController() {
    if (_macController != null) {
      try {
        _macController!.destroy();
      } catch (e) {
        debugPrint('Error disposing macOS camera: $e');
      }
      _macController = null;
    }
  }

  /// Dispose Linux camera (media_kit player) if active
  void _disposeLinuxCamera() {
    _linuxPlayer?.dispose();
    _linuxPlayer = null;
    _linuxVideoController = null;
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
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(duration: 100, amplitude: 128);
        }
      } catch (e) {
        // Vibration not available, continue silently
        debugPrint('Vibration error: $e');
      }
    }
  }

  /// Initialize Linux camera using media_kit with V4L2
  Future<void> _initLinuxCamera() async {
    try {
      LogService.instance.log('Linux: initializing camera with media_kit...');

      // Ensure MediaKit is initialized (required for Player)
      MediaKit.ensureInitialized();

      // Check for video devices
      final videoDevices = <String>[];
      for (int i = 0; i < 10; i++) {
        final devicePath = '/dev/video$i';
        if (await File(devicePath).exists()) {
          videoDevices.add(devicePath);
        }
      }

      if (videoDevices.isEmpty) {
        setState(() {
          _linuxCameraError = 'No camera devices found.\n\n'
              'If using Flatpak, ensure the app has camera permissions:\n'
              'flatpak override --user --device=all com.hugocornellier.agelapse';
        });
        LogService.instance.log('Linux: no video devices found');
        return;
      }

      LogService.instance.log('Linux: found video devices: $videoDevices');

      // Try each video device until one works
      // V4L2 devices often come in pairs (video + metadata), so we need to find the right one
      String? workingDevice;
      for (final devicePath in videoDevices) {
        LogService.instance.log('Linux: trying device $devicePath...');

        _linuxPlayer?.dispose();
        _linuxPlayer = Player(
          configuration: const PlayerConfiguration(
            bufferSize: 1024 * 1024,
          ),
        );

        // Configure mpv for low-latency webcam capture
        try {
          final nativePlayer = _linuxPlayer!.platform;
          if (nativePlayer is NativePlayer) {
            // Enable loading of av:// URLs (mpv blocks them by default as "unsafe")
            await nativePlayer.setProperty('load-unsafe-playlists', 'yes');
            // Low-latency settings to minimize delay
            await nativePlayer.setProperty('profile', 'low-latency');
            await nativePlayer.setProperty('untimed', 'yes');
            await nativePlayer.setProperty('cache', 'no');
            await nativePlayer.setProperty(
                'demuxer-lavf-o', 'fflags=+nobuffer+flush_packets');
            await nativePlayer.setProperty('demuxer-readahead-secs', '0');
            LogService.instance.log('Linux: configured low-latency settings');
          }
        } catch (e) {
          LogService.instance.log('Linux: could not set mpv properties: $e');
        }

        _linuxVideoController = VideoController(_linuxPlayer!);

        // Listen for video dimensions to know when stream is actually working
        final completer = Completer<bool>();
        StreamSubscription? widthSub;
        StreamSubscription? errorSub;

        widthSub = _linuxPlayer!.stream.width.listen((width) {
          LogService.instance.log('Linux: width stream: $width');
          if (width != null && width > 1 && !completer.isCompleted) {
            LogService.instance
                .log('Linux: got valid width $width from $devicePath');
            completer.complete(true);
          }
        });

        errorSub = _linuxPlayer!.stream.error.listen((error) {
          LogService.instance.log('Linux: error stream: $error');
        });

        // Also log track info
        _linuxPlayer!.stream.track.listen((track) {
          LogService.instance.log('Linux: track info: $track');
        });

        _linuxPlayer!.stream.tracks.listen((tracks) {
          LogService.instance.log(
              'Linux: tracks: video=${tracks.video.length}, audio=${tracks.audio.length}');
        });

        // Try the av:// URL format - this is the standard for V4L2 in mpv/ffmpeg
        final url = 'av://v4l2:$devicePath';
        LogService.instance.log('Linux: opening $url');

        try {
          await _linuxPlayer!.open(
            Media(url),
            play: true,
          );

          // Wait up to 3 seconds for valid frames
          final success = await completer.future
              .timeout(const Duration(seconds: 3), onTimeout: () => false);

          if (success) {
            workingDevice = devicePath;
            LogService.instance.log('Linux: device $devicePath is working');
            widthSub.cancel();
            errorSub.cancel();
            break;
          }
        } catch (e) {
          LogService.instance.log('Linux: open failed: $e');
        }

        widthSub.cancel();
        errorSub.cancel();
        LogService.instance
            .log('Linux: device $devicePath did not produce frames');
      }

      if (workingDevice == null) {
        _linuxPlayer?.dispose();
        _linuxPlayer = null;
        _linuxVideoController = null;
        setState(() {
          _linuxCameraError = 'Could not open any camera device.\n\n'
              'Found devices: ${videoDevices.join(", ")}\n'
              'None produced valid video frames.';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _linuxCameraReady = true;
          _linuxCameraError = null;
        });
      }

      LogService.instance
          .log('Linux: camera initialized successfully with $workingDevice');
    } catch (e, st) {
      LogService.instance.log('Linux: camera init failed: $e');
      LogService.instance.log(st.toString());
      if (mounted) {
        setState(() {
          _linuxCameraError = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  /// Take a screenshot from the Linux camera using media_kit's screenshot API
  Future<Uint8List?> _captureLinuxFrame() async {
    if (_linuxPlayer == null) return null;

    try {
      LogService.instance
          .log('Linux: capturing frame via media_kit screenshot...');

      // Use media_kit's built-in screenshot functionality
      final nativePlayer = _linuxPlayer!.platform;
      if (nativePlayer is NativePlayer) {
        final bytes = await nativePlayer.screenshot(format: 'image/jpeg');
        if (bytes != null && bytes.isNotEmpty) {
          LogService.instance
              .log('Linux: captured frame, ${bytes.length} bytes');
          return bytes;
        } else {
          LogService.instance.log('Linux: screenshot returned null or empty');
          return null;
        }
      } else {
        LogService.instance
            .log('Linux: player is not NativePlayer, cannot screenshot');
        return null;
      }
    } catch (e, st) {
      LogService.instance.log('Linux: frame capture error: $e');
      LogService.instance.log(st.toString());
      return null;
    }
  }

  Widget _linuxBody() {
    return SafeArea(
      bottom: true,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: [
          if (_linuxCameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      size: 64,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _linuxCameraError!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _linuxCameraError = null;
                        });
                        _initLinuxCamera();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (!_linuxCameraReady)
            const Center(child: CircularProgressIndicator())
          else if (_linuxVideoController != null)
            Transform.scale(
              scaleX: isMirrored ? -1 : 1,
              child: Video(
                controller: _linuxVideoController!,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              ),
            ),
          if (_gridMode != GridMode.none && _linuxCameraReady)
            CameraGridOverlay(
              widget.projectId,
              _gridMode,
              offsetX,
              offsetY,
              orientation: _orientation,
            ),
          if (_isCountingDown && _pulseAnimation != null && _linuxCameraReady)
            CountdownOverlay(
              countdownValue: _countdownValue,
              pulseAnimation: _pulseAnimation!,
            ),
          if (!modifyGridMode && !_isCountingDown && _linuxCameraReady)
            _leftSideControls(),
          if (!modifyGridMode && !_isCountingDown && _linuxCameraReady)
            _rightSideControls(),
          if (!modifyGridMode && _linuxCameraReady) _cameraControl(),
          if (modifyGridMode) gridModifierOverlay(),
          if (modifyGridMode) saveGridButton(),
          if (!modifyGridMode &&
              !_isCountingDown &&
              (_gridMode == GridMode.gridOnly ||
                  _gridMode == GridMode.doubleGhostGrid ||
                  _gridMode == GridMode.ghostOnly))
            modifyGridButton(),
        ],
      ),
    );
  }

  Future<void> _takePicture() async {
    _pictureTakingCompleter = Completer<void>();

    String? debugPath; // Track for cleanup on macOS/Linux
    bool captureSuccess = false;

    try {
      if (Platform.isMacOS) {
        try {
          final photo = await _macController?.takePicture();
          final Uint8List? bytes = photo?.bytes;
          if (bytes == null) return;

          debugPath =
              '${Directory.systemTemp.path}/camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(debugPath).writeAsBytes(bytes, flush: true);

          final XFile xImage = XFile(debugPath);
          // macOS camera captures already-mirrored images when isVideoMirrored is set,
          // so we don't apply additional mirroring in post-processing
          captureSuccess = await CameraUtils.savePhoto(
            xImage,
            widget.projectId,
            false,
            null,
            false,
            applyMirroring: false,
            deviceOrientation: _orientation,
            refreshSettings: widget.refreshSettings,
          );
        } catch (e) {
          debugPrint('macOS photo save failed: $e');
        }
      } else if (Platform.isLinux) {
        try {
          LogService.instance.log('Linux: taking picture...');
          final Uint8List? bytes = await _captureLinuxFrame();
          if (bytes == null) {
            LogService.instance.log('Linux: photo capture failed');
            return;
          }
          debugPath =
              '${Directory.systemTemp.path}/camera_debug_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(debugPath).writeAsBytes(bytes, flush: true);
          final bool exists = await File(debugPath).exists();
          LogService.instance.log(
            'Linux: wrote image to $debugPath, exists=$exists, length=${bytes.length}',
          );

          final XFile xImage = XFile(debugPath);
          captureSuccess = await CameraUtils.savePhoto(
            xImage,
            widget.projectId,
            false,
            null,
            false,
            applyMirroring: isMirrored,
            deviceOrientation: _orientation,
            refreshSettings: widget.refreshSettings,
          );
          LogService.instance.log('Linux: CameraUtils.savePhoto completed');
        } catch (e, st) {
          LogService.instance.log('Linux: save failed: $e');
          LogService.instance.log(st.toString());
        }
      } else {
        final XFile image = await _controller!.takePicture();
        final Uint8List bytes = await image.readAsBytes();
        captureSuccess = await CameraUtils.savePhoto(
          image,
          widget.projectId,
          false,
          null,
          false,
          bytes: bytes,
          applyMirroring: isMirrored,
          deviceOrientation: _orientation,
          refreshSettings: widget.refreshSettings,
        );
      }

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
        Utils.navigateToScreenNoAnim(
          context,
          TookFirstPhotoPage(
            projectId: widget.projectId,
            projectName: widget.projectName,
            goToPage: widget.goToPage,
          ),
        );
      }
    } finally {
      _pictureTakingCompleter?.complete();
      _pictureTakingCompleter = null;

      // Clean up temporary image file (macOS/Linux)
      if (debugPath != null) {
        try {
          final file = File(debugPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Best-effort cleanup
        }
      }
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

    setState(() {
      modifyGridMode = false;
    });
  }

  Widget mirrorButton() => _buildButton(
        () => toggleMirror(),
        Icon(
          isMirrored ? Icons.flip : Icons.flip_outlined,
          size: 24,
          color: Colors.white,
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

    _restartCameraWithCurrentSettings();
  }

  Future<void> _restartCameraWithCurrentSettings() async {
    await _stopLiveFeed();
    await _startLiveFeed();
  }

  Widget _timerButton() => Container(
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: Colors.black54,
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
                color: Colors.white,
              ),
              if (_timerDuration > 0)
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lightBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$_timerDuration',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
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
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RotatingIconButton(
                  rotationTurns: getRotation(_orientation),
                  onPressed: toggleFlash,
                  child: Icon(
                    flashEnabled ? Icons.flash_auto : Icons.flash_off,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)
              const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: RotatingIconButton(
                rotationTurns: getRotation(_orientation),
                onPressed: _toggleGrid,
                child: _buildIcon(),
              ),
            ),
            const SizedBox(width: 12),
            _timerButton(),
          ],
        ),
      );

  Widget _rightSideControls() =>
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
          ? const SizedBox.shrink()
          : Positioned(
              bottom: 21,
              right: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(0),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RotatingIconButton(
                      rotationTurns: getRotation(_orientation),
                      onPressed: _switchLiveCamera,
                      child: Icon(
                        Platform.isIOS
                            ? Icons.flip_camera_ios_outlined
                            : Icons.flip_camera_android_outlined,
                        color: Colors.white,
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
    Widget body;
    if (Platform.isMacOS) {
      body = _macOSBody();
    } else if (Platform.isLinux) {
      body = _linuxBody();
    } else {
      body = _liveFeedBody();
    }

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, backgroundColor: Colors.black),
      body: CaptureFlashOverlay(
        key: _flashKey,
        child: body,
      ),
    );
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty) return Container();
    if (_controller == null) return Container();
    if (_controller?.value.isInitialized == false) return Container();

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
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Center(
              child: _changingCameraLens
                  ? const Center(child: CircularProgressIndicator())
                  : Platform.isWindows
                      // Windows: use FittedBox.contain - show full frame, letterbox as needed
                      ? Transform.scale(
                          scaleX: isMirrored ? -1 : 1,
                          child: AspectRatio(
                            aspectRatio: camera.aspectRatio,
                            child: CameraPreview(_controller!, child: null),
                          ),
                        )
                      : Transform.scale(
                          scale: scale,
                          child: Center(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 3, 1.0),
                              child: CameraPreview(_controller!, child: null),
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
                    color: Colors.blue.withAlpha(
                      179,
                    ), // Equivalent to opacity 0.7
                    borderRadius: BorderRadius.circular(
                      16,
                    ), // More rounded corners
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Drag guide lines to optimal position. Tap\n"
                        "checkmark to save changes. Note: Camera guide\n"
                        "lines don't affect output guide lines.",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isInfoWidgetVisible = false),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
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
            color: Colors.white,
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
                  color: Colors.white,
                ),
              ),
            // Shutter button
            ElevatedButton(
              style: takePhotoRoundStyle(),
              onPressed: _onShutterPressed,
              child: Icon(
                _isCountingDown ? Icons.close : Icons.circle,
                color: Colors.white,
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
      return const Icon(Icons.grid_off, size: 24, color: Colors.white);
    } else if (_gridMode == GridMode.gridOnly) {
      return const Icon(Icons.grid_3x3, size: 24, color: Colors.white);
    } else if (_gridMode == GridMode.ghostOnly) {
      return const FaIcon(
        FontAwesomeIcons.ghost,
        size: 24,
        color: Colors.white,
      );
    } else {
      return SvgPicture.asset(
        'assets/ghost-custom.svg',
        width: 24,
        height: 24,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
              color: const Color(0x3F84C4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "Move\nGuides",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      );

  Widget saveGridButton() => Positioned(
        top: 32,
        right: 32,
        child: _buildButton(
          () => _saveGridOffsets(),
          const Icon(Icons.check, size: 24, color: Colors.white),
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
                // The vertical line is now drawn based on offsetY.
                // The two horizontal lines are based on offsetX.

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

  Widget _buildButton(
    VoidCallback onTap,
    Widget child, {
    Color color = Colors.black54,
  }) {
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
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }

      _controller?.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Windows doesn't support image streaming, so skip it
      if (Platform.isWindows) {
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
    });
  }

  Future<void> _stopLiveFeed() async {
    if (_pictureTakingCompleter != null) {
      await _pictureTakingCompleter!.future;
    }
    // Windows doesn't use image streaming
    if (!Platform.isWindows) {
      await _controller?.stopImageStream();
    }
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex == frontFacingLensIndex
        ? backFacingLensIndex
        : frontFacingLensIndex)!;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
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

    setState(() {
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
      ..color = Colors.lightBlueAccent
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

class CameraGridOverlay extends StatefulWidget {
  final int projectId;
  final GridMode gridMode;
  final double offsetX;
  final double offsetY;
  final String orientation;

  const CameraGridOverlay(
    this.projectId,
    this.gridMode,
    this.offsetX,
    this.offsetY, {
    required this.orientation,
    super.key,
  });

  @override
  CameraGridOverlayState createState() => CameraGridOverlayState();
}

class CameraGridOverlayState extends State<CameraGridOverlay> {
  double? ghostImageOffsetX;
  double? ghostImageOffsetY;
  String? stabPhotoPath;
  ui.Image? guideImage;

  @override
  void initState() {
    super.initState();
    _initGuidePhoto();
  }

  Future<void> _initGuidePhoto() async {
    final projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final stabPhotos = await DB.instance.getStabilizedPhotosByProjectID(
      widget.projectId,
      projectOrientation,
    );

    if (stabPhotos.isNotEmpty) {
      Map<String, dynamic> guidePhoto;
      String timestamp;

      final String selectedGuidePhoto =
          await SettingsUtil.loadSelectedGuidePhoto(
        widget.projectId.toString(),
      );
      if (selectedGuidePhoto == "not set") {
        LogService.instance.log("not set");

        guidePhoto = stabPhotos.first;
        timestamp = guidePhoto['timestamp'].toString();
      } else {
        final guidePhotoRecord = await DB.instance.getPhotoById(
          selectedGuidePhoto,
          widget.projectId,
        );

        LogService.instance.log("guidePhotoRecord");
        LogService.instance.log(guidePhotoRecord.toString());

        if (guidePhotoRecord != null) {
          guidePhoto = guidePhotoRecord;
          timestamp = guidePhotoRecord['timestamp'].toString();
        } else {
          guidePhoto = stabPhotos.first;
          timestamp = guidePhoto['timestamp'].toString();
        }
      }

      final rawPhotoPath = await getRawPhotoPathFromTimestamp(timestamp);
      final stabilizedPath = await DirUtils.getStabilizedImagePath(
        rawPhotoPath,
        widget.projectId,
      );

      final projectOrientation = await SettingsUtil.loadProjectOrientation(
        widget.projectId.toString(),
      );
      final stabilizedColumn = DB.instance.getStabilizedColumn(
        projectOrientation,
      );
      final stabColOffsetX = "${stabilizedColumn}OffsetX";
      final stabColOffsetY = "${stabilizedColumn}OffsetY";
      final offsetXDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(
        timestamp,
        stabColOffsetX,
        widget.projectId,
      );
      final offsetYDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(
        timestamp,
        stabColOffsetY,
        widget.projectId,
      );
      final offsetXData = double.tryParse(offsetXDataRaw);
      final offsetYData = double.tryParse(offsetYDataRaw);
      if (!mounted) return;

      setState(() {
        ghostImageOffsetX = offsetXData;
        ghostImageOffsetY = offsetYData;
        stabPhotoPath = stabilizedPath;
      });

      _loadImage(stabilizedPath, timestamp);
    }
  }

  Future<void> _loadImage(String path, String timestamp) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('Guide image file does not exist: $path');
        return;
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
      final frameInfo = await codec.getNextFrame();
      codec.dispose();
      if (mounted) {
        final oldImage = guideImage;
        setState(() {
          guideImage = frameInfo.image;
        });
        oldImage?.dispose();
      } else {
        frameInfo.image.dispose();
      }
    } catch (e) {
      debugPrint('Error loading guide image: $e');
    }
  }

  @override
  void dispose() {
    guideImage?.dispose();
    super.dispose();
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        widget.projectId,
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _CameraGridPainter(
          widget.offsetX,
          widget.offsetY,
          ghostImageOffsetX,
          ghostImageOffsetY,
          guideImage,
          widget.projectId,
          widget.gridMode,
          widget.orientation,
        ),
      ),
    );
  }
}

class _CameraGridPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double? ghostImageOffsetX;
  final double? ghostImageOffsetY;
  final ui.Image? guideImage;
  final int projectId;
  final GridMode gridMode;
  final String orientation;

  _CameraGridPainter(
    this.offsetX,
    this.offsetY,
    this.ghostImageOffsetX,
    this.ghostImageOffsetY,
    this.guideImage,
    this.projectId,
    this.gridMode,
    this.orientation,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Determine if we are in landscape.
    final bool isLandscape =
        (orientation == "Landscape Left" || orientation == "Landscape Right");

    if (gridMode == GridMode.none) return;

    if (gridMode == GridMode.gridOnly || gridMode == GridMode.doubleGhostGrid) {
      final paint = Paint()
        ..color = Colors.white.withAlpha(153)
        ..strokeWidth = 1;

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
        double verticalLineX = 0;
        if (orientation == "Landscape Left") {
          verticalLineX = size.width * (1 - offsetY);
        } else {
          verticalLineX = size.width * offsetY;
        }

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

    if (gridMode == GridMode.ghostOnly ||
        gridMode == GridMode.doubleGhostGrid) {
      _drawGuideImage(canvas, size, isLandscape);
    }
  }

  void _drawGuideImage(Canvas canvas, Size size, bool isLandscape) {
    if (guideImage != null &&
        ghostImageOffsetX != null &&
        ghostImageOffsetY != null) {
      final imagePaint = Paint()..color = Colors.white.withAlpha(77);
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();

      final double baseDimension = isLandscape ? size.height : size.width;
      final scale = _calculateImageScale(
        baseDimension,
        imageWidth,
        imageHeight,
      );
      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;
      final eyeOffsetFromCenterInGhostPhoto =
          (0.5 - ghostImageOffsetY!) * scaledHeight;

      if (!isLandscape) {
        final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
        final difference =
            eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

        final rect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2 - difference),
          width: scaledWidth,
          height: scaledHeight,
        );
        canvas.drawImageRect(
          guideImage!,
          Offset.zero & Size(imageWidth, imageHeight),
          rect,
          imagePaint,
        );
      } else {
        final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.width;
        final difference =
            eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

        final center = Offset(size.width / 2, size.height / 2);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        final angle =
            orientation == "Landscape Left" ? math.pi / 2 : -math.pi / 2;
        canvas.rotate(angle);
        final rect = Rect.fromCenter(
          center: Offset(0, -difference),
          width: scaledWidth,
          height: scaledHeight,
        );
        canvas.drawImageRect(
          guideImage!,
          Offset.zero & Size(imageWidth, imageHeight),
          rect,
          imagePaint,
        );
        canvas.restore();
      }
    }
  }

  double _calculateImageScale(
    double baseDimension,
    double imageWidth,
    double imageHeight,
  ) {
    return (baseDimension * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) {
    return offsetX != oldDelegate.offsetX ||
        offsetY != oldDelegate.offsetY ||
        ghostImageOffsetX != oldDelegate.ghostImageOffsetX ||
        ghostImageOffsetY != oldDelegate.ghostImageOffsetY ||
        guideImage != oldDelegate.guideImage ||
        gridMode != oldDelegate.gridMode ||
        orientation != oldDelegate.orientation;
  }
}
