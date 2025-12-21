import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_view.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.projectId,
    required this.projectName,
    this.takingGuidePhoto,
    this.forceGridModeEnum,
    required this.openGallery,
    required this.refreshSettings,
    required this.goToPage,
  });

  final int projectId;
  final String projectName;
  final bool? takingGuidePhoto;
  final int? forceGridModeEnum;
  final void Function() openGallery;
  final void Function() refreshSettings;
  final void Function(int index) goToPage;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  var _cameraLensDirection = CameraLensDirection.front;

  @override
  Widget build(BuildContext context) {
    return DetectorView(
      initialCameraLensDirection: _cameraLensDirection,
      onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
      projectId: widget.projectId,
      projectName: widget.projectName,
      takingGuidePhoto: widget.takingGuidePhoto,
      forceGridModeEnum: widget.forceGridModeEnum,
      openGallery: widget.openGallery,
      refreshSettings: widget.refreshSettings,
      goToPage: widget.goToPage,
    );
  }
}

enum DetectorViewMode { liveFeed, gallery }

class DetectorView extends StatefulWidget {
  const DetectorView({
    super.key,
    required this.projectId,
    required this.projectName,
    this.initialDetectionMode = DetectorViewMode.liveFeed,
    this.initialCameraLensDirection = CameraLensDirection.front,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
    this.takingGuidePhoto,
    this.forceGridModeEnum,
    required this.openGallery,
    required this.refreshSettings,
    required this.goToPage,
  });

  final DetectorViewMode initialDetectionMode;
  final Function()? onCameraFeedReady;
  final Function(DetectorViewMode mode)? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;
  final int projectId;
  final String projectName;
  final bool? takingGuidePhoto;
  final int? forceGridModeEnum;
  final VoidCallback openGallery;
  final VoidCallback refreshSettings;
  final void Function(int index) goToPage;

  @override
  State<DetectorView> createState() => _DetectorViewState();
}

class _DetectorViewState extends State<DetectorView> {
  late DetectorViewMode _mode;

  @override
  void initState() {
    _mode = widget.initialDetectionMode;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return CameraView(
      onCameraFeedReady: widget.onCameraFeedReady,
      onDetectorViewModeChanged: _onDetectorViewModeChanged,
      initialCameraLensDirection: widget.initialCameraLensDirection,
      onCameraLensDirectionChanged: widget.onCameraLensDirectionChanged,
      projectId: widget.projectId,
      projectName: widget.projectName,
      takingGuidePhoto: widget.takingGuidePhoto,
      forceGridModeEnum: widget.forceGridModeEnum,
      openGallery: widget.openGallery,
      refreshSettings: widget.refreshSettings,
      goToPage: widget.goToPage,
    );
  }

  void _onDetectorViewModeChanged() {
    if (_mode == DetectorViewMode.liveFeed) {
      _mode = DetectorViewMode.gallery;
    } else {
      _mode = DetectorViewMode.liveFeed;
    }
    if (widget.onDetectorViewModeChanged != null) {
      widget.onDetectorViewModeChanged!(_mode);
    }
    setState(() {});
  }
}
