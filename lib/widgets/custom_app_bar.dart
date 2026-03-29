import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../styles/styles.dart';
import 'desktop_window_controls.dart';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/log_service.dart';
import '../services/stab_update_event.dart';
import '../utils/dir_utils.dart';
import '../widgets/project_select_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../services/settings_cache.dart';
import 'progress_widget.dart';

class CustomAppBar extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Function(int) goToPage;
  final double progressPercent;
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
  final bool isSyncingProjectFolder;
  final int selectedIndex;
  final Future<void> Function() stabCallback;
  final Future<void> Function() cancelStabCallback;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final Future<void> Function() recompileVideoCallback;
  final SettingsCache? settingsCache;
  final String minutesRemaining;
  final bool userRanOutOfSpace;
  final Stream<StabUpdateEvent>? stabUpdateStream;

  const CustomAppBar({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.goToPage,
    required this.progressPercent,
    required this.stabilizingRunningInMain,
    required this.videoCreationActiveInMain,
    required this.importRunningInMain,
    this.isSyncingProjectFolder = false,
    required this.selectedIndex,
    required this.stabCallback,
    required this.cancelStabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.recompileVideoCallback,
    required this.settingsCache,
    required this.minutesRemaining,
    required this.userRanOutOfSpace,
    this.stabUpdateStream,
  });

  @override
  CustomAppBarState createState() => CustomAppBarState();
}

class CustomAppBarState extends State<CustomAppBar> {
  static const double _titleBarHeight = 42;
  static const double _horizontalPadding = 12;
  static const double _centerLogoWidth = 125;
  static const List<Color> _projectBadgePalette = [
    Color(0xFF2D6CDF),
    Color(0xFF8E44AD),
    Color(0xFF0F9D7A),
    Color(0xFFE67E22),
    Color(0xFFC0392B),
    Color(0xFF1F7A8C),
    Color(0xFF8F6D1F),
    Color(0xFFB83280),
    Color(0xFF4C6FFF),
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
  ];

  String projectImagePath = '';
  bool _projectImageExists = false;

  StreamSubscription<StabUpdateEvent>? _stabUpdateSubscription;
  Timer? _profileImageDebounce;
  Timer? _thumbnailRetryTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) return;
    _loadProjectImage();
    _subscribeToStabUpdates();
  }

  @override
  void dispose() {
    _profileImageDebounce?.cancel();
    _thumbnailRetryTimer?.cancel();
    _stabUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CustomAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (Platform.isMacOS) return;

    // Reload profile image when project changes
    if (oldWidget.projectId != widget.projectId) {
      _loadProjectImage();
      return;
    }

    // Detect settings changes that affect stabilized images
    final oldCache = oldWidget.settingsCache;
    final newCache = widget.settingsCache;
    if (oldCache != null && newCache != null) {
      final orientationChanged =
          oldCache.projectOrientation != newCache.projectOrientation;
      final aspectRatioChanged = oldCache.aspectRatio != newCache.aspectRatio;

      if (orientationChanged || aspectRatioChanged) {
        setState(() {
          projectImagePath = '';
          _projectImageExists = false;
        });
      }
    }
  }

  void _subscribeToStabUpdates() {
    if (widget.stabUpdateStream == null) return;

    _stabUpdateSubscription = widget.stabUpdateStream!.listen((event) {
      if (!mounted) return;

      if (event.isCompletionEvent) {
        _loadProjectImage();
        return;
      }

      final hasValidImage =
          projectImagePath.isNotEmpty && File(projectImagePath).existsSync();
      final isStabilizedImage = projectImagePath.contains(
        DirUtils.stabilizedDirname,
      );

      if (hasValidImage && isStabilizedImage) return;

      // Debounce normal updates to prevent excessive reloads
      _profileImageDebounce?.cancel();
      _profileImageDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _loadProjectImage();
      });
    });
  }

  Future<void> _loadProjectImage() async {
    String imagePath = await ProjectSelectionSheetState.getProjectImage(
      widget.projectId,
    );

    // Only use stabilized images or GIFs - skip raw photos to avoid showing
    // raw then switching to stabilized. This keeps the experience consistent.
    final isStabilized = imagePath.contains(DirUtils.stabilizedDirname);
    final isGif = imagePath.endsWith('.gif');
    if (!isStabilized && !isGif) {
      // No stabilized image yet - will be updated via stabUpdateStream
      return;
    }

    // Try thumbnail first for stabilized images (not GIFs)
    if (isStabilized) {
      final thumbnailPath = FaceStabilizer.getStabThumbnailPath(imagePath);
      final thumbnailExists = await File(thumbnailPath).exists();
      if (thumbnailExists) {
        imagePath = thumbnailPath;
      } else {
        // Thumbnail may still be generating - schedule a retry
        _thumbnailRetryTimer?.cancel();
        _thumbnailRetryTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) _loadProjectImage();
        });
      }
    }

    // Verify file exists before setting
    final fileExists = imagePath.isNotEmpty && await File(imagePath).exists();

    if (fileExists && mounted) {
      // Evict from image cache to ensure we load fresh content
      // (same path may have new content after aspect ratio change)
      final imageProvider = FileImage(File(imagePath));
      imageProvider.evict();
      setState(() {
        projectImagePath = imagePath;
        _projectImageExists = true;
      });
    }
  }

  Color _projectBadgeColor(int projectId) {
    final int hashedId = (projectId * 2654435761) & 0x7fffffff;
    return _projectBadgePalette[hashedId % _projectBadgePalette.length];
  }

  Color _projectBadgeTextColor(Color badgeColor) {
    return ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  static void showSettingsModal(
    BuildContext context,
    int projectId,
    Future<void> Function() stabCallback,
    Future<void> Function() cancelStabCallback,
    Future<void> Function() refreshSettingsIn,
    void Function() clearRawAndStabPhotos,
    Future<void> Function() recompileVideoCallback,
    SettingsCache? settingsCache,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Use a very fast animation to minimize perceived lag from shader compilation
      transitionAnimationController: AnimationController(
        duration: const Duration(milliseconds: 150),
        vsync: Navigator.of(context),
      ),
      builder: (context) {
        return SettingsSheet(
          projectId: projectId,
          stabCallback: stabCallback,
          cancelStabCallback: cancelStabCallback,
          refreshSettings: refreshSettingsIn,
          clearRawAndStabPhotos: clearRawAndStabPhotos,
          recompileVideoCallback: recompileVideoCallback,
        );
      },
    );
  }

  static Future<bool> _isDefaultProject(int projectId) async {
    final data = await DB.instance.getSettingByTitle('default_project');
    final defaultProject = data?['value'];

    if (defaultProject == null || defaultProject == "none") {
      return false;
    } else {
      return int.tryParse(defaultProject) == projectId;
    }
  }

  void _showProjectSelectionModal(BuildContext context, int projectId) async {
    final bool isDefaultProject = await _isDefaultProject(projectId);

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return ProjectSelectionSheet(
          isDefaultProject: isDefaultProject,
          cancelStabCallback: widget.cancelStabCallback,
          currentProjectId: projectId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool useDesktopTitleBar =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            top: useDesktopTitleBar ? 0 : MediaQuery.of(context).padding.top,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.surfaceElevated.withValues(alpha: 0.49),
                width: 0.7,
              ),
            ),
            color: useDesktopTitleBar
                ? AppColors.surface
                : AppColors.backgroundDark,
          ),
          child: Column(
            children: [
              if (Platform.isMacOS)
                _buildMacTitleBar(context)
              else if (useDesktopTitleBar)
                _buildDesktopTitleBar(context),
              ProgressWidget(
                stabilizingRunningInMain: widget.stabilizingRunningInMain,
                videoCreationActiveInMain: widget.videoCreationActiveInMain,
                importRunningInMain: widget.importRunningInMain,
                isSyncingProjectFolder: widget.isSyncingProjectFolder,
                progressPercent: widget.progressPercent,
                goToPage: widget.goToPage,
                selectedIndex: widget.selectedIndex,
                minutesRemaining: widget.minutesRemaining,
                userRanOutOfSpace: widget.userRanOutOfSpace,
              ),
              if (!useDesktopTitleBar) _buildLegacyHeader(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTitleBar(BuildContext context) {
    return SizedBox(
      height: _titleBarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 120),
            child: DragToMoveArea(child: const SizedBox.expand()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            child: Row(
              children: [
                _buildProjectSwitcher(context),
                const Spacer(),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings, size: 22),
                  splashRadius: 18,
                  onPressed: () => showSettingsModal(
                    context,
                    widget.projectId,
                    widget.stabCallback,
                    widget.cancelStabCallback,
                    widget.refreshSettings,
                    widget.clearRawAndStabPhotos,
                    widget.recompileVideoCallback,
                    widget.settingsCache,
                  ),
                ),
                const SizedBox(width: 8),
                _buildWindowControls(),
              ],
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Image.asset(
                'assets/images/agelapselogo.png',
                width: _centerLogoWidth,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacTitleBar(BuildContext context) {
    return SizedBox(
      height: _titleBarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: DragToMoveArea(child: const SizedBox.expand()),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 36,
              right: _horizontalPadding,
            ),
            child: Row(
              children: [
                _buildProjectSwitcher(context),
                const Spacer(),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings, size: 22),
                  splashRadius: 18,
                  onPressed: () => showSettingsModal(
                    context,
                    widget.projectId,
                    widget.stabCallback,
                    widget.cancelStabCallback,
                    widget.refreshSettings,
                    widget.clearRawAndStabPhotos,
                    widget.recompileVideoCallback,
                    widget.settingsCache,
                  ),
                ),
              ],
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Image.asset(
                'assets/images/agelapselogo.png',
                width: _centerLogoWidth,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSwitcher(BuildContext context) {
    final String displayProjectName = widget.projectName.trim().isEmpty
        ? 'agelapse'
        : widget.projectName.trim();
    final String projectInitial =
        displayProjectName.substring(0, 1).toUpperCase();
    final Color badgeColor = _projectBadgeColor(widget.projectId);
    final Color badgeTextColor = _projectBadgeTextColor(badgeColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showProjectSelectionModal(context, widget.projectId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.center,
                child: Text(
                  projectInitial,
                  style: TextStyle(
                    color: badgeTextColor,
                    fontSize: AppTypography.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  displayProjectName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppTypography.md,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textPrimary.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindowControls() {
    return const DesktopWindowControls();
  }

  Widget _buildLegacyHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(width: 16),
        Image.asset(
          'assets/images/agelapselogo.png',
          width: 125,
          fit: BoxFit.cover,
        ),
        Expanded(child: Container()),
        InkWell(
          onTap: () => _showProjectSelectionModal(context, widget.projectId),
          child: projectImagePath.isNotEmpty && _projectImageExists
              ? CircleAvatar(
                  backgroundImage: FileImage(File(projectImagePath)),
                  onBackgroundImageError: (exception, stackTrace) {
                    // File was deleted between existsSync check and load - use fallback
                    LogService.instance.log(
                      '[CustomAppBar] onBackgroundImageError! exception=$exception, path=$projectImagePath',
                    );
                    if (projectImagePath.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          LogService.instance.log(
                            '[CustomAppBar] Resetting path due to image load error',
                          );
                          setState(() {
                            projectImagePath = '';
                            _projectImageExists = false;
                          });
                        }
                      });
                    }
                  },
                  backgroundColor: Colors.transparent,
                  radius: 13.5,
                )
              : CircleAvatar(
                  backgroundColor: AppColors.disabled,
                  radius: 13.5,
                  child: Icon(
                    Icons.person,
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    size: 18,
                  ),
                ),
        ),
        IconButton(
          icon: const Icon(Icons.settings, size: 26),
          onPressed: () => showSettingsModal(
            context,
            widget.projectId,
            widget.stabCallback,
            widget.cancelStabCallback,
            widget.refreshSettings,
            widget.clearRawAndStabPhotos,
            widget.recompileVideoCallback,
            widget.settingsCache,
          ),
        ),
      ],
    );
  }
}
