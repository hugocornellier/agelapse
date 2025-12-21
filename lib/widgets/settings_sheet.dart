import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../screens/set_eye_position_page.dart';
import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/utils.dart';
import 'bool_setting_switch.dart';
import 'custom_dropdown_button.dart';
import 'dropdown_with_custom_textfield.dart';
import 'main_navigation.dart';
import 'setting_list_tile.dart';

class SettingsSheet extends StatefulWidget {
  final int projectId;
  final bool isDefaultProject;
  final bool onlyShowVideoSettings;
  final bool onlyShowNotificationSettings;
  final Future<void> Function() stabCallback;
  final Future<void> Function() cancelStabCallback;
  final void Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;

  const SettingsSheet({
    super.key,
    required this.projectId,
    required this.isDefaultProject,
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
  late Future<Map<String, bool>> _settingsFuture;
  late Future<void> _notificationInitialization;
  late Future<void> _videoSettingsFuture;
  late Future<void> _watermarkSettingsFuture;
  late Future<int> _gridCountFuture;
  late TimeOfDay _selectedTime;
  late bool notificationsEnabled;
  late String dailyNotificationTime;
  late String projectOrientation;
  late int? framerate;
  late bool enableWatermark;
  late String watermarkPosition;
  late String watermarkOpacity;
  late String resolution;
  late String aspectRatio;
  late int gridCount;
  late int _gridModeIndex;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _settingsFuture = _initializeData();
    _notificationInitialization = _settingsFuture.then((_) {
      //
    });

    _videoSettingsFuture = _initializeVideoSettings();
    _watermarkSettingsFuture = _initializeWatermarkSettings();
    _gridCountFuture = _initializeGridCount();
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
      ]);

      notificationsEnabled = results[2] as bool;
      dailyNotificationTime = results[3] as String;
      _gridModeIndex = results[4] as int;

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
    resolution =
        await SettingsUtil.loadVideoResolution(widget.projectId.toString());
    aspectRatio =
        await SettingsUtil.loadAspectRatio(widget.projectId.toString());
    framerate = await SettingsUtil.loadFramerate(widget.projectId.toString());

    String poSetting =
        await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    projectOrientation =
        poSetting[0].toUpperCase() + poSetting.substring(1).toLowerCase();

    setState(() {});
  }

  Future<void> _initializeWatermarkSettings() async {
    enableWatermark =
        await SettingsUtil.loadWatermarkSetting(widget.projectId.toString());
    watermarkPosition = await SettingsUtil.loadWatermarkPosition();
    watermarkOpacity = await SettingsUtil.loadWatermarkOpacity();
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
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Container(
        padding: const EdgeInsets.all(16.0),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Color(0xff121212),
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
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Projects',
                        _buildProjectSettings,
                      ),
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Camera Settings',
                        _buildCameraSettings,
                      ),
                    if (!widget.onlyShowVideoSettings)
                      _buildSettingsSection(
                        'Notifications',
                        _buildNotificationSettings,
                      ),
                    if (!widget.onlyShowVideoSettings &&
                        !widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Gallery Settings',
                        _buildGallerySettings,
                      ),
                    if (!widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Video Settings',
                        _buildVideoSettings,
                      ),
                    if (!widget.onlyShowNotificationSettings)
                      _buildSettingsSection(
                        'Watermark',
                        _buildWatermarkSettings,
                      ),
                    if (widget.onlyShowNotificationSettings)
                      const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: const Color(0xff121212),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Settings',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        _buildIconButton(),
                      ],
                    ),
                    const Divider(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton() {
    return IconButton(
      icon: Icon(
        widget.onlyShowNotificationSettings ? Icons.check : Icons.close,
        color: Colors.white,
      ),
      onPressed: () {
        Navigator.of(context).pop();

        if (widget.onlyShowNotificationSettings) {
          Utils.navigateToScreenReplaceNoAnim(
              context,
              MainNavigation(
                projectId: widget.projectId,
                projectName: "",
                showFlashingCircle: false,
              ));
        }
      },
    );
  }

  Widget _buildSettingsSection(String title, Widget Function() buildSettings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 0.0),
          child: Text(title, style: const TextStyle(color: Colors.grey)),
        ),
        FutureBuilder<void>(
          future: _getFutureForTitle(title),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else {
              return buildSettings();
            }
          },
        ),
      ],
    );
  }

  Future<void> _getFutureForTitle(String title) {
    switch (title) {
      case 'Projects':
        return _settingsFuture;
      case 'Camera Settings':
        return _settingsFuture;
      case 'Notifications':
        return _notificationInitialization;
      case 'Gallery Settings':
        return _gridCountFuture;
      case 'Video Settings':
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
          title: 'Set project as default',
          initialValue: widget.isDefaultProject,
          showInfo: true,
          infoContent:
              "If you set this project as your default, it will be selected automatically on launch.",
          onChanged: (bool value) {
            DB.instance.setSettingByTitle('default_project',
                value ? widget.projectId.toString() : 'none');
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return Column(
      children: [
        BoolSettingSwitch(
          title: 'Enable notifications',
          initialValue: notificationsEnabled,
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
              _flutterLocalNotificationsPlugin.cancelAll();
            }
          },
        ),
        SettingListTile(
          title: 'Daily notification time',
          contentWidget: InkWell(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Text(
                _selectedTime.format(context),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          infoContent: '',
          showInfo: false,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildGallerySettings() {
    return Column(
      children: [
        SettingListTile(
          title: 'Grid count',
          contentWidget: FutureBuilder<int>(
            future: _gridCountFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
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
              return const Center(child: Text('Unexpected error'));
            },
          ),
          infoContent: '',
          showInfo: false,
        ),
        const SizedBox(height: 20),
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
        _buildEyeScaleButton(),
        const SizedBox(height: 24),
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
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildError(String error) {
    return Center(child: Text('Error: $error'));
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
        return const Center(child: Text('Unexpected error'));
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
          title: 'Mirror Front Camera',
          initialValue: cameraMirror,
          onChanged: (bool value) async {
            setState(() {
              cameraMirror = value;
            });

            print("Setting camera_mirror to ${value.toString()}");

            await DB.instance.setSettingByTitle(
                'camera_mirror', value.toString(), widget.projectId.toString());
            widget.refreshSettings();
          },
        ),
        const SizedBox(height: 20),
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
      title: 'Grid mode',
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
      title: 'Save photos to camera roll',
      initialValue: saveToCameraRoll,
      onChanged: (bool value) {
        setState(() => saveToCameraRoll = value);
        _updateSetting('save_to_camera_roll', value);
      },
    );
  }

  Widget _buildProjectOrientationDropdown() {
    return SettingListTile(
      title: 'Orientation',
      contentWidget: CustomDropdownButton<String>(
        value: projectOrientation,
        items: const [
          DropdownMenuItem<String>(value: "Portrait", child: Text("Portrait")),
          DropdownMenuItem<String>(
              value: "Landscape", child: Text("Landscape")),
        ],
        onChanged: (String? value) async {
          if (value != null) {
            final bool shouldProceed = await Utils.showConfirmChangeDialog(
                context, "project orientation");
            if (shouldProceed) {
              await widget.cancelStabCallback();

              setState(() => projectOrientation = value);
              DB.instance.setSettingByTitle('project_orientation',
                  value.toLowerCase(), widget.projectId.toString());
              widget.refreshSettings();

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
        onChanged: (newValue) async {
          await DB.instance.setSettingByTitle(
              'framerate', newValue.toString(), widget.projectId.toString());
          widget.refreshSettings();
          widget.stabCallback();
        });
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
      contentWidget: CustomDropdownButton<String>(
        value: resolution,
        items: _getResolutionDropdownItems(),
        onChanged: (String? value) async {
          if (value != null) {
            bool shouldProceed =
                await Utils.showConfirmChangeDialog(context, "resolution");

            if (shouldProceed) {
              setState(() => resolution = value);

              await widget.cancelStabCallback();
              await DB.instance.setSettingByTitle(
                  'video_resolution', value, widget.projectId.toString());
              widget.refreshSettings();

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

  Widget _buildAspectRatioDropdown() {
    return SettingListTile(
      title: 'Aspect ratio',
      contentWidget: CustomDropdownButton<String>(
        value: aspectRatio,
        items: const [
          DropdownMenuItem<String>(value: "16:9", child: Text("16:9")),
          DropdownMenuItem<String>(value: "4:3", child: Text("4:3")),
        ],
        onChanged: (String? value) async {
          if (value != null) {
            bool shouldProceed =
                await Utils.showConfirmChangeDialog(context, "aspect ratio");

            if (shouldProceed) {
              setState(() => aspectRatio = value);
              await DB.instance.setSettingByTitle(
                  'aspect_ratio', value, widget.projectId.toString());

              await widget.cancelStabCallback();
              widget.refreshSettings();

              await resetStabStatusAndRestartStabilization();
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
      contentWidget: ElevatedButton(
        onPressed: () => Utils.navigateToScreen(
          context,
          SetEyePositionPage(
            projectId: widget.projectId,
            projectName: "",
            cancelStabCallback: widget.cancelStabCallback,
            refreshSettings: widget.refreshSettings,
          ),
        ),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(color: Colors.white),
          backgroundColor: AppColors.evenDarkerLightBlue,
        ),
        child: const Text(
          "Configure",
          style: TextStyle(color: Colors.white),
        ),
      ),
      infoContent: '',
      showInfo: false,
    );
  }

  Widget _buildWatermarkSwitch() {
    return BoolSettingSwitch(
      title: 'Enable watermark',
      initialValue: enableWatermark,
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
        contentWidget: ImagePickerWidget(
            disabled: !enableWatermark, projectId: widget.projectId),
        infoContent: '',
        showInfo: false,
        disabled: !enableWatermark);
  }

  Widget _buildWatermarkPositionDropdown() {
    return SettingListTile(
      title: 'Watermark position',
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
      title: 'Watermark opacity',
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
    return ElevatedButton(
      onPressed: widget.disabled || uploading ? null : _pickImage,
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all<Color>(Colors.transparent),
        shape: MaterialStateProperty.all<OutlinedBorder>(
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (watermarkFilePath.isNotEmpty && watermarkExists) ...[
            Image.file(
              File(watermarkFilePath),
              fit: BoxFit.cover,
              width: 20,
            ),
          ] else ...[
            const Icon(Icons.upload)
          ],
          uploading
              ? const CircularProgressIndicator()
              : Text(watermarkFilePath.isNotEmpty ? '' : 'Select'),
        ],
      ),
    );
  }
}
