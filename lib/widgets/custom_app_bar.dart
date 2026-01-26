import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../styles/styles.dart';
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
  final Function(int) goToPage;
  final double progressPercent;
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
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
    required this.goToPage,
    required this.progressPercent,
    required this.stabilizingRunningInMain,
    required this.videoCreationActiveInMain,
    required this.importRunningInMain,
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
  String projectImagePath = '';
  bool _projectImageExists = false;

  StreamSubscription<StabUpdateEvent>? _stabUpdateSubscription;
  Timer? _profileImageDebounce;
  Timer? _thumbnailRetryTimer;

  @override
  void initState() {
    super.initState();
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

    // Reload profile image when project changes
    if (oldWidget.projectId != widget.projectId) {
      LogService.instance.log(
        '[CustomAppBar] didUpdateWidget: projectId changed ${oldWidget.projectId} -> ${widget.projectId}',
      );
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
        LogService.instance.log(
          '[CustomAppBar] didUpdateWidget: settings changed! '
          'orientation: ${oldCache.projectOrientation} -> ${newCache.projectOrientation}, '
          'aspectRatio: ${oldCache.aspectRatio} -> ${newCache.aspectRatio}',
        );
        LogService.instance.log(
          '[CustomAppBar] Resetting projectImagePath to empty (was: $projectImagePath)',
        );

        setState(() {
          projectImagePath = '';
          _projectImageExists = false;
        });
      }
    }
  }

  void _subscribeToStabUpdates() {
    if (widget.stabUpdateStream == null) {
      LogService.instance.log(
        '[CustomAppBar] _subscribeToStabUpdates: stream is null, not subscribing',
      );
      return;
    }

    LogService.instance.log(
      '[CustomAppBar] _subscribeToStabUpdates: subscribing to stream',
    );
    _stabUpdateSubscription = widget.stabUpdateStream!.listen((event) {
      if (!mounted) {
        LogService.instance.log(
          '[CustomAppBar] stabUpdateStream event received but not mounted, ignoring',
        );
        return;
      }

      LogService.instance.log(
        '[CustomAppBar] stabUpdateStream event: ${event.type}, photoIndex=${event.photoIndex}, isCompletion=${event.isCompletionEvent}',
      );

      if (event.isCompletionEvent) {
        LogService.instance.log(
          '[CustomAppBar] Completion event - calling _loadProjectImage immediately',
        );
        _loadProjectImage();
        return;
      }

      final hasValidImage =
          projectImagePath.isNotEmpty && File(projectImagePath).existsSync();
      final isStabilizedImage = projectImagePath.contains(
        DirUtils.stabilizedDirname,
      );

      LogService.instance.log(
        '[CustomAppBar] Progress event - hasValidImage=$hasValidImage, isStabilizedImage=$isStabilizedImage, currentPath=$projectImagePath',
      );

      if (hasValidImage && isStabilizedImage) {
        LogService.instance.log(
          '[CustomAppBar] Already have valid stabilized image, skipping reload',
        );
        return;
      }

      // Debounce normal updates to prevent excessive reloads
      LogService.instance.log(
        '[CustomAppBar] Scheduling debounced reload (500ms)',
      );
      _profileImageDebounce?.cancel();
      _profileImageDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          LogService.instance.log(
            '[CustomAppBar] Debounce complete, calling _loadProjectImage',
          );
          _loadProjectImage();
        }
      });
    });
  }

  Future<void> _loadProjectImage() async {
    LogService.instance.log('[CustomAppBar] _loadProjectImage called');

    String imagePath = await ProjectSelectionSheetState.getProjectImage(
      widget.projectId,
    );
    LogService.instance.log(
      '[CustomAppBar] getProjectImage returned: $imagePath',
    );

    // Only use stabilized images or GIFs - skip raw photos to avoid showing
    // raw then switching to stabilized. This keeps the experience consistent.
    final isStabilized = imagePath.contains(DirUtils.stabilizedDirname);
    final isGif = imagePath.endsWith('.gif');
    if (!isStabilized && !isGif) {
      LogService.instance.log(
        '[CustomAppBar] Image is not stabilized or GIF, skipping (path=$imagePath)',
      );
      // No stabilized image yet - will be updated via stabUpdateStream
      return;
    }

    // Try thumbnail first for stabilized images (not GIFs)
    if (isStabilized) {
      final thumbnailPath = FaceStabilizer.getStabThumbnailPath(imagePath);
      final thumbnailExists = await File(thumbnailPath).exists();
      LogService.instance.log(
        '[CustomAppBar] Checking thumbnail: $thumbnailPath, exists=$thumbnailExists',
      );
      if (thumbnailExists) {
        imagePath = thumbnailPath;
      } else {
        LogService.instance.log(
          '[CustomAppBar] Thumbnail not found, scheduling retry in 2s',
        );
        // Thumbnail may still be generating - schedule a retry
        _thumbnailRetryTimer?.cancel();
        _thumbnailRetryTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) {
            LogService.instance.log(
              '[CustomAppBar] Thumbnail retry timer fired',
            );
            _loadProjectImage();
          }
        });
      }
    }

    // Verify file exists before setting
    final fileExists = imagePath.isNotEmpty && await File(imagePath).exists();
    LogService.instance.log(
      '[CustomAppBar] Final image path: $imagePath, exists=$fileExists',
    );

    if (fileExists && mounted) {
      LogService.instance.log(
        '[CustomAppBar] Setting projectImagePath: $projectImagePath -> $imagePath',
      );
      // Evict from image cache to ensure we load fresh content
      // (same path may have new content after aspect ratio change)
      final imageProvider = FileImage(File(imagePath));
      imageProvider.evict();
      setState(() {
        projectImagePath = imagePath;
        _projectImageExists = true;
      });
    } else {
      LogService.instance.log(
        '[CustomAppBar] NOT setting path - fileExists=$fileExists, mounted=$mounted',
      );
    }
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
    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: AppColors.surfaceElevated.withValues(alpha: 0.49),
                  width: 0.7),
            ),
            color: AppColors.backgroundDark,
          ),
          child: Column(
            children: [
              ProgressWidget(
                stabilizingRunningInMain: widget.stabilizingRunningInMain,
                videoCreationActiveInMain: widget.videoCreationActiveInMain,
                importRunningInMain: widget.importRunningInMain,
                progressPercent: widget.progressPercent,
                goToPage: widget.goToPage,
                selectedIndex: widget.selectedIndex,
                minutesRemaining: widget.minutesRemaining,
                userRanOutOfSpace: widget.userRanOutOfSpace,
              ),
              Row(
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
                    onTap: () =>
                        _showProjectSelectionModal(context, widget.projectId),
                    child: projectImagePath.isNotEmpty && _projectImageExists
                        ? CircleAvatar(
                            backgroundImage: FileImage(File(projectImagePath)),
                            onBackgroundImageError: (exception, stackTrace) {
                              // File was deleted between existsSync check and load - use fallback
                              LogService.instance.log(
                                '[CustomAppBar] onBackgroundImageError! exception=$exception, path=$projectImagePath',
                              );
                              if (projectImagePath.isNotEmpty) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
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
                              color:
                                  AppColors.textPrimary.withValues(alpha: 0.7),
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}
