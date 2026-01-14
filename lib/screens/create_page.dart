import 'dart:io';

import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;

import '../services/database_helper.dart';
import '../services/settings_cache.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/video_utils.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/yellow_tip_bar.dart';

class CreatePage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final int unstabilizedPhotoCount;
  final int photoIndex;
  final int currentFrame;
  final Future<void> Function() cancelStabCallback;
  final void Function(int index) goToPage;
  final int prevIndex;
  final Future<void> Function() hideNavBar;
  final int progressPercent;
  final Future<void> Function() stabCallback;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final SettingsCache? settingsCache;

  const CreatePage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.stabilizingRunningInMain,
    required this.unstabilizedPhotoCount,
    required this.photoIndex,
    required this.videoCreationActiveInMain,
    required this.currentFrame,
    required this.cancelStabCallback,
    required this.goToPage,
    required this.prevIndex,
    required this.hideNavBar,
    required this.progressPercent,
    required this.stabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.settingsCache,
  });

  @override
  CreatePageState createState() => CreatePageState();
}

class CreatePageState extends State<CreatePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  // media_kit player for Linux (handles 8K better with texture scaling)
  Player? _mediaKitPlayer;
  VideoController? _mediaKitController;
  bool stabilizingActive = true;
  bool videoCreationActive = false;
  bool loadingComplete = false;
  bool videoPlayerBuilt = false;
  bool lessThan2Photos = false;
  String loadingText = "";
  int? videoFps;
  int? photoCount;
  String resolution = "";
  String aspectRatio = "";
  double playbackSpeed = 1.0;
  double dragStartY = 0.0;
  double dragCurrentY = 0.0;
  bool showOverlayIcon = false;
  IconData overlayIcon = Icons.play_arrow;
  bool _isWaiting = false;
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    waitForMain();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_animationController);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposeVideoControllers();
    _animationController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _disposeVideoControllers() {
    _chewieController?.dispose();
    _chewieController = null;

    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    _mediaKitPlayer?.dispose();
    _mediaKitPlayer = null;
    _mediaKitController = null;
  }

  @override
  void didUpdateWidget(CreatePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect transition: not compiling → compiling (either stabilization or video)
    final wasIdle = !oldWidget.stabilizingRunningInMain &&
        !oldWidget.videoCreationActiveInMain;
    final nowActive =
        widget.stabilizingRunningInMain || widget.videoCreationActiveInMain;

    // If we were showing the video and compilation started, reset to loading state
    if (loadingComplete && !lessThan2Photos && wasIdle && nowActive) {
      _resetToLoadingState();
    }
  }

  void _resetToLoadingState() {
    // Dispose existing video controllers
    _disposeVideoControllers();

    // Reset state flags
    setState(() {
      loadingComplete = false;
      videoPlayerBuilt = false;
      loadingText = "";
    });

    // Re-enter waiting loop
    waitForMain();
  }

  Future<void> waitForMain() async {
    // Prevent concurrent executions
    if (_isWaiting) return;
    _isWaiting = true;

    try {
      final List<Map<String, dynamic>> rawPhotos =
          await DB.instance.getPhotosByProjectID(widget.projectId);

      // Check if there are no photos
      if (rawPhotos.length < 2) {
        setState(() {
          lessThan2Photos = true;
          loadingComplete = true;
        });
        return;
      }

      while (
          widget.stabilizingRunningInMain || widget.videoCreationActiveInMain) {
        await Future.delayed(const Duration(milliseconds: 300));
        photoCount = await getStabilizedPhotoCount();
        final double percentUnrounded = widget.currentFrame / photoCount! * 100;
        final num percent = num.parse(percentUnrounded.toStringAsFixed(1));
        setState(() {
          loadingText = "Compiling video...\n$percent% complete";
        });
      }

      setupVideoPlayer();
    } finally {
      _isWaiting = false;
    }
  }

  Future<void> _maybeEncodeWindowsVideo() async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );
    final File outFile = File(videoPath);

    if (await outFile.exists() && await outFile.length() > 0) return;

    final bool ok = await VideoUtils.createTimelapseFromProjectId(
      widget.projectId,
      null,
    );

    if (!ok) {
      setState(() {
        loadingText = "ffmpeg failed to create video";
      });
    }
  }

  Future<void> setupVideoPlayer() async {
    await _maybeEncodeWindowsVideo();

    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );
    final File videoFile = File(videoPath);

    if (!await videoFile.exists() || await videoFile.length() == 0) {
      setState(() {
        loadingText = "Could not create video file";
      });
      return;
    }

    // On Linux, use media_kit directly with texture scaling for 8K support
    if (Platform.isLinux) {
      await _setupMediaKitPlayer(videoFile);
    } else {
      await _setupStandardVideoPlayer(videoFile);
    }

    setResolution();
    aspectRatio = await SettingsUtil.loadAspectRatio(
      widget.projectId.toString(),
    );
    videoFps = await SettingsUtil.loadFramerate(widget.projectId.toString());

    await widget.hideNavBar();
    playVideo();

    final bool hasViewedFirstVideo = await SettingsUtil.hasSeenFirstVideo(
      widget.projectId.toString(),
    );
    if (!hasViewedFirstVideo) {
      await SettingsUtil.setHasSeenFirstVideoToTrue(
        widget.projectId.toString(),
      );
      widget.refreshSettings();
    }
  }

  Future<void> _setupMediaKitPlayer(File videoFile) async {
    _mediaKitPlayer = Player();
    // Create video controller with scaled-down texture for preview
    // This allows 8K video to play by scaling the preview to 1080p
    _mediaKitController = VideoController(
      _mediaKitPlayer!,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false,
        width: 1920,
        height: 1080,
      ),
    );

    await _mediaKitPlayer!.open(Media(videoFile.path));
    _mediaKitPlayer!.setPlaylistMode(PlaylistMode.loop);
    _mediaKitPlayer!.setRate(playbackSpeed);

    // Wait for controller to be ready after opening media
    await _mediaKitController!.waitUntilFirstFrameRendered;
  }

  Future<void> _setupStandardVideoPlayer(File videoFile) async {
    _videoPlayerController = VideoPlayerController.file(videoFile);

    await _videoPlayerController!.initialize();
    _videoPlayerController!.setLooping(true);
    _videoPlayerController!.setPlaybackSpeed(playbackSpeed);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      autoPlay: true,
      looping: true,
      allowFullScreen: true,
      showControlsOnInitialize: false,
      hideControlsTimer: const Duration(seconds: 1),
      deviceOrientationsOnEnterFullScreen: [
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ],
      deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
    );
  }

  void playVideo() {
    setState(() {
      loadingComplete = true;
      if (Platform.isLinux) {
        _mediaKitPlayer?.play();
      } else {
        _videoPlayerController!.play();
      }
    });
  }

  void setResolution() async {
    if (Platform.isLinux) {
      // For Linux with media_kit, get resolution from settings since
      // the preview texture is scaled down
      final res = await SettingsUtil.loadVideoResolution(
        widget.projectId.toString(),
      );
      setState(() {
        resolution = res;
      });
      return;
    }

    final (double width, double height) = getVideoResolution();
    final double smallerSide = getSmallerSide(width, height);

    setState(() {
      if (smallerSide == 4320.0) {
        resolution = "8K";
      } else if (smallerSide == 2304.0) {
        resolution = "4K";
      } else if (smallerSide == 1080.0) {
        resolution = "1080p";
      } else {
        // Custom resolution - show as "1728p" format
        resolution = "${smallerSide.toInt()}p";
      }
    });
  }

  (double, double) getVideoResolution() {
    final Size size = _videoPlayerController!.value.size;
    return (size.width, size.height);
  }

  double getSmallerSide(double width, double height) =>
      width < height ? width : height;

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        widget.projectId,
      );

  void togglePlaybackSpeed() {
    setState(() {
      if (playbackSpeed == 1.0) {
        playbackSpeed = 2.0;
      } else if (playbackSpeed == 2.0) {
        playbackSpeed = 0.5;
      } else {
        playbackSpeed = 1.0;
      }
      if (Platform.isLinux) {
        _mediaKitPlayer?.setRate(playbackSpeed);
      } else {
        _videoPlayerController?.setPlaybackSpeed(playbackSpeed);
      }
    });
  }

  IconData _getPlaybackSpeedIcon() {
    if (playbackSpeed == 2.0) {
      return Icons.double_arrow;
    } else if (playbackSpeed == 0.5) {
      return Icons.slow_motion_video;
    } else {
      return Icons.one_x_mobiledata_outlined;
    }
  }

  void togglePlayback() {
    setState(() {
      if (Platform.isLinux) {
        _mediaKitPlayer?.playOrPause();
        final isPlaying = _mediaKitPlayer?.state.playing ?? false;
        overlayIcon = isPlaying ? Icons.pause : Icons.play_arrow;
      } else {
        if (_videoPlayerController!.value.isPlaying) {
          _videoPlayerController!.pause();
          overlayIcon = Icons.pause;
        } else {
          _videoPlayerController!.play();
          overlayIcon = Icons.play_arrow;
        }
      }
      showOverlayIcon = true;
      _animationController.reset();
      _animationController.forward();
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          showOverlayIcon = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragStart: (details) {
              dragStartY = details.localPosition.dy;
            },
            onVerticalDragUpdate: (details) {
              dragCurrentY = details.localPosition.dy;
              setState(() {});
            },
            onVerticalDragEnd: (details) {
              if ((dragCurrentY - dragStartY) > 100) {
                goBackToPreviousPage();
              } else {
                setState(() {
                  dragStartY = 0;
                  dragCurrentY = 0;
                });
              }
            },
            child: Transform.translate(
              offset: Offset(
                0,
                (dragCurrentY - dragStartY) > 0 ? dragCurrentY - dragStartY : 0,
              ),
              child: _readyToShowVideoPlayer()
                  ? _buildVideoPlayerSection()
                  : buildLoadingView(),
            ),
          ),
        ],
      ),
    );
  }

  bool _readyToShowVideoPlayer() {
    if (Platform.isLinux) {
      return loadingComplete &&
          (lessThan2Photos || _mediaKitController != null);
    }
    return (loadingComplete &&
        (lessThan2Photos ||
            (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)));
  }

  Widget buildLoadingView() {
    if (lessThan2Photos) {
      return _buildNoPhotosMessage();
    }

    final bool isStabilizing = widget.stabilizingRunningInMain;
    final int percent = isStabilizing
        ? widget.progressPercent
        : (photoCount != null && photoCount! > 0)
            ? ((widget.currentFrame * 100) ~/ photoCount!)
            : 0;
    final double progressValue = percent.clamp(0, 100) / 100.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Circular progress with percentage
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: progressValue,
                        strokeWidth: 8,
                        backgroundColor: AppColors.settingsCardBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isStabilizing
                              ? AppColors.lightBlue
                              : AppColors.settingsAccent,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.settingsTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Status text
              Text(
                isStabilizing ? 'Stabilizing' : 'Compiling Video',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isStabilizing
                    ? 'Aligning photos for smooth playback'
                    : 'Your video will be available here when complete',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.settingsTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Linear progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 6,
                  backgroundColor: AppColors.settingsCardBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isStabilizing
                        ? AppColors.lightBlue
                        : AppColors.settingsAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayerSection() {
    setState(() {
      videoPlayerBuilt = true;
    });

    if (lessThan2Photos) {
      return _buildNoPhotosMessage();
    }

    return Column(
      children: [
        Container(
          color: Colors.black,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () => goBackToPreviousPage(),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 35,
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: Center(
              child: GestureDetector(
                onTap: togglePlayback,
                child: Platform.isLinux
                    ? _buildMediaKitVideoPlayer()
                    : _buildChewieVideoPlayer(),
              ),
            ),
          ),
        ),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildMediaKitVideoPlayer() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Video(controller: _mediaKitController!, controls: NoVideoControls),
        if (showOverlayIcon)
          FadeTransition(
            opacity: _opacityAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(128),
                shape: BoxShape.circle,
              ),
              child: Icon(overlayIcon, color: Colors.white, size: 50),
            ),
          ),
      ],
    );
  }

  Widget _buildChewieVideoPlayer() {
    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio!,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Chewie(controller: _chewieController!),
          if (showOverlayIcon)
            Center(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(128),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(overlayIcon, color: Colors.white, size: 50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      color: Colors.black,
      height: 100,
      child: Column(
        children: [
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildIconButton(_getPlaybackSpeedIcon(), togglePlaybackSpeed),
              _buildIconButton(Icons.settings, () => _openSettings(context)),
              _buildIconButton(Icons.ios_share, _shareVideo),
            ],
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildNoPhotosMessage() {
    return const Center(
      child: YellowTipBar(
        message:
            "You need at least 2 photos in your gallery to create a video.",
      ),
    );
  }

  void goBackToPreviousPage() => widget.goToPage(widget.prevIndex);

  Widget _buildIconButton(IconData icon, [VoidCallback? onTap]) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onTap,
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          projectId: widget.projectId,
          onlyShowVideoSettings: true,
          cancelStabCallback: widget.cancelStabCallback,
          stabCallback: widget.stabCallback,
          refreshSettings: widget.refreshSettings,
          clearRawAndStabPhotos: widget.clearRawAndStabPhotos,
        );
      },
    );
  }

  Future<void> _saveVideoDesktop(String sourcePath) async {
    try {
      final File src = File(sourcePath);
      if (!await src.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video not found on disk')),
          );
        }
        return;
      }

      final String suggestedBase =
          (widget.projectName.isEmpty ? 'AgeLapse' : widget.projectName)
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final String suggestedName = '$suggestedBase.mp4';

      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'MP4 video', extensions: ['mp4']),
        ],
      );
      if (location == null) return;

      String targetPath = location.path;
      if (path.extension(targetPath).toLowerCase() != '.mp4') {
        targetPath = '$targetPath.mp4';
      }

      final File dest = File(targetPath);
      if (!await dest.parent.exists()) {
        await dest.parent.create(recursive: true);
      }

      if (await dest.exists()) {
        await dest.delete();
      }
      await src.copy(dest.path);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${dest.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save video: $e')));
    }
  }

  void _shareVideo() async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoOutputPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      final result = await SharePlus.instance.share(
        ShareParams(files: [XFile(videoOutputPath)]),
      );
      if (result.status == ShareResultStatus.success) {
        // maybe a confirmation at some point
      }
      return;
    }

    await _saveVideoDesktop(videoOutputPath);
  }

  Future<bool> videoSettingsChanged(Map<String, dynamic>? newestVideo) async =>
      await VideoUtils.videoOutputSettingsChanged(
        widget.projectId,
        newestVideo,
      );

  Future<int> getStabilizedPhotoCount() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    return await DB.instance.getStabilizedPhotoCountByProjectID(
      widget.projectId,
      projectOrientation,
    );
  }
}

class FadeInOutIcon extends StatefulWidget {
  const FadeInOutIcon({super.key});

  @override
  FadeInOutIconState createState() => FadeInOutIconState();
}

class FadeInOutIconState extends State<FadeInOutIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _controller.forward();
        }
      });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: const Icon(Icons.video_stable, size: 100.0),
        );
      },
    );
  }
}
