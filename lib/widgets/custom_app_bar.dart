import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../utils/dir_utils.dart';
import '../widgets/project_select_sheet.dart';
import '../widgets/settings_sheet.dart';
import 'package:path/path.dart' as path;
import '../services/settings_cache.dart';
import 'progress_widget.dart';

class CustomAppBar extends StatefulWidget {
  final int projectId;
  final Function(int) goToPage;
  final int progressPercent;
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
  final int selectedIndex;
  final Future<void> Function() stabCallback;
  final Future<void> Function() cancelStabCallback;
  final void Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final SettingsCache? settingsCache;
  final String minutesRemaining;
  final bool userRanOutOfSpace;

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
    required this.settingsCache,
    required this.minutesRemaining,
    required this.userRanOutOfSpace,
  });

  @override
  CustomAppBarState createState() => CustomAppBarState();
}

class CustomAppBarState extends State<CustomAppBar> {
  String projectImagePath = '';

  @override
  void initState() {
    super.initState();
    _loadProjectImage();
  }

  Future<void> _loadProjectImage() async {
    String imagePath =
        await ProjectSelectionSheetState.getProjectImage(widget.projectId);

    print('DEBUG _loadProjectImage: getProjectImage returned: $imagePath');

    if (path.dirname(imagePath).contains(DirUtils.stabilizedDirname)) {
      // Try thumbnail first
      final thumbnailPath = FaceStabilizer.getStabThumbnailPath(imagePath);
      final thumbnailExists = await File(thumbnailPath).exists();
      print('DEBUG _loadProjectImage: thumbnail path: $thumbnailPath, exists: $thumbnailExists');
      if (thumbnailExists) {
        imagePath = thumbnailPath;
      }
      // Otherwise keep the full stabilized image path
    }

    // Verify file exists before setting
    final fileExists = imagePath.isNotEmpty && await File(imagePath).exists();
    print('DEBUG _loadProjectImage: final path: $imagePath, exists: $fileExists');
    if (fileExists) {
      setState(() {
        projectImagePath = imagePath;
      });
    } else {
      print('DEBUG _loadProjectImage: NOT setting projectImagePath because file does not exist');
    }
  }

  static void showSettingsModal(
      BuildContext context,
      int projectId,
      Future<void> Function() stabCallback,
      Future<void> Function() cancelStabCallback,
      void Function() refreshSettingsIn,
      void Function() clearRawAndStabPhotos,
      SettingsCache? settingsCache) {
    final stopwatch = Stopwatch()..start();
    print('DEBUG SETTINGS [${stopwatch.elapsedMilliseconds}ms] showSettingsModal called');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Use a very fast animation to minimize perceived lag from shader compilation
      transitionAnimationController: AnimationController(
        duration: const Duration(milliseconds: 150),
        vsync: Navigator.of(context),
      ),
      builder: (context) {
        print('DEBUG SETTINGS [${stopwatch.elapsedMilliseconds}ms] builder called');
        return SettingsSheet(
          projectId: projectId,
          stabCallback: stabCallback,
          cancelStabCallback: cancelStabCallback,
          refreshSettings: refreshSettingsIn,
          clearRawAndStabPhotos: clearRawAndStabPhotos,
        );
      },
    );
    print('DEBUG SETTINGS [${stopwatch.elapsedMilliseconds}ms] showModalBottomSheet returned');
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
            cancelStabCallback: widget.cancelStabCallback);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0x7c6b6b6b),
                width: 0.7,
              ),
            ),
            color: Color(0xff0F0F0F),
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
                    child: CircleAvatar(
                      backgroundImage: projectImagePath.isNotEmpty
                          ? FileImage(File(projectImagePath)) as ImageProvider
                          : const AssetImage('assets/images/person-grey.png'),
                      onBackgroundImageError: (exception, stackTrace) {
                        print('DEBUG CircleAvatar image load error: $exception');
                        print('DEBUG CircleAvatar path was: $projectImagePath');
                        // Reset path to show fallback on next rebuild
                        if (projectImagePath.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                projectImagePath = '';
                              });
                            }
                          });
                        }
                      },
                      backgroundColor: Colors.transparent,
                      radius: 13.5,
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
