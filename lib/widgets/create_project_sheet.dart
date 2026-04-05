import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/notification_util.dart';
import '../utils/platform_utils.dart';
import '../utils/test_mode.dart' as test_config;
import '../utils/window_utils.dart';
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
  String _selectedType = 'face';

  static const _projectTypes = [
    ('face', 'Face'),
    ('cat', 'Cat'),
    ('dog', 'Dog'),
    ('musc', 'Muscle'),
    ('pregnancy', 'Pregnancy'),
  ];

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
                              icon: Icon(
                                Icons.close,
                                color: AppColors.textPrimary,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      _buildTypeLabel(),
                      _buildTypeDropdown(),
                      const SizedBox(height: 32),
                      _buildNameLabel(),
                      _buildTextField(),
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 70.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTypeLabel(),
                  _buildTypeDropdown(),
                  const SizedBox(height: 16),
                  _buildNameLabel(),
                  _buildTextField(),
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
                          onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildTypeLabel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text('Type', style: TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _buildNameLabel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.0),
      child: Text('Name', style: TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _buildTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedType,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          dropdownColor: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          items: _projectTypes
              .map(
                (t) => DropdownMenuItem<String>(value: t.$1, child: Text(t.$2)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _selectedType = value);
          },
          style: TextStyle(
            fontSize: AppTypography.md,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: TextField(
        controller: _nameController,
        onSubmitted: (_) {
          if (isDesktop) {
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

    final int projectId = await DB.instance.addProject(
      projectName,
      _selectedType,
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
    if (widget.isFullPage && !test_config.isTestMode) {
      await WindowUtils.transitionToDefaultWindowState();
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MainNavigation(
          projectId: projectId,
          projectName: projectName,
          showFlashingCircle: false,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
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
}
