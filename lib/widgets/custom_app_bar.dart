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
  _CustomAppBarState createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  String projectImagePath = '';

  @override
  void initState() {
    super.initState();
    _loadProjectImage();
  }

  Future<void> _loadProjectImage() async {
    String imagePath =
        await ProjectSelectionSheetState.getProjectImage(widget.projectId);

    if (path.dirname(imagePath).contains(DirUtils.stabilizedDirname)) {
      imagePath = FaceStabilizer.getStabThumbnailPath(imagePath);
    }

    setState(() {
      projectImagePath = imagePath;
    });
  }

  static void showSettingsModal(
      BuildContext context,
      int projectId,
      Future<void> Function() stabCallback,
      Future<void> Function() cancelStabCallback,
      void Function() refreshSettingsIn,
      void Function() clearRawAndStabPhotos,
      SettingsCache? settingsCache) async {
    final bool isDefaultProject = await _isDefaultProject(projectId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          projectId: projectId,
          isDefaultProject: isDefaultProject,
          stabCallback: stabCallback,
          cancelStabCallback: cancelStabCallback,
          refreshSettings: refreshSettingsIn,
          clearRawAndStabPhotos: clearRawAndStabPhotos,
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
                          ? FileImage(File(projectImagePath))
                          : null,
                      backgroundColor:
                          projectImagePath.isEmpty ? Colors.grey : null,
                      radius: 13.5,
                      child: projectImagePath.isEmpty
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
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
