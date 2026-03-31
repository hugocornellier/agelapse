import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../screens/project_page.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/linked_source_utils.dart';
import '../utils/notification_util.dart';
import '../utils/test_mode.dart' as test_config;
import '../utils/window_utils.dart';
import '../utils/dir_utils.dart';
import 'main_navigation.dart';

class CreateProjectSheet extends StatefulWidget {
  final bool isDefaultProject;
  final bool showCloseButton;
  final bool isFullPage;

  const CreateProjectSheet({
    super.key,
    required this.isDefaultProject,
    this.showCloseButton = true,
    this.isFullPage = false,
  });

  @override
  CreateProjectSheetState createState() => CreateProjectSheetState();
}

class CreateProjectSheetState extends State<CreateProjectSheet> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedImage = 'assets/images/face.png';
  bool _useLinkedSourceFolder = false;
  String _linkedSourceFolderPath = '';

  static Future<String?> checkForStabilizedImage(String dirPath) async {
    final directory = Directory(dirPath);
    if (await directory.exists()) {
      try {
        final pngFiles = await directory
            .list()
            .where((item) => item.path.endsWith('.png') && item is File)
            .toList();
        if (pngFiles.isNotEmpty) {
          return pngFiles.first.path;
        }
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFullPage) {
      return _buildFullPageLayout();
    }
    return _buildSheetLayout();
  }

  Widget _buildFullPageLayout() {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Create New Project',
                            style: TextStyle(
                              fontSize: AppTypography.xxxl,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (widget.showCloseButton)
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: AppColors.textPrimary),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'Pose',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      _buildImageSelector(),
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0.0),
                        child: Text(
                          'Name',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      _buildTextField(),
                      const SizedBox(height: 16),
                      _buildLinkedSourceSection(),
                      const Spacer(),
                      _buildActionButton(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSheetLayout() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      height: 500,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 70.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'Pose',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  _buildImageSelector(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 0.0),
                    child: Text(
                      'Name',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  _buildTextField(),
                  _buildLinkedSourceSection(),
                  _buildActionButton(),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: AppColors.background,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Create New Project',
                          style: TextStyle(
                            fontSize: AppTypography.xxxl,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.showCloseButton)
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.textPrimary),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectTypeButton(String assetPath) {
    return Flexible(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedImage = assetPath;
            });
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                color: _selectedImage == assetPath ? AppColors.info : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildProjectTypeButton('assets/images/face.png'),
        _buildProjectTypeButton('assets/images/cat.png'),
        _buildProjectTypeButton('assets/images/dog.png'),
        _buildProjectTypeButton('assets/images/musc.png'),
        _buildProjectTypeButton('assets/images/preg.png'),
      ],
    );
  }

  Widget _buildTextField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: FractionallySizedBox(
        widthFactor: 1.0,
        child: TextField(
          controller: _nameController,
          onSubmitted: (_) {
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              _createProject();
            }
          },
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceElevated,
            hintText: 'Enter project name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.0),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 14.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedSourceSection() {
    final supportsLinkedSource = LinkedSourceUtils.supportsDesktopLinkedFolders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Use linked source folder',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Switch.adaptive(
              value: _useLinkedSourceFolder,
              onChanged: supportsLinkedSource
                  ? (value) async {
                      if (!value) {
                        setState(() {
                          _useLinkedSourceFolder = false;
                          _linkedSourceFolderPath = '';
                        });
                        return;
                      }

                      final selectedPath =
                          await FilePicker.platform.getDirectoryPath();
                      if (selectedPath == null || selectedPath.trim().isEmpty) {
                        setState(() => _useLinkedSourceFolder = false);
                        return;
                      }

                      setState(() {
                        _useLinkedSourceFolder = true;
                        _linkedSourceFolderPath = selectedPath;
                      });
                    }
                  : null,
            ),
          ],
        ),
        if (_useLinkedSourceFolder) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _linkedSourceFolderPath.isEmpty
                  ? 'No folder selected'
                  : _linkedSourceFolderPath,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppTypography.sm,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final selectedPath =
                    await FilePicker.platform.getDirectoryPath();
                if (selectedPath == null || selectedPath.trim().isEmpty) return;
                setState(() => _linkedSourceFolderPath = selectedPath);
              },
              child: const Text('Choose Folder'),
            ),
          ),
        ] else if (!supportsLinkedSource) ...[
          const SizedBox(height: 8),
          Text(
            'Linked source folders are currently available on desktop only.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypography.sm,
            ),
          ),
        ],
      ],
    );
  }

  void _createProject() async {
    final projectName = _nameController.text.trim();
    if (projectName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project name cannot be blank')),
      );
      return;
    }

    String projectType = 'face';
    switch (_selectedImage) {
      case 'assets/images/face.png':
        projectType = 'face';
        break;
      case 'assets/images/cat.png':
        projectType = 'cat';
        break;
      case 'assets/images/dog.png':
        projectType = 'dog';
        break;
      case 'assets/images/musc.png':
        projectType = 'musc';
        break;
      case 'assets/images/preg.png':
        projectType = 'pregnancy';
        break;
    }

    final int projectId = await DB.instance.addProject(
      projectName,
      projectType,
      DateTime.now().millisecondsSinceEpoch,
    );

    try {
      final String defaultProject = await DB.instance.getSettingValueByTitle(
        'default_project',
      );
      if (defaultProject == "none") {
        await DB.instance.setSettingByTitle(
          'default_project',
          projectId.toString(),
        );
      }
    } catch (e) {
      LogService.instance.log("Error while setting new default project: $e");
    }

    // Skip notification setup in test mode to avoid permission prompts
    if (!test_config.isTestMode) {
      try {
        DateTime fivePMLocalTime = NotificationUtil.getFivePMLocalTime();
        final dailyNotificationTime =
            fivePMLocalTime.millisecondsSinceEpoch.toString();

        await DB.instance.setSettingByTitle(
          'daily_notification_time',
          dailyNotificationTime,
          projectId.toString(),
        );
        await NotificationUtil.initializeNotifications();
        await NotificationUtil.scheduleDailyNotification(
          projectId,
          dailyNotificationTime,
        );
      } catch (e) {
        LogService.instance.log("Error while setting up notifications: $e");
      }
    }

    // Transition window to default state after completing welcome flow
    if (widget.isFullPage) {
      await WindowUtils.transitionToDefaultWindowState();
    }

    if (_useLinkedSourceFolder && _linkedSourceFolderPath.trim().isNotEmpty) {
      final projectDirPath = await DirUtils.getProjectDirPath(projectId);
      final validationError = LinkedSourceUtils.validateLinkedFolderPath(
        projectId: projectId,
        selectedPath: _linkedSourceFolderPath,
        projectDirPath: projectDirPath,
      );
      if (validationError == null) {
        await LinkedSourceUtils.persistDesktopFolderSelection(
          projectId,
          _linkedSourceFolderPath,
        );
      } else {
        LogService.instance.log(
          '[LinkedSource] Skipping invalid project-create selection: $validationError',
        );
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => MainNavigation(
          projectId: projectId,
          projectName: projectName,
          showFlashingCircle: false,
        ),
      ),
      (route) => false,
    );
  }

  Widget _buildActionButton() {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: _createProject,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentDark,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 18.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
          ),
        ),
        child: Text(
          "CREATE",
          style: TextStyle(
            fontSize: AppTypography.lg,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static Future<bool> photoWasTakenToday(int projectId) async {
    var photos = await DB.instance.getPhotosByProjectID(projectId);
    final DateTime today = DateTime.now();
    return photos.any((photo) {
      final timestampInt = int.parse(photo['timestamp']!);
      final photoDate = DateTime.fromMillisecondsSinceEpoch(timestampInt);
      return photoDate.isSameDate(today);
    });
  }
}
