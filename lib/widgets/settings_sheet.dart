import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../screens/set_eye_position_page.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/project_utils.dart';
import '../utils/utils.dart';
import 'bool_setting_switch.dart';
import 'custom_dropdown_button.dart';
import '../screens/projects_page.dart';
import 'delete_project_dialog.dart';
import 'dropdown_with_custom_textfield.dart';
import 'main_navigation.dart';
import 'setting_list_tile.dart';

class SettingsSheet extends StatefulWidget {
  final int projectId;
  final bool onlyShowVideoSettings;
  final bool onlyShowNotificationSettings;
  final Future<void> Function() stabCallback;
  final Future<void> Function() cancelStabCallback;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;

  const SettingsSheet({
    super.key,
    required this.projectId,
    this.onlyShowVideoSettings = false,
    this.onlyShowNotificationSettings = false,
    required this.stabCallback,
    required this.cancelStabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
  });

  @override
  SettingsSheetState createState() => SettingsSheetState();
}

class SettingsSheetState extends State<SettingsSheet> {
  // Use Completers to allow deferred initialization while still having
  // valid futures for FutureBuilders from the first frame
  final _settingsCompleter = Completer<Map<String, bool>>();
  final _notificationCompleter = Completer<void>();
  final _videoSettingsCompleter = Completer<void>();
  final _watermarkSettingsCompleter = Completer<void>();
  final _gridCountCompleter = Completer<int>();
  final _projectSettingsCompleter = Completer<void>();

  Future<Map<String, bool>> get _settingsFuture => _settingsCompleter.future;
  Future<void> get _notificationInitialization => _notificationCompleter.future;
  Future<void> get _videoSettingsFuture => _videoSettingsCompleter.future;
  Future<void> get _watermarkSettingsFuture =>
      _watermarkSettingsCompleter.future;
  Future<int> get _gridCountFuture => _gridCountCompleter.future;
  Future<void> get _projectSettingsFuture => _projectSettingsCompleter.future;

  bool _isDefaultProject = false;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 17, minute: 0);
  bool notificationsEnabled = false;
  String dailyNotificationTime = "not set";
  String projectOrientation = "Portrait";
  int? framerate;
  bool enableWatermark = false;
  String watermarkPosition = "Lower left";
  String watermarkOpacity = "0.7";
  String resolution = "1080p";
  String aspectRatio = "16:9";
  int gridCount = 4;
  int _gridModeIndex = 0;
  String _stabilizationMode = 'slow';

  // Lazy initialization to avoid blocking widget creation
  FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin;
  FlutterLocalNotificationsPlugin get _notificationPlugin {
    _flutterLocalNotificationsPlugin ??= FlutterLocalNotificationsPlugin();
    return _flutterLocalNotificationsPlugin!;
  }

  @override
  void initState() {
    super.initState();
    // Defer initialization until after the first frame to allow
    // the modal animation to start smoothly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  void _init() {
    // Start all initializations and complete their Completers
    _initializeData().then((result) {
      _settingsCompleter.complete(result);
      _notificationCompleter.complete();
    }).catchError((e) {
      _settingsCompleter.completeError(e);
      _notificationCompleter.completeError(e);
    });

    _initializeVideoSettings().then((_) {
      _videoSettingsCompleter.complete();
    }).catchError((e) {
      _videoSettingsCompleter.completeError(e);
    });

    _initializeWatermarkSettings().then((_) {
      _watermarkSettingsCompleter.complete();
    }).catchError((e) {
      _watermarkSettingsCompleter.completeError(e);
    });

    _initializeGridCount().then((result) {
      _gridCountCompleter.complete(result);
    }).catchError((e) {
      _gridCountCompleter.completeError(e);
    });

    _initializeProjectSettings().then((_) {
      _projectSettingsCompleter.complete();
    }).catchError((e) {
      _projectSettingsCompleter.completeError(e);
    });
  }

  Future<void> _initializeProjectSettings() async {
    final data = await DB.instance.getSettingByTitle('default_project');
    final defaultProject = data?['value'];

    if (defaultProject == null || defaultProject == "none") {
      _isDefaultProject = false;
    } else {
      _isDefaultProject = int.tryParse(defaultProject) == widget.projectId;
    }
    setState(() {});
  }

  Future<Map<String, bool>> _initializeData() async {
    try {
      final results = await Future.wait([
        SettingsUtil.loadEnableGrid(),
        SettingsUtil.loadSaveToCameraRoll(),
        SettingsUtil.loadNotificationSetting(),
        SettingsUtil.loadDailyNotificationTime(widget.projectId.toString()),
        SettingsUtil.loadGridModeIndex(widget.projectId.toString()),
        SettingsUtil.loadCameraMirror(widget.projectId.toString()),
        SettingsUtil.loadStabilizationMode(),
      ]);

      notificationsEnabled = results[2] as bool;
      dailyNotificationTime = results[3] as String;
      _gridModeIndex = results[4] as int;
      _stabilizationMode = results[6] as String;

      if (dailyNotificationTime == "not set") {
        _selectedTime = const TimeOfDay(hour: 17, minute: 0);
      } else {
        final int timestamp = int.parse(dailyNotificationTime);
        final DateTime dateTime =
            DateTime.fromMillisecondsSinceEpoch(timestamp);
        _selectedTime = TimeOfDay.fromDateTime(dateTime);
      }

      return {
        'enableGrid': results[0] as bool,
        'saveToCameraRoll': results[1] as bool,
        'cameraMirror': results[5] as bool,
      };
    } catch (e) {
      throw Exception('Failed to load settings: $e');
    }
  }

  Future<void> _initializeVideoSettings() async {
    final projectIdStr = widget.projectId.toString();
    final results = await Future.wait([
      SettingsUtil.loadVideoResolution(projectIdStr),
      SettingsUtil.loadAspectRatio(projectIdStr),
      SettingsUtil.loadFramerate(projectIdStr),
      SettingsUtil.loadProjectOrientation(projectIdStr),
    ]);

    resolution = results[0] as String;
    aspectRatio = results[1] as String;
    framerate = results[2] as int;
    final poSetting = results[3] as String;
    projectOrientation =
        poSetting[0].toUpperCase() + poSetting.substring(1).toLowerCase();

    setState(() {});
  }

  Future<void> _initializeWatermarkSettings() async {
    final results = await Future.wait([
      SettingsUtil.loadWatermarkSetting(widget.projectId.toString()),
      SettingsUtil.loadWatermarkPosition(),
      SettingsUtil.loadWatermarkOpacity(),
    ]);

    enableWatermark = results[0] as bool;
    watermarkPosition = results[1] as String;
    watermarkOpacity = results[2] as String;
    setState(() {});
  }

  Future<int> _initializeGridCount() async {
    gridCount =
        await SettingsUtil.loadGridAxisCount(widget.projectId.toString());
    setState(() {});
    return gridCount;
  }

  void _updateSetting(String title, bool value) {
    DB.instance.setSettingByTitle(title, value.toString().toLowerCase());
    widget.refreshSettings();
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.settingsAccent,
              surface: AppColors.settingsCardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() => _selectedTime = picked);

      final now = DateTime.now();
      final selectedDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      final selectedDateTimestamp = selectedDateTime.millisecondsSinceEpoch;
      dailyNotificationTime = selectedDateTimestamp.toString();

      await DB.instance.setSettingByTitle('daily_notification_time',
          dailyNotificationTime, widget.projectId.toString());
      widget.refreshSettings();

      await _scheduleDailyNotification();
    }
  }

  Future<void> _scheduleDailyNotification() async {
    NotificationUtil.scheduleDailyNotification(
        widget.projectId, dailyNotificationTime);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.settingsBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Projects',
                        Icons.folder_outlined,
                        _buildProjectSettings,
                      ),
                    if (!widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Stabilization',
                        Icons.center_focus_strong_outlined,
                        _buildStabilizationSettings,
                      ),
                    if (!widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Video',
                        Icons.movie_outlined,
                        _buildVideoSettings,
                      ),
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Camera',
                        Icons.camera_alt_outlined,
                        _buildCameraSettings,
                      ),
                    if (!widget.onlyShowVideoSettings)
                      _buildSettingsSection(
                        'Notifications',
                        Icons.notifications_outlined,
                        _buildNotificationSettings,
                      ),
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Gallery',
                        Icons.grid_view_outlined,
                        _buildGallerySettings,
                      ),
                    if (!widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Watermark',
                        Icons.branding_watermark_outlined,
                        _buildWatermarkSettings,
                      ),
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildDangerZoneSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.settingsDivider,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.settingsTextTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.settingsTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              _buildCloseButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        if (widget.onlyShowNotificationSettings) {
          Utils.navigateToScreenReplaceNoAnim(
            context,
            MainNavigation(
              projectId: widget.projectId,
              projectName: "",
              showFlashingCircle: false,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          widget.onlyShowNotificationSettings ? Icons.check : Icons.close,
          color: Colors.white70,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSettingsSection(
    String title,
    IconData icon,
    Widget Function() buildSettings,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: AppColors.settingsTextSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.settingsTextSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.settingsCardBorder,
                width: 1,
              ),
            ),
            child: FutureBuilder<void>(
              future: _getFutureForTitle(title),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.settingsAccent,
                        ),
                      ),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error loading settings',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 14,
                      ),
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: buildSettings(),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  static const Color _dangerRed = Color(0xffFF453A);

  Widget _buildDangerZoneSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: _dangerRed.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _dangerRed.withValues(alpha: 0.8),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _dangerRed.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delete this project',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.settingsTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Once deleted, there is no going back. This will permanently delete all photos and videos associated with this project.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.settingsTextSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _showDeleteProjectDialog,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _dangerRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _dangerRed.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Delete this project',
                          style: TextStyle(
                            color: _dangerRed,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteProjectDialog() async {
    // Get project name from DB
    final projectName = await DB.instance.getProjectNameById(widget.projectId);
    if (projectName == null || !mounted) return;

    // Show type-to-confirm dialog
    final confirmed = await showDeleteProjectDialog(
      context: context,
      projectName: projectName,
    );

    if (confirmed == true && mounted) {
      // Perform deletion
      await ProjectUtils.deleteProject(widget.projectId);

      // Navigate to ProjectsPage and clear the entire navigation stack
      // This prevents the broken MainNavigation from persisting
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ProjectsPage()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _getFutureForTitle(String title) {
    switch (title) {
      case 'Projects':
        return _projectSettingsFuture;
      case 'Stabilization':
        return _settingsFuture;
      case 'Camera':
        return _settingsFuture;
      case 'Notifications':
        return _notificationInitialization;
      case 'Gallery':
        return _gridCountFuture;
      case 'Video':
        return _videoSettingsFuture;
      case 'Watermark':
        return _watermarkSettingsFuture;
      default:
        return Future.value();
    }
  }

  Widget _buildProjectSettings() {
    return Column(
      children: [
        BoolSettingSwitch(
          title: 'Set as default project',
          initialValue: _isDefaultProject,
          showInfo: true,
          infoContent:
              "If you set this project as your default, it will be selected automatically on launch.",
          onChanged: (bool value) {
            DB.instance.setSettingByTitle('default_project',
                value ? widget.projectId.toString() : 'none');
          },
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return Column(
      children: [
        BoolSettingSwitch(
          title: 'Enable notifications',
          initialValue: notificationsEnabled,
          showDivider: true,
          onChanged: (value) async {
            setState(() {
              notificationsEnabled = value;
            });
            await DB.instance
                .setSettingByTitle('enable_notifications', value.toString());
            widget.refreshSettings();
            if (value) {
              _scheduleDailyNotification();
            } else {
              _notificationPlugin.cancelAll();
            }
          },
        ),
        SettingListTile(
          title: 'Daily reminder time',
          contentWidget: GestureDetector(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.settingsCardBorder,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedTime.format(context),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.settingsTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: AppColors.settingsTextSecondary,
                  ),
                ],
              ),
            ),
          ),
          infoContent: '',
          showInfo: false,
        ),
      ],
    );
  }

  Widget _buildGallerySettings() {
    return Column(
      children: [
        SettingListTile(
          title: 'Grid columns',
          contentWidget: FutureBuilder<int>(
            future: _gridCountFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              } else if (snapshot.hasError) {
                return const Text('Error');
              } else if (snapshot.hasData) {
                return StatefulBuilder(
                  builder: (context, setState) {
                    final bool isDesktop = Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux;
                    final int maxSteps = isDesktop ? 12 : 5;

                    return CustomDropdownButton<int>(
                      value: gridCount.clamp(1, maxSteps),
                      items: List.generate(maxSteps, (index) {
                        return DropdownMenuItem<int>(
                          value: index + 1,
                          child: Text('${index + 1}'),
                        );
                      }),
                      onChanged: (int? value) async {
                        if (value != null) {
                          setState(() {
                            gridCount = value;
                          });
                          await DB.instance.setSettingByTitle(
                            'gridAxisCount',
                            value.toString(),
                            widget.projectId.toString(),
                          );
                          widget.refreshSettings();
                        }
                      },
                    );
                  },
                );
              }
              return const Text('Error');
            },
          ),
          infoContent: '',
          showInfo: false,
        ),
      ],
    );
  }

  Widget _buildStabilizationSettings() {
    return Column(
      children: [
        _buildStabilizationModeDropdown(),
        _buildEyeScaleButton(),
      ],
    );
  }

  Widget _buildVideoSettings() {
    return Column(
      children: [
        _buildFramerateDropdown(framerate ?? 30),
        _buildProjectOrientationDropdown(),
        _buildResolutionDropdown(),
        _buildAspectRatioDropdown(),
      ],
    );
  }

  Widget _buildWatermarkSettings() {
    return Column(
      children: [
        _buildWatermarkSwitch(),
        _buildWatermarkImageInput(),
        _buildWatermarkPositionDropdown(),
        _buildWatermarkOpacityDropdown(),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.settingsAccent,
        ),
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Text(
        'Error loading settings',
        style: TextStyle(color: Colors.red.shade300),
      ),
    );
  }

  Widget _buildCameraSettings() {
    return FutureBuilder<Map<String, bool>>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        } else if (snapshot.hasError) {
          return _buildError(snapshot.error.toString());
        } else if (snapshot.hasData) {
          return _buildCameraSettingsContent(snapshot.data!);
        }
        return const Text('Unexpected error');
      },
    );
  }

  Widget _buildCameraSettingsContent(Map<String, bool> settings) {
    bool saveToCameraRoll = settings['saveToCameraRoll']!;
    bool cameraMirror = settings['cameraMirror']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGridModeDropdown(),
        _buildSaveToCameraRollSwitch(saveToCameraRoll),
        BoolSettingSwitch(
          title: 'Mirror front camera',
          initialValue: cameraMirror,
          onChanged: (bool value) async {
            setState(() {
              cameraMirror = value;
            });

            LogService.instance
                .log("Setting camera_mirror to ${value.toString()}");

            await DB.instance.setSettingByTitle(
                'camera_mirror', value.toString(), widget.projectId.toString());
            widget.refreshSettings();
          },
        ),
      ],
    );
  }

  Widget _buildGridModeDropdown() {
    final Map<int, String> gridModeMap = {
      0: "None",
      1: "Ghost",
      2: "Grid",
      3: "Ghost + Grid"
    };

    return SettingListTile(
      title: 'Overlay mode',
      showDivider: true,
      contentWidget: CustomDropdownButton<int>(
        value: _gridModeIndex,
        items: gridModeMap.entries.map((entry) {
          return DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
        onChanged: (int? newValue) async {
          if (newValue != null) {
            setState(() {
              _gridModeIndex = newValue;
            });
            await DB.instance.setSettingByTitle(
              'grid_mode_index',
              newValue.toString(),
              widget.projectId.toString(),
            );
            widget.refreshSettings();
          }
        },
      ),
      infoContent: '',
      showInfo: false,
    );
  }

  Widget _buildSaveToCameraRollSwitch(bool saveToCameraRoll) {
    return BoolSettingSwitch(
      title: 'Save to camera roll',
      initialValue: saveToCameraRoll,
      showDivider: true,
      onChanged: (bool value) {
        setState(() => saveToCameraRoll = value);
        _updateSetting('save_to_camera_roll', value);
      },
    );
  }

  Widget _buildProjectOrientationDropdown() {
    return SettingListTile(
      title: 'Orientation',
      showDivider: true,
      contentWidget: CustomDropdownButton<String>(
        value: projectOrientation,
        items: const [
          DropdownMenuItem<String>(value: "Portrait", child: Text("Portrait")),
          DropdownMenuItem<String>(
              value: "Landscape", child: Text("Landscape")),
        ],
        onChanged: (String? value) async {
          if (value != null && value != projectOrientation) {
            final bool shouldProceed = await Utils.showConfirmChangeDialog(
                context, "project orientation");
            if (shouldProceed) {
              await widget.cancelStabCallback();

              setState(() => projectOrientation = value);
              await DB.instance.setSettingByTitle('project_orientation',
                  value.toLowerCase(), widget.projectId.toString());
              await widget.refreshSettings();

              await resetStabStatusAndRestartStabilization();
            }
          }
        },
      ),
      infoContent: '',
      showInfo: false,
    );
  }

  Widget _buildFramerateDropdown(int framerate) {
    return DropdownWithCustomTextField(
      projectId: widget.projectId,
      title: 'Framerate (FPS)',
      initialValue: framerate,
      showDivider: true,
      onChanged: (newValue) async {
        await DB.instance.setSettingByTitle(
            'framerate', newValue.toString(), widget.projectId.toString());
        widget.refreshSettings();
        widget.stabCallback();
      },
    );
  }

  Future<void> resetStabStatusAndRestartStabilization() async {
    await DB.instance.resetStabilizationStatusForProject(
        widget.projectId, projectOrientation);

    // Clear cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    widget.clearRawAndStabPhotos();
    widget.stabCallback();
  }

  Widget _buildResolutionDropdown() {
    return SettingListTile(
      title: 'Resolution',
      showDivider: true,
      contentWidget: CustomDropdownButton<String>(
        value: resolution,
        items: _getResolutionDropdownItems(),
        onChanged: (String? value) async {
          if (value != null && value != resolution) {
            bool shouldProceed =
                await Utils.showConfirmChangeDialog(context, "resolution");

            if (shouldProceed) {
              setState(() => resolution = value);

              await widget.cancelStabCallback();
              await DB.instance.setSettingByTitle(
                  'video_resolution', value, widget.projectId.toString());
              await widget.refreshSettings();

              await resetStabStatusAndRestartStabilization();
            }
          }
        },
      ),
      infoContent: '',
      showInfo: false,
    );
  }

  List<DropdownMenuItem<String>> _getResolutionDropdownItems() {
    return const [
      DropdownMenuItem<String>(value: "1080p", child: Text("1080p")),
      DropdownMenuItem<String>(value: "2K", child: Text("2K")),
      DropdownMenuItem<String>(value: "3K", child: Text("3K")),
      DropdownMenuItem<String>(value: "4K", child: Text("4K")),
    ];
  }

  Widget _buildStabilizationModeDropdown() {
    return SettingListTile(
      title: 'Stabilization mode',
      showDivider: true,
      contentWidget: CustomDropdownButton<String>(
        value: _stabilizationMode,
        items: const [
          DropdownMenuItem<String>(value: "fast", child: Text("Fast")),
          DropdownMenuItem<String>(value: "slow", child: Text("Slow")),
        ],
        onChanged: (String? value) async {
          if (value != null && value != _stabilizationMode) {
            bool shouldProceed = await Utils.showConfirmChangeDialog(
                context, "stabilization mode");

            if (shouldProceed) {
              setState(() => _stabilizationMode = value);

              await widget.cancelStabCallback();
              await SettingsUtil.saveStabilizationMode(value);
              await widget.refreshSettings();

              await resetStabStatusAndRestartStabilization();
            }
          }
        },
      ),
      infoContent: 'Fast: Quicker, but less accurate.\n'
          'Slow: More accurate, but takes longer.',
      showInfo: true,
    );
  }

  Widget _buildAspectRatioDropdown() {
    return SettingListTile(
      title: 'Aspect ratio',
      showDivider: true,
      contentWidget: CustomDropdownButton<String>(
        value: aspectRatio,
        items: const [
          DropdownMenuItem<String>(value: "16:9", child: Text("16:9")),
          DropdownMenuItem<String>(value: "4:3", child: Text("4:3")),
        ],
        onChanged: (String? value) async {
          if (value != null && value != aspectRatio) {
            bool shouldProceed =
                await Utils.showConfirmChangeDialog(context, "aspect ratio");

            if (shouldProceed) {
              LogService.instance
                  .log('[SettingsSheet] Aspect ratio changing to: $value');
              setState(() => aspectRatio = value);
              await DB.instance.setSettingByTitle(
                  'aspect_ratio', value, widget.projectId.toString());
              LogService.instance
                  .log('[SettingsSheet] DB updated, cancelling stab...');

              await widget.cancelStabCallback();
              LogService.instance.log(
                  '[SettingsSheet] Stab cancelled, refreshing settings...');
              await widget.refreshSettings();
              LogService.instance.log(
                  '[SettingsSheet] Settings refreshed, restarting stabilization...');

              await resetStabStatusAndRestartStabilization();
              LogService.instance
                  .log('[SettingsSheet] Stabilization restarted');
            }
          }
        },
      ),
      infoContent: '',
      showInfo: false,
    );
  }

  Widget _buildEyeScaleButton() {
    return SettingListTile(
      title: 'Eye position',
      contentWidget: GestureDetector(
        onTap: () => Utils.navigateToScreen(
          context,
          SetEyePositionPage(
            projectId: widget.projectId,
            projectName: "",
            cancelStabCallback: widget.cancelStabCallback,
            refreshSettings: widget.refreshSettings,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.settingsAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.settingsAccent.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: const Text(
            'Configure',
            style: TextStyle(
              color: AppColors.settingsAccent,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      infoContent:
          'Controls where eyes are positioned in the output frame. Photos are transformed so that detected eyes align to this position, and the video output is consistent across frames.',
      showInfo: true,
    );
  }

  Widget _buildWatermarkSwitch() {
    return BoolSettingSwitch(
      title: 'Enable watermark',
      initialValue: enableWatermark,
      showDivider: true,
      onChanged: (bool value) async {
        setState(() => enableWatermark = value);
        await DB.instance.setSettingByTitle(
            'enable_watermark', value.toString(), widget.projectId.toString());

        widget.refreshSettings();
      },
    );
  }

  Widget _buildWatermarkImageInput() {
    return SettingListTile(
      title: 'Watermark image',
      showDivider: true,
      contentWidget: ImagePickerWidget(
          disabled: !enableWatermark, projectId: widget.projectId),
      infoContent: '',
      showInfo: false,
      disabled: !enableWatermark,
    );
  }

  Widget _buildWatermarkPositionDropdown() {
    return SettingListTile(
      title: 'Position',
      showDivider: true,
      contentWidget: CustomDropdownButton<String>(
        value: watermarkPosition,
        items: const [
          DropdownMenuItem<String>(
              value: "Upper left", child: Text("Upper left")),
          DropdownMenuItem<String>(
              value: "Upper right", child: Text("Upper right")),
          DropdownMenuItem<String>(
              value: "Lower left", child: Text("Lower left")),
          DropdownMenuItem<String>(
              value: "Lower right", child: Text("Lower right")),
        ],
        onChanged: enableWatermark
            ? (String? value) async {
                if (value != null) {
                  setState(() => watermarkPosition = value);
                  await DB.instance
                      .setSettingByTitle('watermark_position', value);

                  widget.refreshSettings();
                }
              }
            : null,
      ),
      infoContent: '',
      showInfo: false,
      disabled: !enableWatermark,
    );
  }

  Widget _buildWatermarkOpacityDropdown() {
    return SettingListTile(
      title: 'Opacity',
      contentWidget: CustomDropdownButton<String>(
        value: watermarkOpacity,
        items: List.generate(9, (index) {
          final opacityValue = (index + 1) * 0.1;
          return DropdownMenuItem<String>(
            value: opacityValue.toStringAsFixed(1),
            child: Text('${(opacityValue * 100).toInt()}%'),
          );
        }),
        onChanged: (String? value) async {
          if (value != null) {
            setState(() => watermarkOpacity = value);
            await DB.instance.setSettingByTitle('watermark_opacity', value);

            widget.refreshSettings();
          }
        },
      ),
      infoContent: '',
      showInfo: false,
      disabled: !enableWatermark,
    );
  }
}

class ImagePickerWidget extends StatefulWidget {
  final bool disabled;
  final int projectId;

  const ImagePickerWidget(
      {super.key, required this.disabled, required this.projectId});

  @override
  ImagePickerWidgetState createState() => ImagePickerWidgetState();
}

class ImagePickerWidgetState extends State<ImagePickerWidget> {
  String watermarkFilePath = "";
  bool watermarkExists = false;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    watermarkFilePath = await DirUtils.getWatermarkFilePath(widget.projectId);
    if (await assetExists(watermarkFilePath)) {
      setState(() => watermarkExists = true);
    }
    setState(() {});
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    setState(() => uploading = true);

    if (result != null && result.files.isNotEmpty) {
      String imagePath = result.files.single.path!;
      File file = File(imagePath);
      Uint8List bytes = await file.readAsBytes();

      // Decode and re-encode as PNG using opencv
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (!mat.isEmpty) {
        try {
          final (success, pngBytes) = cv.imencode('.png', mat);
          mat.dispose();
          if (success) {
            await DirUtils.createDirectoryIfNotExists(watermarkFilePath);
            await StabUtils.writePngBytesToFileInIsolate(
                watermarkFilePath, pngBytes);
          }
          setState(() => uploading = false);
        } catch (e) {
          mat.dispose();
          setState(() => uploading = false);
        }
      } else {
        mat.dispose();
        setState(() => uploading = false);
      }
    }
  }

  Future<bool> assetExists(String path) async {
    try {
      await rootBundle.loadString(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.disabled || uploading ? null : _pickImage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.disabled
              ? AppColors.settingsCardBorder.withValues(alpha: 0.5)
              : AppColors.settingsCardBorder,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (uploading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.settingsAccent,
                ),
              )
            else if (watermarkFilePath.isNotEmpty && watermarkExists)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(watermarkFilePath),
                  fit: BoxFit.cover,
                  width: 20,
                  height: 20,
                ),
              )
            else
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 18,
                color: widget.disabled
                    ? AppColors.settingsTextTertiary
                    : AppColors.settingsTextSecondary,
              ),
            if (!uploading) ...[
              const SizedBox(width: 6),
              Text(
                watermarkExists ? 'Change' : 'Select',
                style: TextStyle(
                  fontSize: 14,
                  color: widget.disabled
                      ? AppColors.settingsTextTertiary
                      : AppColors.settingsTextPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
