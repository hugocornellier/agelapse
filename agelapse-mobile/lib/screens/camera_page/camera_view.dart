import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/database_helper.dart';
import '../../styles/styles.dart';
import '../../utils/camera_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/utils.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../utils/settings_utils.dart';
import '../guide_mode_tutorial_page.dart';
import '../took_first_photo_page.dart';
import 'grid_mode.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;

class RotatingIconButton extends StatelessWidget {
  final Widget child;
  final double rotationTurns;
  final VoidCallback onPressed;
  final Duration duration;
  const RotatingIconButton({Key? key, required this.child, required this.rotationTurns, required this.onPressed, this.duration = const Duration(milliseconds: 300)}) : super(key: key);
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
  final CustomPaint? customPaint;
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;
  final int projectId;
  final String projectName;
  final bool? takingGuidePhoto;
  final int? forceGridModeEnum;
  final VoidCallback openGallery;
  final VoidCallback refreshSettings;
  final void Function(int index) goToPage;

  const CameraView({
    super.key,
    required this.customPaint,
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

class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;
  int? frontFacingLensIndex;
  int? backFacingLensIndex;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  bool _changingCameraLens = false;
  bool _showFlash = false;
  bool backIndexSet = false;
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

  @override
  void initState() {
    super.initState();
    _initialize();

    accelerometerEventStream().listen((AccelerometerEvent event) {
      final potentialOrientation = event.x.abs() > event.y.abs()
          ? (event.x > 0 ? "Landscape Left" : "Landscape Right")
          : (event.y > 0 ? "Portrait Up" : "Portrait Down");

      if (potentialOrientation == "Portrait Down" &&
          (_orientation == "Landscape Left" || _orientation == "Landscape Right")) {
        return;
      }

      if (potentialOrientation != _orientation) {
        setState(() {
          _orientation = potentialOrientation;
        });

        resetOffsetValues(potentialOrientation);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getWidgetHeight();
    });
  }

  void _getWidgetHeight() {
    final RenderBox? renderBox = _widgetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      setState(() {
        _widgetHeight = renderBox.size.height;
      });
    }
  }

  void _initialize() async {
    final bool hasSeenGuideModeTut = await SettingsUtil.hasSeenGuideModeTut(widget.projectId.toString());
    final bool hasTakenFirstPhoto = await SettingsUtil.hasTakenFirstPhoto(widget.projectId.toString());
    final bool mirrorSettingBool = await SettingsUtil.loadCameraMirror(widget.projectId.toString());

    final String mirrorSetting = mirrorSettingBool.toString();

    if (mirrorSetting.isNotEmpty) {
      setState(() => isMirrored = mirrorSetting == 'true');
    }

    if (hasTakenFirstPhoto && !hasSeenGuideModeTut) {
      Utils.navigateToScreenNoAnim(
        context,
        GuideModeTutorialPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          goToPage: widget.goToPage,
          sourcePage: "CameraView"
        ),
      );

      return;
    }

    final int gridModeIndex = await SettingsUtil.loadGridModeIndex(widget.projectId.toString());
    setState(() {
      _gridMode = GridMode.values[gridModeIndex];
    });

    final projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final stabPhotos = await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation);
    if (stabPhotos.isNotEmpty) {
      setState(() {
        showGuidePhoto = true;
      });
    }

    takingGuidePhoto = (widget.takingGuidePhoto != null && widget.takingGuidePhoto == true);

    final String flashSetting = await SettingsUtil.loadCameraFlash(widget.projectId.toString());
    if (flashSetting == 'off') flashEnabled = false;

    _cameras = await availableCameras();

    if (widget.forceGridModeEnum != null) {
      _gridMode = GridMode.values[widget.forceGridModeEnum!];
    } else if (!takingGuidePhoto) {
      final bool enableGridSetting = await SettingsUtil.loadEnableGrid();
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
  }

  @override
  void dispose() {
    _stopLiveFeed();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _takePicture() async {
    _pictureTakingCompleter = Completer<void>();

    setState(() => _showFlash = true);
    await CameraUtils.flashAndVibrate();
    setState(() => _showFlash = false);

    try {
      final XFile? image = await _controller?.takePicture();
      if (image != null) {
        CameraUtils.savePhoto(
          image,
          widget.projectId,
          false,
          null,
          false,
          refreshSettings: widget.refreshSettings,
          applyMirroring: isMirrored,
          deviceOrientation: _orientation,
        );

        final bool hasTakenFirstPhoto = await SettingsUtil.hasTakenFirstPhoto(widget.projectId.toString());
        if (!hasTakenFirstPhoto) {
          await SettingsUtil.setHasTakenFirstPhotoToTrue(widget.projectId.toString());
          Utils.navigateToScreenNoAnim(
            context,
            TookFirstPhotoPage(
              projectId: widget.projectId,
              projectName: widget.projectName,
              goToPage: widget.goToPage
            ),
          );
        }
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
    final String guideOffSetXColName = _orientation == 'Portrait Up' ? "guideOffsetXPortrait" : "guideOffsetXLandscape";
    final String guideOffSetYColName = _orientation == 'Portrait Up' ? "guideOffsetYPortrait" : "guideOffsetYLandscape";

    await DB.instance.setSettingByTitle(guideOffSetXColName, offsetX.toString(), widget.projectId.toString());
    await DB.instance.setSettingByTitle(guideOffSetYColName, offsetY.toString(), widget.projectId.toString());

    setState(() {
      modifyGridMode = false;
    });
  }

  Widget mirrorButton() => _buildButton(() => toggleMirror(),
    Icon(isMirrored ? Icons.flip : Icons.flip_outlined, size: 24, color: Colors.white),
  );

  void toggleMirror() {
    DB.instance.setSettingByTitle('camera_mirror', isMirrored.toString(), widget.projectId.toString());

    setState(() {
      isMirrored = !isMirrored;
    });

    _restartCameraWithCurrentSettings();
  }

  Future<void> _restartCameraWithCurrentSettings() async {
    await _stopLiveFeed();
    await _startLiveFeed();
  }

  Widget _leftSideControls() => Positioned(
    bottom: 21,
    left: 16,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: RotatingIconButton(
            child: Icon(flashEnabled ? Icons.flash_auto : Icons.flash_off, size: 24, color: Colors.white),
            rotationTurns: getRotation(_orientation),
            onPressed: toggleFlash,
          ),
        ),
        SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: RotatingIconButton(
            child: _buildIcon(),
            rotationTurns: getRotation(_orientation),
            onPressed: _toggleGrid,
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
        // mirrorButton(),
        SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: RotatingIconButton(
            child: Icon(
              Platform.isIOS ? Icons.flip_camera_ios_outlined : Icons.flip_camera_android_outlined,
              color: Colors.white,
              size: 27,
            ),
            rotationTurns: getRotation(_orientation),
            onPressed: _switchLiveCamera,
          ),
        ),

      ],
    ),
  );

  void _toggleGrid() {
    setState(() {
      if (showGuidePhoto) {
        _gridMode = GridMode.values[(_gridMode.index + 1) % GridMode.values.length];
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
      appBar: AppBar(toolbarHeight: 0, backgroundColor: Colors.black),
      body: _liveFeedBody(),
    );
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty) return Container();
    if (_controller == null) return Container();
    if (_controller?.value.isInitialized == false) return Container();

    final camera = _controller!.value;
    final size = MediaQuery.of(context).size;
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
                  : Transform.scale(
                      scale: scale,
                      child: Center(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..scale(isMirrored ? -1.0 : 1.0, 1.0, 1.0),
                          child: CameraPreview(
                            _controller!,
                            child: null,
                          ),
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
            if (_showFlash) ...[
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showFlash ? 1.0 : 0.0,
                child: Container(color: Colors.black),
              ),
            ],
            if (!modifyGridMode) _leftSideControls(),
            if (!modifyGridMode) _rightSideControls(),
            if (!modifyGridMode) _cameraControl(),
            if (modifyGridMode) gridModifierOverlay(),
            if (modifyGridMode && _isInfoWidgetVisible) ...[
              Positioned(
                bottom: 32,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(179), // Equivalent to opacity 0.7
                    borderRadius: BorderRadius.circular(16), // More rounded corners
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
                        onTap: () => setState(() => _isInfoWidgetVisible = false),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
            if (modifyGridMode)
              saveGridButton(),
            if (!modifyGridMode && (_gridMode == GridMode.gridOnly || _gridMode == GridMode.doubleGhostGrid || _gridMode == GridMode.ghostOnly))
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
      Icon(flashEnabled ? Icons.flash_auto : Icons.flash_off, size: 24, color: Colors.white),
    ),
  );

  Widget gridButton() => Positioned(
    bottom: 21,
    left: 64,
    child: _buildButton(
          () => _toggleGrid(),
      _buildIcon(),
    ),
  );

  Widget _switchLiveCameraToggle() {
    return Positioned(
      bottom: 21,
      right: 16,
      child: _buildButton(
        _switchLiveCamera,
        Icon(
          Platform.isIOS ? Icons.flip_camera_ios_outlined : Icons.flip_camera_android_outlined,
          color: Colors.white,
          size: 27,
        ),
      ),
    );
  }

  Widget _cameraControl() {
    return Positioned(
      bottom: 21 - 4,
      child: ElevatedButton(
        style: takePhotoRoundStyle(),
        onPressed: () => _takePicture(),
        child: const Icon(Icons.circle, color: Colors.white, size: 70),
      ),
    );
  }

  Widget _buildIcon() {
    if (_gridMode == GridMode.none) {
      return const Icon(
        Icons.grid_off,
        size: 24,
        color: Colors.white,
      );
    } else if (_gridMode == GridMode.gridOnly) {
      return const Icon(
        Icons.grid_3x3,
        size: 24,
        color: Colors.white,
      );
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
      rotationTurns: getRotation(_orientation),
      onPressed: _toggleModifyGridMode,
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
              final bool isLandscape = (_orientation == "Landscape Left" || _orientation == "Landscape Right");

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
              final bool isLandscape = (_orientation == "Landscape Left" || _orientation == "Landscape Right");

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
              child: Container(
                color: Colors.transparent,
              ),
            ),
          )

        ],
      ),
    );
  }

  Future<void> toggleFlash() async {
    setState(() => flashEnabled = !flashEnabled);
    if (flashEnabled) {
      await _controller?.setFlashMode(FlashMode.auto);
      DB.instance.setSettingByTitle('camera_flash', 'auto', widget.projectId.toString());
      return;
    }
    await _controller?.setFlashMode(FlashMode.off);
    DB.instance.setSettingByTitle('camera_flash', 'off', widget.projectId.toString());
  }

  Widget _buildButton(onTap, child, {Color color = Colors.black54}) {
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

  Widget _exposureControl() => ConstrainedBox(
    constraints: const BoxConstraints(
      maxHeight: 250,
    ),
    child: Column(children: [
      Container(
        width: 55,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Text(
              '${_currentExposureOffset.toStringAsFixed(1)}x',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
      Expanded(
        child: RotatedBox(
          quarterTurns: 3,
          child: SizedBox(
            height: 30,
            child: Slider(
              value: _currentExposureOffset,
              min: _minAvailableExposureOffset,
              max: _maxAvailableExposureOffset,
              activeColor: Colors.white,
              inactiveColor: Colors.white30,
              onChanged: (value) async {
                setState(() {
                  _currentExposureOffset = value;
                });
                await _controller?.setExposureOffset(value);
              },
            ),
          ),
        ),
      )
    ]),
  );

  Future _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }

      _controller?.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _controller?.startImageStream(_processCameraImage).then((value) {
        if (widget.onCameraFeedReady != null) {
          widget.onCameraFeedReady!();
        }
        if (widget.onCameraLensDirectionChanged != null) {
          widget.onCameraLensDirectionChanged!(camera.lensDirection);
        }
      });
      _controller?.getMinZoomLevel().then((value) {});
      _controller?.getMaxZoomLevel().then((value) {});
      _currentExposureOffset = 0.0;
      _controller?.getMinExposureOffset().then((value) {
        _minAvailableExposureOffset = value;
      });
      _controller?.getMaxExposureOffset().then((value) {
        _maxAvailableExposureOffset = value;
      });
      setState(() {});
    });
  }

  Future<void> _stopLiveFeed() async {
    if (_pictureTakingCompleter != null) {
      await _pictureTakingCompleter!.future;
    }
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex == frontFacingLensIndex ? backFacingLensIndex : frontFacingLensIndex)!;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  Future<void> setFocusPoint(Offset point) async {
    if (_controller!.value.isInitialized && _controller!.value.focusPointSupported) {
      await _controller?.setFocusPoint(point);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {

  }

  Future<void> resetOffsetValues(String potentialOrientation) async {
    String customOrientation;
    if (potentialOrientation == "Landscape Left" || potentialOrientation == "Landscape Right") {
      customOrientation = "landscape";
    } else {
      customOrientation = "portrait";
    }

    final String offsetXStr = await SettingsUtil.loadGuideOffsetXCustomOrientation(
      widget.projectId.toString(),
      customOrientation,
    );
    final String offsetYStr = await SettingsUtil.loadGuideOffsetYCustomOrientation(
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
      canvas.drawLine(Offset(verticalLineX, 0), Offset(verticalLineX, size.height), paint);

      final offsetYInPixels = size.height * offsetX;
      final centerY = size.height / 2;
      final topY = centerY - offsetYInPixels;
      final bottomY = centerY + offsetYInPixels;
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), paint);
      canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CameraGridOverlay extends StatefulWidget {
  final int projectId;
  final GridMode gridMode;
  final double offsetX;
  final double offsetY;
  final String orientation;

  const CameraGridOverlay(this.projectId, this.gridMode, this.offsetX, this.offsetY, {
    required this.orientation,
    super.key
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
    final projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final stabPhotos = await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation);

    if (stabPhotos.isNotEmpty) {
      Map<String, dynamic> guidePhoto;
      String timestamp;

      final String selectedGuidePhoto = await SettingsUtil.loadSelectedGuidePhoto(widget.projectId.toString());
      if (selectedGuidePhoto == "not set") {
        print("not set");

        guidePhoto = stabPhotos.first;
        timestamp = guidePhoto['timestamp'].toString();
      } else {
        final guidePhotoRecord = await DB.instance.getPhotoById(selectedGuidePhoto, widget.projectId);

        print("guidePhotoRecord");
        print(guidePhotoRecord);

        if (guidePhotoRecord != null) {
          guidePhoto = guidePhotoRecord;
          timestamp = guidePhotoRecord['timestamp'].toString();
        } else {
          guidePhoto = stabPhotos.first;
          timestamp = guidePhoto['timestamp'].toString();
        }
      }

      final rawPhotoPath = await getRawPhotoPathFromTimestamp(timestamp);
      final stabilizedPath = await DirUtils.getStabilizedImagePath(rawPhotoPath, widget.projectId);

      final projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
      final stabilizedColumn = DB.instance.getStabilizedColumn(projectOrientation);
      final stabColOffsetX = "${stabilizedColumn}OffsetX";
      final stabColOffsetY = "${stabilizedColumn}OffsetY";
      final offsetXDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(timestamp, stabColOffsetX);
      final offsetYDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(timestamp, stabColOffsetY);
      final offsetXData = double.tryParse(offsetXDataRaw);
      final offsetYData = double.tryParse(offsetYDataRaw);

      setState(() {
        ghostImageOffsetX = offsetXData;
        ghostImageOffsetY = offsetYData;
        stabPhotoPath = stabilizedPath;
      });

      _loadImage(stabilizedPath, timestamp);
    }
  }

  Future<void> _loadImage(String path, String timestamp) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    setState(() {
      guideImage = frameInfo.image;
    });
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, widget.projectId);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _CameraGridPainter(widget.offsetX, widget.offsetY, ghostImageOffsetX, ghostImageOffsetY, guideImage, widget.projectId, widget.gridMode, widget.orientation),
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

    if (gridMode == GridMode.gridOnly || gridMode == GridMode.doubleGhostGrid ) {
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

        canvas.drawLine(Offset(verticalLineX, 0), Offset(verticalLineX, size.height), paint);

        final offsetYInPixels = size.height * offsetX;
        final centerY = size.height / 2;
        final topY = centerY - offsetYInPixels;
        final bottomY = centerY + offsetYInPixels;
        canvas.drawLine(Offset(0, topY), Offset(size.width, topY), paint);
        canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
      }
    }

    if (gridMode == GridMode.ghostOnly || gridMode == GridMode.doubleGhostGrid) {
      _drawGuideImage(canvas, size, isLandscape);
    }
  }

  void _drawGuideImage(Canvas canvas, Size size, bool isLandscape) {
    if (guideImage != null && ghostImageOffsetX != null && ghostImageOffsetY != null) {
      final imagePaint = Paint()..color = Colors.white.withAlpha(77);
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();

      final double baseDimension = isLandscape ? size.height : size.width;
      final scale = _calculateImageScale(baseDimension, imageWidth, imageHeight);
      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;
      final eyeOffsetFromCenterInGhostPhoto = (0.5 - ghostImageOffsetY!) * scaledHeight;

      if (!isLandscape) {
        final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
        final difference = eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

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
        final difference = eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

        final center = Offset(size.width / 2, size.height / 2);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        final angle = orientation == "Landscape Left" ? math.pi / 2 : -math.pi / 2;
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

  double _calculateImageScale(double baseDimension, double imageWidth, double imageHeight) {
    return (baseDimension * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
