import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../screens/create_project_page.dart';
import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/gallery_utils.dart';
import '../utils/project_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../screens/projects_page.dart';
import 'bottom_sheet_container.dart';
import 'bottom_sheet_header.dart';
import 'delete_project_dialog.dart';
import 'dialog_button_row.dart';
import 'empty_state.dart';
import 'main_navigation.dart';
import 'option_tile.dart';
import 'styled_text_field.dart';

class ProjectSelectionSheet extends StatefulWidget {
  final bool isDefaultProject;
  final bool showCloseButton;
  final void Function() cancelStabCallback;
  final int? currentProjectId;
  final bool isFullPage;

  const ProjectSelectionSheet({
    super.key,
    required this.isDefaultProject,
    this.showCloseButton = true,
    required this.cancelStabCallback,
    this.currentProjectId,
    this.isFullPage = false,
  });

  @override
  ProjectSelectionSheetState createState() => ProjectSelectionSheetState();
}

class ProjectSelectionSheetState extends State<ProjectSelectionSheet> {
  List<Map<String, dynamic>> _projects = [];
  final TextEditingController _editProjectNameController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _getProjects();
  }

  @override
  void dispose() {
    _editProjectNameController.dispose();
    super.dispose();
  }

  Future<void> _getProjects() async {
    final List<Map<String, dynamic>> projects =
        await DB.instance.getAllProjects();
    setState(() => _projects = projects);
  }

  Future<void> _onNewButtonTapped() async {
    Utils.navigateToScreenReplace(context, const CreateProjectPage());
  }

  static Future<String> getProjectImage(int projectId) async {
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(
      projectId,
    );
    final String activeProjectOrientation =
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String bgColor = await SettingsUtil.loadBackgroundColor(
      projectId.toString(),
    );
    final bool isTransparent = SettingsUtil.isTransparent(bgColor);

    final String videoOutputPath = await DirUtils.getVideoOutputPath(
      projectId,
      activeProjectOrientation,
      isTransparent: isTransparent,
    );
    final String gifPath = videoOutputPath.replaceAll(
      path.extension(videoOutputPath),
      ".gif",
    );
    if (await File(gifPath).exists()) {
      return gifPath;
    }

    final String stabilizedDirActivePath = path.join(
      stabilizedDirPath,
      activeProjectOrientation,
    );
    String? pngPath =
        await GalleryUtils.checkForStabilizedImage(stabilizedDirActivePath);
    if (pngPath != null) {
      return pngPath;
    }

    final String stabilizedDirInactivePath = path.join(
      stabilizedDirPath,
      activeProjectOrientation == "portrait" ? "landscape" : "portrait",
    );
    pngPath =
        await GalleryUtils.checkForStabilizedImage(stabilizedDirInactivePath);
    if (pngPath != null) {
      return pngPath;
    }

    final String rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
    final Directory rawPhotoDir = Directory(rawPhotoDirPath);
    final bool dirExists = await rawPhotoDir.exists();
    if (!dirExists) {
      return "";
    }

    final files = await rawPhotoDir.list().toList();
    final imageFiles = files
        .where((file) => file is File && Utils.isImage(file.path))
        .toList();
    if (imageFiles.isEmpty) {
      return "";
    }

    final minFile = imageFiles.reduce(
      (a, b) =>
          GalleryUtils.compareByNumericBasename(a.path, b.path) <= 0 ? a : b,
    );
    return minFile.path;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFullPage) {
      return _buildFullPageLayout(context);
    }
    return _buildSheetLayout(context);
  }

  Widget _buildFullPageLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;

    return Container(
      color: AppColors.backgroundDark,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate grid columns based on width
            int crossAxisCount = 1;
            if (isDesktop) {
              if (constraints.maxWidth > 1200) {
                crossAxisCount = 4;
              } else if (constraints.maxWidth > 900) {
                crossAxisCount = 3;
              } else {
                crossAxisCount = 2;
              }
            } else if (constraints.maxWidth > 500) {
              crossAxisCount = 2;
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 48.0 : 20.0,
                    vertical: isDesktop ? 32.0 : 16.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      _buildFullPageHeader(isDesktop),
                      SizedBox(height: isDesktop ? 32 : 24),
                      // Content
                      Expanded(
                        child: _projects.isEmpty
                            ? _buildEmptyState()
                            : isDesktop
                                ? _buildProjectGrid(crossAxisCount)
                                : _buildProjectList(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFullPageHeader(bool isDesktop) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Projects',
          style: TextStyle(
            fontSize: isDesktop ? AppTypography.display : AppTypography.xxxl,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _onNewButtonTapped,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 16 : 12,
                vertical: isDesktop ? 10 : 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.settingsAccent,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    size: isDesktop ? 20 : 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'New Project',
                    style: TextStyle(
                      fontSize: isDesktop ? AppTypography.lg : AppTypography.sm,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectGrid(int crossAxisCount) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: _projects.length,
      itemBuilder: (context, index) {
        return _buildProjectCard(_projects[index]);
      },
    );
  }

  Widget _buildProjectList() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            _projects.map((project) => _buildProjectItem(project)).toList(),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    return FutureBuilder<String>(
      future: getProjectImage(project['id']),
      builder: (context, snapshot) {
        return FutureBuilder<bool>(
          future: ProjectUtils.photoWasTakenToday(project['id']),
          builder: (context, photoSnapshot) {
            final bool takenToday = photoSnapshot.data ?? false;
            final bool hasImage = snapshot.hasData &&
                snapshot.data!.isNotEmpty &&
                File(snapshot.data!).existsSync();

            return GestureDetector(
              onTap: () => navigateToProject(context, project),
              onSecondaryTap: () => _showProjectOptionsPopup(context, project),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.textPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thumbnail area
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          child: hasImage
                              ? Image.file(
                                  File(snapshot.data!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildCardPlaceholder(),
                                )
                              : _buildCardPlaceholder(),
                        ),
                      ),
                      // Info area
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                project['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppTypography.lg,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: takenToday
                                          ? AppColors.success
                                          : AppColors.warning,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      takenToday
                                          ? 'Photo taken today'
                                          : 'Photo not taken',
                                      style: TextStyle(
                                        fontSize: AppTypography.sm,
                                        color: AppColors.textPrimary.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCardPlaceholder() {
    return Center(
      child: Icon(
        Icons.person_outline,
        size: 48,
        color: AppColors.textPrimary.withValues(alpha: 0.2),
      ),
    );
  }

  Widget _buildSheetLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0),
      width: MediaQuery.of(context).size.height * 0.9,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Projects',
                    style: TextStyle(
                      fontSize: AppTypography.xxl,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _onNewButtonTapped,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.settingsAccent,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'New',
                              style: TextStyle(
                                fontSize: AppTypography.sm,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.showCloseButton)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.close,
                        color: AppColors.textPrimary.withValues(alpha: 0.7),
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Project list
          Flexible(
            child: _projects.isEmpty
                ? _buildEmptyState()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _projects
                          .map((project) => _buildProjectItem(project))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Icons.folder_outlined,
      title: 'No projects yet',
      subtitle: 'Tap "+ New" to create your first project',
    );
  }

  void navigateToProject(BuildContext context, Map<String, dynamic> project) {
    widget.cancelStabCallback();

    if (widget.showCloseButton) {
      Navigator.of(context).pop();
    }

    Utils.navigateToScreenReplaceNoAnim(
      context,
      MainNavigation(
        projectId: project['id'],
        projectName: project['name'],
        showFlashingCircle: false,
      ),
    );
  }

  void _showProjectOptionsPopup(
    BuildContext context,
    Map<String, dynamic> project,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BottomSheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BottomSheetHeader(
                title: project['name'],
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 16),
              // Options
              OptionTile(
                icon: Icons.edit_outlined,
                title: 'Rename Project',
                subtitle: 'Change the project name',
                onTap: () {
                  Navigator.pop(context);
                  _showEditProjectNamePopup(context, project);
                },
              ),
              const SizedBox(height: 8),
              OptionTile(
                icon: Icons.delete_outline,
                title: 'Delete Project',
                subtitle: 'Permanently remove this project',
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteProjectPopup(context, project);
                },
                isDestructive: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditProjectNamePopup(
    BuildContext context,
    Map<String, dynamic> project,
  ) {
    _editProjectNameController.text = project['name'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: BottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BottomSheetHeader(
                  title: 'Rename Project',
                  onClose: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 20),
                // Input field
                StyledTextField(
                  controller: _editProjectNameController,
                  hintText: 'Enter project name',
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // Buttons
                DialogButtonRow(
                  actionLabel: 'Save',
                  actionColor: AppColors.settingsAccent,
                  onCancel: () => Navigator.pop(context),
                  onAction: () async {
                    final newName = _editProjectNameController.text;
                    if (newName.trim().isEmpty) return;
                    await DB.instance.updateProjectName(
                      project['id'],
                      newName,
                    );
                    _getProjects();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteProjectPopup(
    BuildContext context,
    Map<String, dynamic> project,
  ) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDeleteProjectDialog(
      context: context,
      projectName: project['name'],
    );

    if (confirmed == true) {
      final deletedProjectId = project['id'];
      await ProjectUtils.deleteProject(deletedProjectId);

      // If we deleted the currently active project, navigate to ProjectsPage
      if (widget.currentProjectId != null &&
          widget.currentProjectId == deletedProjectId &&
          mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ProjectsPage()),
          (route) => false,
        );
      } else {
        _getProjects();
      }
    }
  }

  Widget _buildProjectItem(Map<String, dynamic> project) {
    return FutureBuilder<String>(
      future: getProjectImage(project['id']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildProjectItemSkeleton();
        }
        return FutureBuilder<bool>(
          future: ProjectUtils.photoWasTakenToday(project['id']),
          builder: (context, photoSnapshot) {
            if (photoSnapshot.connectionState == ConnectionState.waiting) {
              return _buildProjectItemSkeleton();
            }
            final bool takenToday = photoSnapshot.data ?? false;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => navigateToProject(context, project),
                onLongPress: () => _showProjectOptionsPopup(context, project),
                onSecondaryTap: () =>
                    _showProjectOptionsPopup(context, project),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.textPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: snapshot.hasData &&
                                snapshot.data!.isNotEmpty &&
                                File(snapshot.data!).existsSync()
                            ? Image.file(
                                File(snapshot.data!),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildPlaceholderAvatar(),
                              )
                            : _buildPlaceholderAvatar(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: AppTypography.lg,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: takenToday
                                        ? AppColors.success
                                        : AppColors.warning,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  takenToday
                                      ? 'Photo taken today'
                                      : 'Photo not taken',
                                  style: TextStyle(
                                    fontSize: AppTypography.sm,
                                    color: AppColors.textPrimary.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textPrimary.withValues(alpha: 0.3),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      color: AppColors.textPrimary.withValues(alpha: 0.1),
      child: Icon(
        Icons.person,
        size: 24,
        color: AppColors.textPrimary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildProjectItemSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
