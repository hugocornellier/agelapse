import 'dart:io';
import 'package:agelapse/utils/project_utils.dart';
import 'package:agelapse/widgets/yellow_tip_bar.dart';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/database_helper.dart';
import '../services/settings_cache.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/video_utils.dart';
import '../widgets/settings_sheet.dart';

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
  final void Function() refreshSettings;
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

class CreatePageState extends State<CreatePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
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
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_animationController);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _animationController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
  }

  waitForMain() async {
    final List<Map<String, dynamic>> rawPhotos = await DB.instance.getPhotosByProjectID(widget.projectId);

    // Check if there are no photos
    if (rawPhotos.length < 2) {
      setState(() {
        lessThan2Photos = true;
        loadingComplete = true;
      });
      return;
    }

    while (widget.stabilizingRunningInMain || widget.videoCreationActiveInMain) {
      await Future.delayed(const Duration(milliseconds: 300));
      photoCount = await getStabilizedPhotoCount();
      final double percentUnrounded = widget.currentFrame / photoCount! * 100;
      final num percent = num.parse(percentUnrounded.toStringAsFixed(1));
      setState(() {
        loadingText = "Compiling video...\n$percent% complete";
      });
    }

    setupVideoPlayer();
  }

  Future<void> setupVideoPlayer() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final String videoPath = await DirUtils.getVideoOutputPath(widget.projectId, projectOrientation);
    final File videoFile = File(videoPath);
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
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.portraitUp,
      ],
    );

    setResolution();
    aspectRatio = await SettingsUtil.loadAspectRatio(widget.projectId.toString());
    videoFps = await SettingsUtil.loadFramerate(widget.projectId.toString());

    await widget.hideNavBar();
    playVideo();

    final bool hasViewedFirstVideo = await SettingsUtil.hasSeenFirstVideo(widget.projectId.toString());
    if (!hasViewedFirstVideo) {
      await SettingsUtil.setHasSeenFirstVideoToTrue(widget.projectId.toString());
      widget.refreshSettings();
    }
  }

  void playVideo() {
    setState(() {
      loadingComplete = true;
      _videoPlayerController!.play();
    });
  }

  void setResolution() {
    final (double width, double height) = getVideoResolution();
    final double smallerSide = getSmallerSide(width, height);

    setState(() {
      if (smallerSide == 2304.0) {
        resolution = "4K";
      } else if (smallerSide == 1728.0) {
        resolution = "3K";
      } else if (smallerSide == 1152.0) {
        resolution = "2K";
      } else if (smallerSide == 1080.0) {
        resolution = "1080p";
      } else {
        resolution = "${width.toInt()} x ${height.toInt()}";
      }
    });
  }

  (double, double) getVideoResolution() {
    final Size size = _videoPlayerController!.value.size;
    return (size.width, size.height);
  }

  double getSmallerSide(width, height) => width < height ? width : height;

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, widget.projectId);

  void togglePlaybackSpeed() {
    setState(() {
      if (playbackSpeed == 1.0) {
        playbackSpeed = 2.0;
      } else if (playbackSpeed == 2.0) {
        playbackSpeed = 0.5;
      } else {
        playbackSpeed = 1.0;
      }
      _videoPlayerController?.setPlaybackSpeed(playbackSpeed);
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
      if (_videoPlayerController!.value.isPlaying) {
        _videoPlayerController!.pause();
        overlayIcon = Icons.pause;
      } else {
        _videoPlayerController!.play();
        overlayIcon = Icons.play_arrow;
      }
      showOverlayIcon = true;
      _animationController.reset();
      _animationController.forward();
    });

    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        showOverlayIcon = false;
      });
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
              offset: Offset(0, (dragCurrentY - dragStartY) > 0 ? dragCurrentY - dragStartY : 0),
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
    return (loadingComplete && (lessThan2Photos || (_chewieController != null
        && _chewieController!.videoPlayerController.value.isInitialized)));
  }


  Widget buildLoadingView() {
    if (lessThan2Photos) {
      return _buildNoPhotosMessage();
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.stabilizingRunningInMain) ...[
            const AnimatedIconDemo(),
            const SizedBox(height: 64),
            const Text(
              "Stabilizing...",
              style: TextStyle(fontSize: 21.0, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              "${widget.progressPercent}%",
              style: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold, color: Colors.white),
            )
          ]
          else ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 30),
            Text(loadingText)
          ],
        ],
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
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 35),
                  ),
                  const SizedBox(width: 20)
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
                child: AspectRatio(
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
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                overlayIcon,
                                color: Colors.white,
                                size: 50,
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
        _buildActionBar(),
      ],
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
        message: "A minimum of 2 photos is required before creating a video.",
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

  void _openSettings(BuildContext context) async {
    final bool isDefaultProject = await ProjectUtils.isDefaultProject(widget.projectId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          projectId: widget.projectId,
          isDefaultProject: isDefaultProject,
          onlyShowVideoSettings: true,
          cancelStabCallback: widget.cancelStabCallback,
          stabCallback: widget.stabCallback,
          refreshSettings: widget.refreshSettings,
          clearRawAndStabPhotos: widget.clearRawAndStabPhotos,
        );
      },
    );
  }

  void _shareVideo() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final String videoOutputPath = await DirUtils.getVideoOutputPath(widget.projectId, projectOrientation);

    final result = await Share.shareXFiles([XFile(videoOutputPath)]);
    if (result.status == ShareResultStatus.success) {
      // Success
    }
  }

  Future<bool> videoSettingsChanged(newestVideo) async =>
      await VideoUtils.videoOutputSettingsChanged(widget.projectId, newestVideo);

  Future<int> getStabilizedPhotoCount() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    return (await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation)).length;
  }
}

class FadeInOutIcon extends StatefulWidget {
  const FadeInOutIcon({super.key});

  @override
  FadeInOutIconState createState() => FadeInOutIconState();
}

class FadeInOutIconState extends State<FadeInOutIcon> with SingleTickerProviderStateMixin {
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
          child: const Icon(
            Icons.video_stable,
            size: 100.0,
          ),
        );
      },
    );
  }
}

class AnimatedIconDemo extends StatefulWidget {
  const AnimatedIconDemo({super.key});

  @override
  AnimatedIconDemoState createState() => AnimatedIconDemoState();
}

class AnimatedIconDemoState extends State<AnimatedIconDemo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: -0.26, // -30 degrees in radians
      end: 0.26, // 30 degrees in radians
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 177.78,
          height: 133.335,
          decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey.shade700,
                width: 14.0,
              ),
              borderRadius: BorderRadius.circular(16)
          ),
        ),
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.rotate(
              angle: _animation.value,
              child: child,
            );
          },
          child: Container(
            width: 88.88,
            height: 50,
            color: AppColors.lightBlue,
          ),
        ),
      ],
    );
  }
}
