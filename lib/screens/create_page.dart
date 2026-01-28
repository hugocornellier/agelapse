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
import '../utils/export_naming_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/video_utils.dart';

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
  final double progressPercent;
  final Future<void> Function() stabCallback;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final Future<void> Function() recompileVideoCallback;
  final SettingsCache? settingsCache;
  final String minutesRemaining;

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
    required this.recompileVideoCallback,
    required this.settingsCache,
    required this.minutesRemaining,
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
  bool showOverlayIcon = false;
  IconData overlayIcon = Icons.play_arrow;
  bool _isWaiting = false;
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  // Manual compile state (when auto-compile is disabled)
  bool _autoCompileEnabled = true;
  bool _manualCompileInProgress = false;
  bool _videoExists = false;
  DateTime? _lastVideoDate;
  int _newPhotosSinceLastVideo = 0;

  // Video metadata for info display
  String _projectOrientation = 'portrait';
  String _stabilizationMode = 'face';

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
        if (!mounted) return;
        setState(() {
          lessThan2Photos = true;
          loadingComplete = true;
        });
        return;
      }

      // Load auto-compile setting
      _autoCompileEnabled = await SettingsUtil.loadAutoCompileVideo(
        widget.projectId.toString(),
      );

      // Cache photo count before polling loop - it won't change during compilation
      photoCount = await getStabilizedPhotoCount();

      // If manual compile is in progress, show progress UI
      if (_manualCompileInProgress) {
        // Wait handled by _triggerManualCompilation
        return;
      }

      while (
          widget.stabilizingRunningInMain || widget.videoCreationActiveInMain) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final double percentUnrounded = widget.currentFrame / photoCount! * 100;
        final String percent = percentUnrounded.toStringAsFixed(1);
        final String etaDisplay = widget.minutesRemaining.isNotEmpty
            ? widget.minutesRemaining
            : "Calculating ETA";
        setState(() {
          loadingText = "Compiling video...\n$percent% complete\n$etaDisplay";
        });
      }

      // Check if auto-compile is disabled - show manual compile options
      if (!_autoCompileEnabled) {
        await _checkVideoState();
        if (!mounted) return;
        if (!_videoExists) {
          // No video exists, show compile button only
          setState(() {
            loadingComplete = true;
          });
          return;
        }
        // Video exists, show two-option UI
        setState(() {
          loadingComplete = true;
        });
        return;
      }

      setupVideoPlayer();
    } finally {
      _isWaiting = false;
    }
  }

  /// Checks if a video exists and gets metadata for the manual compile UI.
  Future<void> _checkVideoState() async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );
    final File videoFile = File(videoPath);

    _videoExists = await videoFile.exists() && await videoFile.length() > 0;

    if (_videoExists) {
      // Get video modification date
      final stat = await videoFile.stat();
      _lastVideoDate = stat.modified;

      // Get newest video from DB to calculate new photos since
      final newestVideo = await DB.instance.getNewestVideoByProjectId(
        widget.projectId,
      );
      if (newestVideo != null) {
        final int videoPhotoCount = newestVideo['photoCount'] ?? 0;
        final int currentPhotoCount = photoCount ?? 0;
        _newPhotosSinceLastVideo = currentPhotoCount - videoPhotoCount;
        if (_newPhotosSinceLastVideo < 0) _newPhotosSinceLastVideo = 0;
      }
    }
  }

  /// Triggers manual video compilation when auto-compile is disabled.
  Future<void> _triggerManualCompilation() async {
    setState(() {
      _manualCompileInProgress = true;
      loadingComplete = false;
      loadingText = "Preparing to compile...";
    });

    // Start ETA tracking
    final int totalFrames = photoCount ?? 0;
    VideoUtils.resetVideoStopwatch(totalFrames);

    final result = await VideoUtils.createTimelapseFromProjectId(
      widget.projectId,
      (frame) {
        final double percentUnrounded =
            totalFrames > 0 ? (frame / totalFrames * 100) : 0;
        final String percent = percentUnrounded.toStringAsFixed(1);
        final String? eta = VideoUtils.calculateVideoEta(frame);
        final String etaDisplay = eta ?? "Calculating ETA";
        if (mounted) {
          setState(() {
            loadingText = "Compiling video...\n$percent% complete\n$etaDisplay";
          });
        }
      },
    );

    VideoUtils.stopVideoStopwatch();

    if (result) {
      // Mark that video is no longer needed
      DB.instance.setNewVideoNotNeeded(widget.projectId);
    }

    setState(() {
      _manualCompileInProgress = false;
    });

    // Now setup the video player to show the newly compiled video
    if (result) {
      setupVideoPlayer();
    } else {
      setState(() {
        loadingComplete = true;
        loadingText = "Failed to compile video";
      });
    }
  }

  /// Views the last compiled video without recompiling.
  void _viewLastVideo() {
    setupVideoPlayer();
  }

  /// Checks if a video file exists and is valid.
  /// Previously this would create videos directly, but that bypassed progress
  /// tracking. Now video creation is handled exclusively by the stabilization
  /// service (which properly emits progress events) or manual compilation.
  Future<bool> _checkVideoFileExists() async {
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );
    final File outFile = File(videoPath);

    final exists = await outFile.exists() && await outFile.length() > 0;
    return exists;
  }

  Future<void> setupVideoPlayer() async {
    // Check if video file exists - don't create directly, let stabilization service handle it
    final videoExists = await _checkVideoFileExists();
    if (!videoExists) {
      setState(() {
        loadingText = "Video is being compiled...";
      });
      return;
    }

    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String videoPath = await DirUtils.getVideoOutputPath(
      widget.projectId,
      projectOrientation,
    );
    final File videoFile = File(videoPath);

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

    // Load additional metadata for the info section
    _projectOrientation = projectOrientation;
    _stabilizationMode = await SettingsUtil.loadStabilizationMode();

    // Don't hide nav bar - keep the standard page layout
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
      showControlsOnInitialize: true,
      showControls: true,
      allowPlaybackSpeedChanging: true,
      playbackSpeeds: const [0.5, 1.0, 1.5, 2.0],
      hideControlsTimer: const Duration(seconds: 3),
      deviceOrientationsOnEnterFullScreen: [
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
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
      backgroundColor: AppColors.background,
      body: _readyToShowVideoPlayer()
          ? _buildVideoPlayerSection()
          : buildLoadingView(),
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

    // If auto-compile is disabled and not currently compiling, show manual options
    if (!_autoCompileEnabled &&
        !_manualCompileInProgress &&
        !widget.stabilizingRunningInMain &&
        !widget.videoCreationActiveInMain) {
      return _buildManualCompileOptions();
    }

    final bool isStabilizing = widget.stabilizingRunningInMain;
    final double percent = isStabilizing
        ? widget.progressPercent
        : (photoCount != null && photoCount! > 0)
            ? (widget.currentFrame * 100.0 / photoCount!)
            : 0.0;
    final double progressValue = percent.clamp(0.0, 100.0) / 100.0;

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
                              ? AppColors.accentLight
                              : AppColors.settingsAccent,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${percent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: AppTypography.display,
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
                style: TextStyle(
                  fontSize: AppTypography.xxl,
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
                style: TextStyle(
                  fontSize: AppTypography.md,
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
                        ? AppColors.accentLight
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

  /// Builds the manual compile options UI when auto-compile is disabled.
  Widget _buildManualCompileOptions() {
    final String dateStr = _lastVideoDate != null
        ? '${_lastVideoDate!.month}/${_lastVideoDate!.day}/${_lastVideoDate!.year}'
        : 'Unknown';

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
              Icon(
                Icons.videocam_outlined,
                size: 64,
                color: AppColors.settingsTextSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                _videoExists ? 'Video Available' : 'No Video Yet',
                style: TextStyle(
                  fontSize: AppTypography.xxl,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (_videoExists) ...[
                Text(
                  'Last compiled: $dateStr',
                  style: TextStyle(
                    fontSize: AppTypography.md,
                    color: AppColors.settingsTextSecondary,
                  ),
                ),
                if (_newPhotosSinceLastVideo > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$_newPhotosSinceLastVideo new photo${_newPhotosSinceLastVideo == 1 ? '' : 's'} since then',
                    style: TextStyle(
                      fontSize: AppTypography.md,
                      color: AppColors.settingsAccent,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  'You have ${photoCount ?? 0} stabilized photos',
                  style: TextStyle(
                    fontSize: AppTypography.md,
                    color: AppColors.settingsTextSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_videoExists) ...[
                // View Last Video button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _viewLastVideo,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('View Last Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.settingsAccent,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Compile New Video button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _triggerManualCompilation,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                      _videoExists ? 'Compile New Video' : 'Compile Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _videoExists
                        ? AppColors.settingsCardBorder
                        : AppColors.settingsAccent,
                    foregroundColor: _videoExists
                        ? AppColors.settingsTextPrimary
                        : AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Auto-compile is disabled in Settings',
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  color: AppColors.settingsTextSecondary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayerSection() {
    if (!videoPlayerBuilt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => videoPlayerBuilt = true);
      });
    }

    if (lessThan2Photos) {
      return _buildNoPhotosMessage();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = _getVideoAspectRatio();

        // Fixed heights for top and bottom sections
        const topRowHeight = 50.0;
        const normalBottomRowHeight = 140.0;
        const compactBottomRowHeight = 56.0;

        // First pass: estimate if we'll need compact mode
        final maxWidth = constraints.maxWidth - 32;
        final estimatedVideoHeight =
            constraints.maxHeight - topRowHeight - normalBottomRowHeight - 16;
        final estimatedWidth = estimatedVideoHeight * aspectRatio;
        final useCompactInfo = estimatedWidth.clamp(200.0, maxWidth) < 680;

        // Use actual bottom row height based on compact mode
        final bottomRowHeight =
            useCompactInfo ? compactBottomRowHeight : normalBottomRowHeight;
        final verticalPadding = useCompactInfo ? 8.0 : 24.0;

        // Calculate video dimensions based on available space
        final availableVideoHeight = constraints.maxHeight -
            topRowHeight -
            bottomRowHeight -
            verticalPadding;
        final videoWidthFromHeight = availableVideoHeight * aspectRatio;

        // Content width matches video width, clamped to screen bounds
        final contentWidth = videoWidthFromHeight.clamp(200.0, maxWidth);

        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row (fixed): Title
                SizedBox(
                  height: topRowHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.projectName,
                                style: TextStyle(
                                  fontSize: AppTypography.xl,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              ' · ${photoCount ?? 0} photos',
                              style: TextStyle(
                                fontSize: AppTypography.md,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _enterFullscreen,
                        icon: Icon(
                          Icons.fullscreen,
                          color: AppColors.textSecondary,
                          size: 28,
                        ),
                        tooltip: 'Fullscreen',
                      ),
                    ],
                  ),
                ),

                // Middle row: Video player sized by aspect ratio
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _buildVideoContainer(),
                ),

                // Bottom row (fixed): Info + Export
                SizedBox(
                  height: bottomRowHeight,
                  child: useCompactInfo
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              _buildCompactInfoButton(),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _buildExportButton(compact: true)),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            _buildVideoInfoSection(compact: false),
                            const SizedBox(height: 16),
                            _buildExportButton(compact: false),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoContainer() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.overlay,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.surfaceElevated,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Platform.isLinux
          ? _buildMediaKitVideoPlayer()
          : _buildChewieVideoPlayer(),
    );
  }

  Widget _buildVideoInfoSection({bool compact = false}) {
    final infoChips = [
      _VideoInfoChip(label: 'Resolution', value: resolution),
      _VideoInfoChip(label: 'Framerate', value: '${videoFps ?? 30} FPS'),
      _VideoInfoChip(label: 'Aspect', value: aspectRatio),
      _VideoInfoChip(
        label: 'Orientation',
        value: _capitalizeFirstLetter(_projectOrientation),
      ),
      _VideoInfoChip(
        label: 'Stabilization',
        value: _capitalizeFirstLetter(_stabilizationMode),
      ),
    ];

    // Compact mode: show button that opens popup
    if (compact) {
      return InkWell(
        onTap: () => _showVideoInfoPopup(infoChips),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.surfaceElevated, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Video Info',
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Icon(
              Icons.movie_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'VIDEO INFO',
              style: TextStyle(
                fontSize: AppTypography.xs,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Info Chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              infoChips.map((chip) => _buildInfoChipWidget(chip)).toList(),
        ),
      ],
    );
  }

  void _showVideoInfoPopup(List<_VideoInfoChip> chips) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.movie_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Video Info',
              style: TextStyle(
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: chips
              .map((chip) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          chip.label,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppTypography.md,
                          ),
                        ),
                        Text(
                          chip.value,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppTypography.md,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChipWidget(_VideoInfoChip chip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceElevated, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chip.label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypography.xs,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            chip.value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppTypography.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoButton() {
    final infoChips = [
      _VideoInfoChip(label: 'Resolution', value: resolution),
      _VideoInfoChip(label: 'Framerate', value: '${videoFps ?? 30} FPS'),
      _VideoInfoChip(label: 'Aspect', value: aspectRatio),
      _VideoInfoChip(
        label: 'Orientation',
        value: _capitalizeFirstLetter(_projectOrientation),
      ),
      _VideoInfoChip(
        label: 'Stabilization',
        value: _capitalizeFirstLetter(_stabilizationMode),
      ),
    ];

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _showVideoInfoPopup(infoChips),
        icon: Icon(
          Icons.info_outline,
          size: 16,
          color: AppColors.textPrimary,
        ),
        label: Text(
          'Info',
          style: TextStyle(
            fontSize: AppTypography.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: AppColors.surfaceElevated, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton({bool compact = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _shareVideo,
        icon: Icon(
          Platform.isAndroid || Platform.isIOS ? Icons.share : Icons.download,
          size: compact ? 16 : 18,
        ),
        label: Text(
          compact
              ? (Platform.isAndroid || Platform.isIOS ? 'Share' : 'Export')
              : (Platform.isAndroid || Platform.isIOS
                  ? 'Share Video'
                  : 'Export Video'),
          style: TextStyle(
            fontSize: AppTypography.sm,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentDark,
          foregroundColor: AppColors.textPrimary,
          padding:
              EdgeInsets.symmetric(vertical: 12, horizontal: compact ? 12 : 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  String _capitalizeFirstLetter(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  Widget _buildMediaKitVideoPlayer() {
    return AspectRatio(
      aspectRatio: _getVideoAspectRatio(),
      child: GestureDetector(
        onTap: togglePlayback,
        onDoubleTap: _enterFullscreen,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(
              controller: _mediaKitController!,
              controls: (state) => _buildMediaKitControls(state),
            ),
            if (showOverlayIcon)
              FadeTransition(
                opacity: _opacityAnimation,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.overlay.withAlpha(128),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(overlayIcon, color: AppColors.textPrimary, size: 50),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaKitControls(VideoState state) {
    // Simple controls for media_kit on Linux
    return Stack(
      children: [
        // Fullscreen button in top-right
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: Icon(
              Icons.fullscreen,
              color: AppColors.textPrimary,
              size: 28,
            ),
            onPressed: _enterFullscreen,
          ),
        ),
        // Playback speed in bottom-left
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.overlay.withAlpha(180),
              borderRadius: BorderRadius.circular(4),
            ),
            child: PopupMenuButton<double>(
              initialValue: playbackSpeed,
              onSelected: (speed) {
                setState(() {
                  playbackSpeed = speed;
                  _mediaKitPlayer?.setRate(speed);
                });
              },
              itemBuilder: (context) => [
                for (final speed in [0.5, 1.0, 1.5, 2.0])
                  PopupMenuItem(
                    value: speed,
                    child: Text('${speed}x'),
                  ),
              ],
              child: Text(
                '${playbackSpeed}x',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppTypography.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _getVideoAspectRatio() {
    if (Platform.isLinux) {
      // Parse aspect ratio string like "16:9" or "4:3"
      final parts = aspectRatio.split(':');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]) ?? 16;
        final h = double.tryParse(parts[1]) ?? 9;
        return w / h;
      }
      return 16 / 9;
    }
    return _videoPlayerController?.value.aspectRatio ?? 16 / 9;
  }

  void _enterFullscreen() {
    if (Platform.isLinux) {
      // For media_kit, we'd need to implement native fullscreen
      // For now, just maximize the video area
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Double-tap or use F11 for fullscreen'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _chewieController?.enterFullScreen();
    }
  }

  /// Called from MainNavigation when user taps play icon while already on CreatePage.
  /// Enters fullscreen mode if video is ready.
  void enterFullscreenFromNavBar() {
    if (_readyToShowVideoPlayer() && !lessThan2Photos) {
      _enterFullscreen();
    }
  }

  Widget _buildChewieVideoPlayer() {
    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio!,
      child: Chewie(controller: _chewieController!),
    );
  }

  Widget _buildNoPhotosMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Not Enough Photos',
              style: TextStyle(
                fontSize: AppTypography.xl,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You need at least 2 photos in your gallery to create a video.',
              style: TextStyle(
                fontSize: AppTypography.md,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => widget.goToPage(1),
              icon: const Icon(Icons.photo_library),
              label: const Text('Open Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentDark,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
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

      final String suggestedName = ExportNamingUtils.generateVideoFilename(
        projectName: widget.projectName,
      );

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

class _VideoInfoChip {
  final String label;
  final String value;

  const _VideoInfoChip({required this.label, required this.value});
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
