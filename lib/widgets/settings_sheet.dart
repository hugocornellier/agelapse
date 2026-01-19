import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../screens/set_eye_position_page.dart';
import '../services/custom_font_manager.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/date_stamp_utils.dart';
import '../utils/project_utils.dart';
import '../utils/utils.dart';
import 'bool_setting_switch.dart';
import 'custom_dropdown_button.dart';
import '../screens/projects_page.dart';
import 'confirm_action_dialog.dart';
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
  final Future<void> Function() recompileVideoCallback;

  const SettingsSheet({
    super.key,
    required this.projectId,
    this.onlyShowVideoSettings = false,
    this.onlyShowNotificationSettings = false,
    required this.stabCallback,
    required this.cancelStabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.recompileVideoCallback,
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
  final _dateStampSettingsCompleter = Completer<void>();

  Future<Map<String, bool>> get _settingsFuture => _settingsCompleter.future;
  Future<void> get _notificationInitialization => _notificationCompleter.future;
  Future<void> get _videoSettingsFuture => _videoSettingsCompleter.future;
  Future<void> get _watermarkSettingsFuture =>
      _watermarkSettingsCompleter.future;
  Future<int> get _gridCountFuture => _gridCountCompleter.future;
  Future<void> get _projectSettingsFuture => _projectSettingsCompleter.future;
  Future<void> get _dateStampSettingsFuture =>
      _dateStampSettingsCompleter.future;

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
  bool _autoCompileVideo = true;
  bool _isCustomResolution = false;
  String? _customResolutionError;
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();
  bool _customResolutionModified = false;
  String _customResolutionBaseline =
      ''; // The initial WxH when entering custom mode
  int gridCount = 4;
  int _gridModeIndex = 0;
  String _stabilizationMode = 'slow';
  String _galleryGridMode = 'auto';

  // Date stamp settings
  bool _galleryDateLabelsEnabled = false;
  bool _galleryRawDateLabelsEnabled = false;
  String _galleryDateFormat = DateStampUtils.galleryFormatMMYY;
  String _galleryDateStampFont = DateStampUtils.defaultFont;
  bool _exportDateStampEnabled = false;
  String _exportDateStampPosition = DateStampUtils.positionLowerRight;
  String _exportDateStampFormat = DateStampUtils.exportFormatLong;
  int _exportDateStampSize = 3;
  double _exportDateStampOpacity = 1.0;
  String _exportDateStampFont = DateStampUtils.fontSameAsGallery;

  // Custom fonts state
  List<CustomFont> _customFonts = [];
  bool _isLoadingCustomFonts = false;

  // Custom format controllers and state
  final TextEditingController _galleryCustomFormatController =
      TextEditingController();
  final TextEditingController _exportCustomFormatController =
      TextEditingController();
  String? _galleryCustomFormatError;
  String? _exportCustomFormatError;
  bool _isGalleryCustomFormat = false;
  bool _isExportCustomFormat = false;

  // Lazy initialization to avoid blocking widget creation
  FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin;
  FlutterLocalNotificationsPlugin get _notificationPlugin {
    _flutterLocalNotificationsPlugin ??= FlutterLocalNotificationsPlugin();
    return _flutterLocalNotificationsPlugin!;
  }

  @override
  void initState() {
    super.initState();
    // Listen for changes to custom resolution fields
    _customWidthController.addListener(_onCustomResolutionFieldChanged);
    _customHeightController.addListener(_onCustomResolutionFieldChanged);
    // Defer initialization until after the first frame to allow
    // the modal animation to start smoothly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  void _onCustomResolutionFieldChanged() {
    if (!_isCustomResolution) return;
    final currentDims =
        '${_customWidthController.text}x${_customHeightController.text}';
    final hasChanges = currentDims != _customResolutionBaseline;
    if (hasChanges != _customResolutionModified) {
      setState(() => _customResolutionModified = hasChanges);
    }
  }

  @override
  void dispose() {
    _customWidthController.removeListener(_onCustomResolutionFieldChanged);
    _customHeightController.removeListener(_onCustomResolutionFieldChanged);
    _customWidthController.dispose();
    _customHeightController.dispose();
    _galleryCustomFormatController.dispose();
    _exportCustomFormatController.dispose();
    super.dispose();
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

    _initializeDateStampSettings().then((_) {
      _dateStampSettingsCompleter.complete();
    }).catchError((e) {
      _dateStampSettingsCompleter.completeError(e);
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
        final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
        );
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

  static const _presetResolutions = ['1080p', '4K', '8K'];

  Future<void> _initializeVideoSettings() async {
    final projectIdStr = widget.projectId.toString();
    final results = await Future.wait([
      SettingsUtil.loadVideoResolution(projectIdStr),
      SettingsUtil.loadAspectRatio(projectIdStr),
      SettingsUtil.loadFramerate(projectIdStr),
      SettingsUtil.loadProjectOrientation(projectIdStr),
      SettingsUtil.loadAutoCompileVideo(projectIdStr),
    ]);

    resolution = results[0] as String;
    aspectRatio = results[1] as String;
    framerate = results[2] as int;
    final poSetting = results[3] as String;
    projectOrientation =
        poSetting[0].toUpperCase() + poSetting.substring(1).toLowerCase();
    _autoCompileVideo = results[4] as bool;

    // Detect if resolution is custom (not a preset)
    _isCustomResolution = !_presetResolutions.contains(resolution);
    if (_isCustomResolution) {
      String w = '', h = '';
      // Try to parse WIDTHxHEIGHT format first
      final dimensions = StabUtils.getDimensions(resolution);
      if (dimensions != null) {
        w = dimensions.$1.toString();
        h = dimensions.$2.toString();
      } else {
        // Legacy format (short side only like "1728" or "2K"/"3K")
        // Calculate dimensions using stored aspect ratio
        final shortSide = StabUtils.getShortSide(resolution);
        final aspectDecimal = StabUtils.getAspectRatioAsDecimal(aspectRatio);
        if (shortSide != null && aspectDecimal != null) {
          final longSide = (shortSide * aspectDecimal).toInt();
          final width =
              projectOrientation == "Landscape" ? longSide : shortSide.toInt();
          final height =
              projectOrientation == "Landscape" ? shortSide.toInt() : longSide;
          w = width.toString();
          h = height.toString();
        }
      }
      _customWidthController.text = w;
      _customHeightController.text = h;
      _customResolutionBaseline = '${w}x$h';
      _customResolutionModified = false;
    }

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
    final projectIdStr = widget.projectId.toString();
    final results = await Future.wait([
      SettingsUtil.loadGridAxisCount(projectIdStr),
      SettingsUtil.loadGalleryGridMode(projectIdStr),
    ]);
    gridCount = results[0] as int;
    _galleryGridMode = results[1] as String;
    setState(() {});
    return gridCount;
  }

  Future<void> _initializeDateStampSettings() async {
    final settings = await SettingsUtil.loadAllDateStampSettings(
      widget.projectId.toString(),
    );

    _galleryDateLabelsEnabled = settings.galleryLabelsEnabled;
    _galleryRawDateLabelsEnabled = settings.galleryRawLabelsEnabled;
    _galleryDateFormat = settings.galleryFormat;
    _galleryDateStampFont = settings.galleryFont;
    _exportDateStampEnabled = settings.exportEnabled;
    _exportDateStampPosition = settings.exportPosition;
    _exportDateStampFormat = settings.exportFormat;
    _exportDateStampSize = settings.exportSizePercent;
    _exportDateStampOpacity = settings.exportOpacity;
    _exportDateStampFont = settings.exportFont;

    // Check if gallery format is custom (not a preset)
    _isGalleryCustomFormat =
        !DateStampUtils.isGalleryPreset(_galleryDateFormat);
    if (_isGalleryCustomFormat) {
      _galleryCustomFormatController.text = _galleryDateFormat;
    }

    // Check if export format is custom (not a preset)
    _isExportCustomFormat =
        !DateStampUtils.isExportPreset(_exportDateStampFormat);
    if (_isExportCustomFormat) {
      _exportCustomFormatController.text = _exportDateStampFormat;
    }

    // Load custom fonts
    await _loadCustomFonts();

    setState(() {});
  }

  /// Load all installed custom fonts.
  Future<void> _loadCustomFonts() async {
    _customFonts = await CustomFontManager.instance.getAllCustomFonts();
  }

  /// Import a custom font from file picker.
  /// Returns the family name of the installed font, or null if cancelled.
  Future<String?> _importCustomFont() async {
    setState(() => _isLoadingCustomFonts = true);

    try {
      // Open file picker for TTF/OTF files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        dialogTitle: 'Select a font file (TTF or OTF)',
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      // Validate the font file
      final validation =
          await CustomFontManager.instance.validateFontFile(filePath);
      if (!validation.isValid) {
        setState(() => _isLoadingCustomFonts = false);
        if (mounted) {
          _showFontErrorDialog(validation.errorMessage ?? 'Invalid font file');
        }
        return null;
      }

      // Show dialog to confirm font name
      final displayName =
          await _showFontNameDialog(validation.suggestedName ?? 'Custom Font');
      if (displayName == null) {
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      // Install the font
      final font =
          await CustomFontManager.instance.installFont(filePath, displayName);

      // Refresh custom fonts list
      await _loadCustomFonts();
      setState(() => _isLoadingCustomFonts = false);

      return font.familyName;
    } catch (e) {
      setState(() => _isLoadingCustomFonts = false);
      if (mounted) {
        _showFontErrorDialog(e.toString());
      }
      return null;
    }
  }

  /// Show dialog to enter/confirm custom font name.
  Future<String?> _showFontNameDialog(String suggestedName) async {
    final controller = TextEditingController(text: suggestedName);
    String? error;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          title: const Text('Name Your Font'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a display name for this font:',
                style: TextStyle(color: AppColors.settingsTextSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 30,
                decoration: InputDecoration(
                  hintText: 'Font name',
                  errorText: error,
                  counterText: '',
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.settingsAccent),
                  ),
                ),
                onChanged: (value) {
                  if (error != null) {
                    setDialogState(() => error = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'Name cannot be empty');
                  return;
                }
                // Check if name already exists
                final existing = await CustomFontManager.instance
                    .getCustomFontByDisplayName(name);
                if (existing != null) {
                  setDialogState(
                      () => error = 'A font with this name already exists');
                  return;
                }
                if (context.mounted) {
                  Navigator.of(context).pop(name);
                }
              },
              child: const Text('Install'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show error dialog for font operations.
  void _showFontErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        title: const Text('Font Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to manage custom fonts (view/delete).
  Future<void> _showManageFontsDialog() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          title: const Text('Custom Fonts'),
          content: SizedBox(
            width: 300,
            child: _customFonts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No custom fonts installed.\n\nSelect "Custom (TTF/OTF)" from the font dropdown to import a font.',
                      style: TextStyle(color: AppColors.settingsTextSecondary),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _customFonts.map((font) {
                      // Check if this font is currently in use
                      final isInUse =
                          _galleryDateStampFont == font.familyName ||
                              _exportDateStampFont == font.familyName;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                font.displayName,
                                style: TextStyle(fontFamily: font.familyName),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isInUse)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: AppColors.settingsAccent,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${(font.fileSize / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.settingsTextSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final confirm =
                                await _showDeleteFontConfirmation(font);
                            if (confirm == true) {
                              await _handleFontDeletion(font);
                              setDialogState(() {});
                              // Close dialog if all fonts deleted
                              if (_customFonts.isEmpty &&
                                  dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show confirmation dialog before deleting a font.
  Future<bool?> _showDeleteFontConfirmation(CustomFont font) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        title: const Text('Delete Font?'),
        content: Text(
          'Are you sure you want to delete "${font.displayName}"?\n\n'
          'Any projects using this font will revert to the default font.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Handle font deletion and reset project settings if needed.
  Future<void> _handleFontDeletion(CustomFont font) async {
    await CustomFontManager.instance.uninstallFont(font);

    // Check if this project was using the deleted font
    final projectIdStr = widget.projectId.toString();
    bool needsRefresh = false;

    // Check gallery font
    if (_galleryDateStampFont == font.familyName) {
      _galleryDateStampFont = DateStampUtils.defaultFont;
      await DB.instance.setSettingByTitle(
        'gallery_date_stamp_font',
        DateStampUtils.defaultFont,
        projectIdStr,
      );
      needsRefresh = true;
    }

    // Check export font
    if (_exportDateStampFont == font.familyName) {
      _exportDateStampFont = DateStampUtils.fontSameAsGallery;
      await DB.instance.setSettingByTitle(
        'export_date_stamp_font',
        DateStampUtils.fontSameAsGallery,
        projectIdStr,
      );
      needsRefresh = true;
    }

    await _loadCustomFonts();

    if (needsRefresh) {
      await widget.refreshSettings();
      // Recompile video if export was affected
      if (_exportDateStampEnabled) {
        await widget.recompileVideoCallback();
      }
    }

    setState(() {});
  }

  /// Build font dropdown items including custom fonts and import option.
  List<DropdownMenuItem<String>> _buildFontDropdownItems({
    bool includeCustomMarker = true,
    bool includeSameAsGallery = false,
  }) {
    final items = <DropdownMenuItem<String>>[];

    // Add "Same as thumbnail" option if requested (for export font)
    if (includeSameAsGallery) {
      items.add(
        DropdownMenuItem<String>(
          value: DateStampUtils.fontSameAsGallery,
          child: Text(DateStampUtils.getFontDisplayName(
              DateStampUtils.fontSameAsGallery)),
        ),
      );
    }

    // Add bundled fonts
    for (final font in DateStampUtils.bundledFonts) {
      items.add(
        DropdownMenuItem<String>(
          value: font,
          child: Text(
            DateStampUtils.getFontDisplayName(font),
            style: TextStyle(fontFamily: font),
          ),
        ),
      );
    }

    // Add custom fonts
    for (final font in _customFonts) {
      items.add(
        DropdownMenuItem<String>(
          value: font.familyName,
          child: Text(
            '${font.displayName} \u2605', // Star character
            style: TextStyle(fontFamily: font.familyName),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Add "Custom (TTF/OTF)" import option
    if (includeCustomMarker) {
      items.add(
        DropdownMenuItem<String>(
          value: DateStampUtils.fontCustomMarker,
          child: const Text('+ Custom (TTF/OTF)'),
        ),
      );
    }

    return items;
  }

  /// Handle font selection, including importing custom fonts.
  Future<void> _handleGalleryFontSelection(String? value) async {
    if (value == null) return;

    // Check if user wants to import a custom font
    if (value == DateStampUtils.fontCustomMarker) {
      final familyName = await _importCustomFont();
      if (familyName != null && mounted) {
        // Use the newly imported font
        final affectsExport = _exportDateStampEnabled &&
            _exportDateStampFont == DateStampUtils.fontSameAsGallery;
        if (affectsExport) {
          final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
            context,
            'font',
          );
          if (!shouldProceed) return;
        }

        setState(() => _galleryDateStampFont = familyName);
        await DB.instance.setSettingByTitle(
          'gallery_date_stamp_font',
          familyName,
          widget.projectId.toString(),
        );
        await widget.refreshSettings();

        if (affectsExport) {
          await widget.recompileVideoCallback();
        }
      }
      return;
    }

    // Regular font selection
    final affectsExport = _exportDateStampEnabled &&
        _exportDateStampFont == DateStampUtils.fontSameAsGallery;
    if (affectsExport) {
      final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
        context,
        'font',
      );
      if (!shouldProceed) return;
    }

    setState(() => _galleryDateStampFont = value);
    await DB.instance.setSettingByTitle(
      'gallery_date_stamp_font',
      value,
      widget.projectId.toString(),
    );
    await widget.refreshSettings();

    if (affectsExport) {
      await widget.recompileVideoCallback();
    }
  }

  /// Handle export font selection, including importing custom fonts.
  Future<void> _handleExportFontSelection(String? value) async {
    if (value == null) return;

    // Check if user wants to import a custom font
    if (value == DateStampUtils.fontCustomMarker) {
      final familyName = await _importCustomFont();
      if (familyName != null && mounted) {
        final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
          context,
          'font',
        );
        if (!shouldProceed) return;

        setState(() => _exportDateStampFont = familyName);
        await DB.instance.setSettingByTitle(
          'export_date_stamp_font',
          familyName,
          widget.projectId.toString(),
        );
        await widget.refreshSettings();
        await widget.recompileVideoCallback();
      }
      return;
    }

    // Regular font selection
    final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
      context,
      'font',
    );
    if (!shouldProceed) return;

    setState(() => _exportDateStampFont = value);
    await DB.instance.setSettingByTitle(
      'export_date_stamp_font',
      value,
      widget.projectId.toString(),
    );
    await widget.refreshSettings();
    await widget.recompileVideoCallback();
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

      await DB.instance.setSettingByTitle(
        'daily_notification_time',
        dailyNotificationTime,
        widget.projectId.toString(),
      );
      widget.refreshSettings();

      await _scheduleDailyNotification();
    }
  }

  Future<void> _scheduleDailyNotification() async {
    NotificationUtil.scheduleDailyNotification(
      widget.projectId,
      dailyNotificationTime,
    );
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
                    if (!widget.onlyShowVideoSettings &&
                        (Platform.isAndroid || Platform.isIOS))
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
                        'Date Stamp',
                        Icons.calendar_today_outlined,
                        _buildDateStampSettings,
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
          bottom: BorderSide(color: AppColors.settingsDivider, width: 1),
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
                Icon(icon, size: 18, color: AppColors.settingsTextSecondary),
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
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
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
      case 'Date Stamp':
        return _dateStampSettingsFuture;
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
            DB.instance.setSettingByTitle(
              'default_project',
              value ? widget.projectId.toString() : 'none',
            );
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
            await DB.instance.setSettingByTitle(
              'enable_notifications',
              value.toString(),
            );
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
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Column(
      children: [
        _buildGalleryGridModeDropdown(),
        if (_galleryGridMode == 'manual') _buildGridColumnsControl(isDesktop),
      ],
    );
  }

  Widget _buildGalleryGridModeDropdown() {
    return SettingListTile(
      title: 'Grid mode',
      showDivider: _galleryGridMode == 'manual',
      contentWidget: FutureBuilder<int>(
        future: _gridCountFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return CustomDropdownButton<String>(
            value: _galleryGridMode,
            items: const [
              DropdownMenuItem<String>(
                value: 'auto',
                child: Text('Auto'),
              ),
              DropdownMenuItem<String>(
                value: 'manual',
                child: Text('Manual'),
              ),
            ],
            onChanged: (String? value) async {
              if (value != null && value != _galleryGridMode) {
                setState(() {
                  _galleryGridMode = value;
                });
                await SettingsUtil.setGalleryGridMode(
                  widget.projectId.toString(),
                  value,
                );
                widget.refreshSettings();
              }
            },
          );
        },
      ),
      infoContent:
          'Auto: Tiles resize based on window width with optimized sizing.\n\n'
          'Manual: Displays an exact number of columns regardless of window size.',
      showInfo: true,
    );
  }

  Widget _buildGridColumnsControl(bool isDesktop) {
    return SettingListTile(
      title: 'Grid columns',
      showDivider: false,
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
            return _buildColumnDropdown(isDesktop);
          }
          return const Text('Error');
        },
      ),
      infoContent:
          'Choose how many columns of photos to display in the gallery grid.',
      showInfo: true,
    );
  }

  Widget _buildColumnDropdown(bool isDesktop) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final int maxSteps = isDesktop ? 12 : 6;

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
              setLocalState(() {
                gridCount = value;
              });
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

  Widget _buildStabilizationSettings() {
    return Column(
      children: [_buildStabilizationModeDropdown(), _buildEyeScaleButton()],
    );
  }

  Widget _buildVideoSettings() {
    return Column(
      children: [
        _buildResolutionDropdown(),
        if (!_isCustomResolution) ...[
          _buildProjectOrientationDropdown(),
          _buildAspectRatioDropdown(),
          _buildOutputResolutionDisplay(),
        ],
        _buildFramerateDropdown(framerate ?? 30),
        _buildAutoCompileVideoSwitch(),
      ],
    );
  }

  Widget _buildAutoCompileVideoSwitch() {
    return BoolSettingSwitch(
      title: 'Auto-compile video',
      initialValue: _autoCompileVideo,
      showDivider: false,
      showInfo: true,
      infoContent:
          'When enabled, your video is automatically updated after each photo you take.\n\n'
          'Turn this off if you have a large project and want to save time. '
          'You can then manually compile your video from the Create tab whenever you\'re ready.',
      onChanged: (bool value) async {
        setState(() => _autoCompileVideo = value);
        await SettingsUtil.setAutoCompileVideo(
          widget.projectId.toString(),
          value,
        );
      },
    );
  }

  /// Calculates output dimensions from the current resolution setting.
  /// For presets, uses aspect ratio and orientation.
  /// For custom WIDTHxHEIGHT, returns exact dimensions.
  (int, int)? _calculateOutputDimensions() {
    return StabUtils.getOutputDimensions(
      resolution,
      aspectRatio,
      projectOrientation,
    );
  }

  Widget _buildOutputResolutionDisplay() {
    final dims = _calculateOutputDimensions();
    if (dims == null) return const SizedBox.shrink();

    return SettingListTile(
      title: 'Output resolution',
      showDivider: true,
      contentWidget: Text(
        '${dims.$1} × ${dims.$2}',
        style: const TextStyle(
          color: AppColors.settingsTextPrimary,
          fontSize: 14,
        ),
      ),
      infoContent: '',
      showInfo: false,
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

  Widget _buildDateStampSettings() {
    final bool galleryEnabled =
        _galleryDateLabelsEnabled || _galleryRawDateLabelsEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gallery section header
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            'Gallery Thumbnails',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
            ),
          ),
        ),
        // Stabilized thumbnails toggle
        BoolSettingSwitch(
          title: 'Show on stabilized',
          initialValue: _galleryDateLabelsEnabled,
          showDivider: true,
          onChanged: (bool value) async {
            setState(() => _galleryDateLabelsEnabled = value);
            await DB.instance.setSettingByTitle(
              'gallery_date_labels_enabled',
              value.toString(),
              widget.projectId.toString(),
            );
            widget.refreshSettings();
          },
        ),
        // Raw thumbnails toggle
        BoolSettingSwitch(
          title: 'Show on raw',
          initialValue: _galleryRawDateLabelsEnabled,
          showDivider: true,
          onChanged: (bool value) async {
            setState(() => _galleryRawDateLabelsEnabled = value);
            await DB.instance.setSettingByTitle(
              'gallery_raw_date_labels_enabled',
              value.toString(),
              widget.projectId.toString(),
            );
            widget.refreshSettings();
          },
        ),
        // Gallery date format dropdown with Custom option
        SettingListTile(
          title: 'Format',
          showDivider: !_isGalleryCustomFormat,
          contentWidget: CustomDropdownButton<String>(
            value: _isGalleryCustomFormat
                ? DateStampUtils.galleryFormatCustom
                : _galleryDateFormat,
            items: [
              DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatMMYY,
                child: Text(
                  DateStampUtils.getGalleryFormatExample(
                    DateStampUtils.galleryFormatMMYY,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatMMMDD,
                child: Text(
                  DateStampUtils.getGalleryFormatExample(
                    DateStampUtils.galleryFormatMMMDD,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatMMMDDYY,
                child: Text(
                  DateStampUtils.getGalleryFormatExample(
                    DateStampUtils.galleryFormatMMMDDYY,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatDDMMM,
                child: Text(
                  DateStampUtils.getGalleryFormatExample(
                    DateStampUtils.galleryFormatDDMMM,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatMMMYYYY,
                child: Text(
                  DateStampUtils.getGalleryFormatExample(
                    DateStampUtils.galleryFormatMMMYYYY,
                  ),
                ),
              ),
              const DropdownMenuItem<String>(
                value: DateStampUtils.galleryFormatCustom,
                child: Text('Custom...'),
              ),
            ],
            onChanged: galleryEnabled
                ? (String? value) async {
                    if (value == DateStampUtils.galleryFormatCustom) {
                      // Switch to custom mode
                      setState(() {
                        _isGalleryCustomFormat = true;
                        _galleryCustomFormatController.text =
                            _galleryDateFormat;
                      });
                    } else if (value != null) {
                      setState(() {
                        _isGalleryCustomFormat = false;
                        _galleryDateFormat = value;
                        _galleryCustomFormatError = null;
                      });
                      await DB.instance.setSettingByTitle(
                        'gallery_date_format',
                        value,
                        widget.projectId.toString(),
                      );
                      widget.refreshSettings();
                    }
                  }
                : null,
          ),
          infoContent: DateStampUtils.galleryFormatHelpText,
          showInfo: true,
          disabled: !galleryEnabled,
        ),
        // Custom format input for gallery (shown when Custom is selected)
        if (_isGalleryCustomFormat)
          _buildCustomFormatInput(
            controller: _galleryCustomFormatController,
            error: _galleryCustomFormatError,
            maxLength: DateStampUtils.galleryFormatMaxLength,
            enabled: galleryEnabled,
            onChanged: (value) {
              final error = DateStampUtils.validateGalleryFormat(value);
              setState(() => _galleryCustomFormatError = error);
            },
            onSubmit: (value) async {
              final error = DateStampUtils.validateGalleryFormat(value);
              if (error == null) {
                setState(() {
                  _galleryDateFormat = value;
                  _galleryCustomFormatError = null;
                });
                await DB.instance.setSettingByTitle(
                  'gallery_date_format',
                  value,
                  widget.projectId.toString(),
                );
                widget.refreshSettings();
              } else {
                setState(() => _galleryCustomFormatError = error);
              }
            },
          ),
        // Gallery font dropdown (includes custom fonts and import option)
        SettingListTile(
          title: 'Font',
          showDivider: _customFonts.isEmpty,
          contentWidget: _isLoadingCustomFonts
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : CustomDropdownButton<String>(
                  value: _galleryDateStampFont,
                  items: _buildFontDropdownItems(),
                  onChanged:
                      galleryEnabled ? _handleGalleryFontSelection : null,
                ),
          infoContent:
              'Select "Custom (TTF/OTF)" to import your own font file.',
          showInfo: true,
          disabled: !galleryEnabled,
        ),
        // Manage custom fonts button (shown when custom fonts exist)
        if (_customFonts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: TextButton.icon(
              onPressed: galleryEnabled ? _showManageFontsDialog : null,
              icon: const Icon(Icons.settings, size: 16),
              label: Text(
                'Manage ${_customFonts.length} custom font${_customFonts.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.settingsAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),

        // Export section header
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            'Export & Video',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
            ),
          ),
        ),
        // Export date stamp toggle
        BoolSettingSwitch(
          title: 'Add date stamp to exports',
          initialValue: _exportDateStampEnabled,
          showDivider: true,
          onChanged: (bool value) async {
            // Show confirmation dialog when enabling or disabling
            final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
              context,
              value
                  ? 'settings (enabling date stamps)'
                  : 'settings (disabling date stamps)',
            );
            if (!shouldProceed) return;

            setState(() => _exportDateStampEnabled = value);
            await DB.instance.setSettingByTitle(
              'export_date_stamp_enabled',
              value.toString(),
              widget.projectId.toString(),
            );
            await widget.refreshSettings();
            await widget.recompileVideoCallback();
          },
        ),
        // Export position dropdown
        SettingListTile(
          title: 'Position',
          showDivider: true,
          contentWidget: CustomDropdownButton<String>(
            value: _exportDateStampPosition,
            items: const [
              DropdownMenuItem<String>(
                value: DateStampUtils.positionLowerRight,
                child: Text('Lower right'),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.positionLowerLeft,
                child: Text('Lower left'),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.positionUpperRight,
                child: Text('Upper right'),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.positionUpperLeft,
                child: Text('Upper left'),
              ),
            ],
            onChanged: _exportDateStampEnabled
                ? (String? value) async {
                    if (value != null) {
                      final shouldProceed =
                          await ConfirmActionDialog.showRecompileVideo(
                        context,
                        'position',
                      );
                      if (!shouldProceed) return;

                      setState(() => _exportDateStampPosition = value);
                      await DB.instance.setSettingByTitle(
                        'export_date_stamp_position',
                        value,
                        widget.projectId.toString(),
                      );
                      await widget.refreshSettings();
                      await widget.recompileVideoCallback();
                    }
                  }
                : null,
          ),
          infoContent: '',
          showInfo: false,
          disabled: !_exportDateStampEnabled,
        ),
        // Export format dropdown with Custom option
        SettingListTile(
          title: 'Format',
          showDivider: !_isExportCustomFormat,
          contentWidget: CustomDropdownButton<String>(
            value: _isExportCustomFormat
                ? DateStampUtils.exportFormatCustom
                : _exportDateStampFormat,
            items: [
              DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatLong,
                child: Text(
                  DateStampUtils.getExportFormatExample(
                    DateStampUtils.exportFormatLong,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatISO,
                child: Text(
                  DateStampUtils.getExportFormatExample(
                    DateStampUtils.exportFormatISO,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatUS,
                child: Text(
                  DateStampUtils.getExportFormatExample(
                    DateStampUtils.exportFormatUS,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatEU,
                child: Text(
                  DateStampUtils.getExportFormatExample(
                    DateStampUtils.exportFormatEU,
                  ),
                ),
              ),
              DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatShort,
                child: Text(
                  DateStampUtils.getExportFormatExample(
                    DateStampUtils.exportFormatShort,
                  ),
                ),
              ),
              const DropdownMenuItem<String>(
                value: DateStampUtils.exportFormatCustom,
                child: Text('Custom...'),
              ),
            ],
            onChanged: _exportDateStampEnabled
                ? (String? value) async {
                    if (value == DateStampUtils.exportFormatCustom) {
                      // Switch to custom mode (no confirmation needed, just UI change)
                      setState(() {
                        _isExportCustomFormat = true;
                        _exportCustomFormatController.text =
                            _exportDateStampFormat;
                      });
                    } else if (value != null) {
                      final shouldProceed =
                          await ConfirmActionDialog.showRecompileVideo(
                        context,
                        'format',
                      );
                      if (!shouldProceed) return;

                      setState(() {
                        _isExportCustomFormat = false;
                        _exportDateStampFormat = value;
                        _exportCustomFormatError = null;
                      });
                      await DB.instance.setSettingByTitle(
                        'export_date_stamp_format',
                        value,
                        widget.projectId.toString(),
                      );
                      await widget.refreshSettings();
                      await widget.recompileVideoCallback();
                    }
                  }
                : null,
          ),
          infoContent: DateStampUtils.exportFormatHelpText,
          showInfo: true,
          disabled: !_exportDateStampEnabled,
        ),
        // Custom format input for export (shown when Custom is selected)
        if (_isExportCustomFormat)
          _buildCustomFormatInput(
            controller: _exportCustomFormatController,
            error: _exportCustomFormatError,
            maxLength: DateStampUtils.exportFormatMaxLength,
            enabled: _exportDateStampEnabled,
            onChanged: (value) {
              final error = DateStampUtils.validateExportFormat(value);
              setState(() => _exportCustomFormatError = error);
            },
            onSubmit: (value) async {
              final error = DateStampUtils.validateExportFormat(value);
              if (error == null) {
                final shouldProceed =
                    await ConfirmActionDialog.showRecompileVideo(
                  context,
                  'format',
                );
                if (!shouldProceed) return;

                setState(() {
                  _exportDateStampFormat = value;
                  _exportCustomFormatError = null;
                });
                await DB.instance.setSettingByTitle(
                  'export_date_stamp_format',
                  value,
                  widget.projectId.toString(),
                );
                await widget.refreshSettings();
                await widget.recompileVideoCallback();
              } else {
                setState(() => _exportCustomFormatError = error);
              }
            },
          ),
        // Export font dropdown (includes custom fonts and import option)
        SettingListTile(
          title: 'Font',
          showDivider: true,
          contentWidget: _isLoadingCustomFonts
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : CustomDropdownButton<String>(
                  value: _exportDateStampFont,
                  items: _buildFontDropdownItems(includeSameAsGallery: true),
                  onChanged: _exportDateStampEnabled
                      ? _handleExportFontSelection
                      : null,
                ),
          infoContent: '',
          showInfo: false,
          disabled: !_exportDateStampEnabled,
        ),
        // Export size dropdown
        SettingListTile(
          title: 'Size',
          showDivider: true,
          contentWidget: CustomDropdownButton<int>(
            value: _exportDateStampSize,
            items: List.generate(6, (index) {
              final size = index + 1;
              return DropdownMenuItem<int>(value: size, child: Text('$size%'));
            }),
            onChanged: _exportDateStampEnabled
                ? (int? value) async {
                    if (value != null) {
                      final shouldProceed =
                          await ConfirmActionDialog.showRecompileVideo(
                        context,
                        'size',
                      );
                      if (!shouldProceed) return;

                      setState(() => _exportDateStampSize = value);
                      await DB.instance.setSettingByTitle(
                        'export_date_stamp_size',
                        value.toString(),
                        widget.projectId.toString(),
                      );
                      await widget.refreshSettings();
                      await widget.recompileVideoCallback();
                    }
                  }
                : null,
          ),
          infoContent: '',
          showInfo: false,
          disabled: !_exportDateStampEnabled,
        ),
        // Export opacity dropdown
        SettingListTile(
          title: 'Opacity',
          contentWidget: CustomDropdownButton<double>(
            value: _exportDateStampOpacity,
            items: List.generate(8, (index) {
              final opacity = (index + 3) * 0.1; // 0.3 to 1.0
              return DropdownMenuItem<double>(
                value: double.parse(opacity.toStringAsFixed(1)),
                child: Text('${(opacity * 100).toInt()}%'),
              );
            }),
            onChanged: _exportDateStampEnabled
                ? (double? value) async {
                    if (value != null) {
                      final shouldProceed =
                          await ConfirmActionDialog.showRecompileVideo(
                        context,
                        'opacity',
                      );
                      if (!shouldProceed) return;

                      setState(() => _exportDateStampOpacity = value);
                      await DB.instance.setSettingByTitle(
                        'export_date_stamp_opacity',
                        value.toString(),
                        widget.projectId.toString(),
                      );
                      await widget.refreshSettings();
                      await widget.recompileVideoCallback();
                    }
                  }
                : null,
          ),
          infoContent: '',
          showInfo: false,
          disabled: !_exportDateStampEnabled,
        ),
      ],
    );
  }

  /// Build custom format input widget with preview and validation.
  Widget _buildCustomFormatInput({
    required TextEditingController controller,
    required String? error,
    required int maxLength,
    required bool enabled,
    required void Function(String) onChanged,
    required Future<void> Function(String) onSubmit,
  }) {
    final hasError = error != null;
    final preview = DateStampUtils.getFormatPreview(controller.text);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text field with monospace font
          TextField(
            controller: controller,
            enabled: enabled,
            maxLength: maxLength,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: enabled
                  ? AppColors.settingsTextPrimary
                  : AppColors.settingsTextSecondary,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: AppColors.settingsInputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? Colors.red : AppColors.settingsDivider,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? Colors.red : AppColors.settingsDivider,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? Colors.red : AppColors.settingsAccent,
                  width: 1.5,
                ),
              ),
              counterText: '',
              hintText: 'e.g. MMM d, yyyy',
              hintStyle: TextStyle(
                color: AppColors.settingsTextSecondary.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
            ),
            onChanged: onChanged,
            onSubmitted: (value) => onSubmit(value),
          ),
          const SizedBox(height: 6),
          // Preview and error row
          Row(
            children: [
              // Preview
              Expanded(
                child: Text(
                  hasError ? '' : 'Preview: $preview',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.settingsTextSecondary,
                  ),
                ),
              ),
              // Character count
              Text(
                '${controller.text.length}/$maxLength',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.settingsTextSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          // Error message
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            ),
          // Apply button
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: enabled && !hasError && controller.text.isNotEmpty
                  ? () => onSubmit(controller.text)
                  : null,
              style: TextButton.styleFrom(
                backgroundColor:
                    AppColors.settingsAccent.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Apply',
                style: TextStyle(
                  color: enabled && !hasError && controller.text.isNotEmpty
                      ? AppColors.settingsAccent
                      : AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
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
        if (Platform.isAndroid || Platform.isIOS)
          _buildSaveToCameraRollSwitch(saveToCameraRoll),
        BoolSettingSwitch(
          title: 'Mirror front camera',
          initialValue: cameraMirror,
          onChanged: (bool value) async {
            setState(() {
              cameraMirror = value;
            });

            LogService.instance.log(
              "Setting camera_mirror to ${value.toString()}",
            );

            await DB.instance.setSettingByTitle(
              'camera_mirror',
              value.toString(),
              widget.projectId.toString(),
            );
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
      3: "Ghost + Grid",
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
            value: "Landscape",
            child: Text("Landscape"),
          ),
        ],
        onChanged: (String? value) async {
          if (value != null && value != projectOrientation) {
            final bool shouldProceed = await Utils.showConfirmChangeDialog(
              context,
              "project orientation",
            );
            if (shouldProceed) {
              await widget.cancelStabCallback();

              setState(() => projectOrientation = value);
              await DB.instance.setSettingByTitle(
                'project_orientation',
                value.toLowerCase(),
                widget.projectId.toString(),
              );
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
          'framerate',
          newValue.toString(),
          widget.projectId.toString(),
        );
        widget.refreshSettings();
        widget.stabCallback();
      },
    );
  }

  Future<void> resetStabStatusAndRestartStabilization() async {
    await DB.instance.resetStabilizationStatusForProject(
      widget.projectId,
      projectOrientation,
    );

    // Clear ALL caches
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ThumbnailService.instance.clearAllCache();

    widget.clearRawAndStabPhotos();
    widget.stabCallback();
  }

  Widget _buildResolutionDropdown() {
    return Column(
      children: [
        SettingListTile(
          title: 'Resolution',
          showDivider: !_isCustomResolution,
          contentWidget: CustomDropdownButton<String>(
            value: _isCustomResolution ? 'Custom' : resolution,
            items: _getResolutionDropdownItems(),
            onChanged: (String? value) async {
              if (value == null) return;

              if (value == 'Custom') {
                // Switching to custom mode - pre-populate with current dimensions
                if (!_isCustomResolution) {
                  final dims = _calculateOutputDimensions();
                  final w = dims?.$1.toString() ?? '';
                  final h = dims?.$2.toString() ?? '';
                  setState(() {
                    _isCustomResolution = true;
                    _customWidthController.text = w;
                    _customHeightController.text = h;
                    _customResolutionBaseline = '${w}x$h';
                    _customResolutionModified = false;
                    _customResolutionError = null;
                  });
                }
                return;
              }

              // Switching from custom to preset, or preset to preset
              if (value != resolution || _isCustomResolution) {
                bool shouldProceed = await Utils.showConfirmChangeDialog(
                  context,
                  "resolution",
                );

                if (shouldProceed) {
                  setState(() {
                    resolution = value;
                    _isCustomResolution = false;
                    _customResolutionError = null;
                  });

                  await widget.cancelStabCallback();
                  await DB.instance.setSettingByTitle(
                    'video_resolution',
                    value,
                    widget.projectId.toString(),
                  );
                  await widget.refreshSettings();

                  await resetStabStatusAndRestartStabilization();
                }
              }
            },
          ),
          infoContent: '',
          showInfo: false,
        ),
        if (_isCustomResolution) _buildCustomResolutionInput(),
      ],
    );
  }

  Widget _buildCustomResolutionInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Width field
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _customWidthController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: AppColors.settingsTextPrimary,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: '1920',
                        hintStyle: const TextStyle(
                          color: AppColors.settingsTextTertiary,
                          fontSize: 16,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsTextTertiary,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsTextTertiary,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsAccent,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _applyCustomResolution(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'width',
                      style: TextStyle(
                        color: AppColors.settingsTextTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // × symbol
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '×',
                    style: TextStyle(
                      color: AppColors.settingsTextSecondary,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              // Height field
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _customHeightController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: AppColors.settingsTextPrimary,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: '1080',
                        hintStyle: const TextStyle(
                          color: AppColors.settingsTextTertiary,
                          fontSize: 16,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsTextTertiary,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsTextTertiary,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.settingsAccent,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _applyCustomResolution(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'height',
                      style: TextStyle(
                        color: AppColors.settingsTextTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Apply button (full width) - reactive styling based on changes
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _customResolutionModified ? _applyCustomResolution : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _customResolutionModified
                    ? AppColors.settingsAccent
                    : AppColors.settingsCardBorder,
                foregroundColor: _customResolutionModified
                    ? Colors.white
                    : AppColors.settingsTextTertiary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                disabledBackgroundColor: AppColors.settingsCardBorder,
                disabledForegroundColor: AppColors.settingsTextTertiary,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_customResolutionModified) ...[
                    const Icon(Icons.save_outlined, size: 18),
                    const SizedBox(width: 8),
                  ],
                  const Text('Apply'),
                ],
              ),
            ),
          ),
          // Error message
          if (_customResolutionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _customResolutionError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applyCustomResolution() async {
    final widthStr = _customWidthController.text.trim();
    final heightStr = _customHeightController.text.trim();
    final width = int.tryParse(widthStr);
    final height = int.tryParse(heightStr);

    // Validate
    if (width == null || height == null) {
      setState(() => _customResolutionError = 'Enter valid numbers');
      return;
    }
    if (width < 480 || height < 480) {
      setState(() => _customResolutionError = 'Minimum dimension is 480');
      return;
    }
    if (width > 7680 || height > 7680) {
      setState(() => _customResolutionError = 'Maximum dimension is 7680');
      return;
    }
    if (width % 2 != 0 || height % 2 != 0) {
      setState(() => _customResolutionError = 'Dimensions must be even');
      return;
    }

    // Valid - apply the resolution
    final newResolution = '${width}x$height';
    if (newResolution == resolution && _customResolutionError == null) {
      // No change needed
      return;
    }

    bool shouldProceed = await Utils.showConfirmChangeDialog(
      context,
      "resolution",
    );

    if (shouldProceed) {
      setState(() {
        resolution = newResolution;
        _customResolutionBaseline = newResolution;
        _customResolutionError = null;
        _customResolutionModified = false;
      });

      await widget.cancelStabCallback();
      await DB.instance.setSettingByTitle(
        'video_resolution',
        newResolution,
        widget.projectId.toString(),
      );
      await widget.refreshSettings();

      await resetStabStatusAndRestartStabilization();
    }
  }

  List<DropdownMenuItem<String>> _getResolutionDropdownItems() {
    return const [
      DropdownMenuItem<String>(value: "1080p", child: Text("1080p")),
      DropdownMenuItem<String>(value: "4K", child: Text("4K")),
      DropdownMenuItem<String>(value: "8K", child: Text("8K")),
      DropdownMenuItem<String>(value: "Custom", child: Text("Custom")),
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
              context,
              "stabilization mode",
            );

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
            bool shouldProceed = await Utils.showConfirmChangeDialog(
              context,
              "aspect ratio",
            );

            if (shouldProceed) {
              LogService.instance.log(
                '[SettingsSheet] Aspect ratio changing to: $value',
              );
              setState(() => aspectRatio = value);
              await DB.instance.setSettingByTitle(
                'aspect_ratio',
                value,
                widget.projectId.toString(),
              );
              LogService.instance.log(
                '[SettingsSheet] DB updated, cancelling stab...',
              );

              await widget.cancelStabCallback();
              LogService.instance.log(
                '[SettingsSheet] Stab cancelled, refreshing settings...',
              );
              await widget.refreshSettings();
              LogService.instance.log(
                '[SettingsSheet] Settings refreshed, restarting stabilization...',
              );

              await resetStabStatusAndRestartStabilization();
              LogService.instance.log(
                '[SettingsSheet] Stabilization restarted',
              );
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
            clearRawAndStabPhotos: widget.clearRawAndStabPhotos,
            stabCallback: widget.stabCallback,
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
          'enable_watermark',
          value.toString(),
          widget.projectId.toString(),
        );

        widget.refreshSettings();
      },
    );
  }

  Widget _buildWatermarkImageInput() {
    return SettingListTile(
      title: 'Watermark image',
      showDivider: true,
      contentWidget: ImagePickerWidget(
        disabled: !enableWatermark,
        projectId: widget.projectId,
      ),
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
            value: "Upper left",
            child: Text("Upper left"),
          ),
          DropdownMenuItem<String>(
            value: "Upper right",
            child: Text("Upper right"),
          ),
          DropdownMenuItem<String>(
            value: "Lower left",
            child: Text("Lower left"),
          ),
          DropdownMenuItem<String>(
            value: "Lower right",
            child: Text("Lower right"),
          ),
        ],
        onChanged: enableWatermark
            ? (String? value) async {
                if (value != null) {
                  setState(() => watermarkPosition = value);
                  await DB.instance.setSettingByTitle(
                    'watermark_position',
                    value,
                  );

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

  const ImagePickerWidget({
    super.key,
    required this.disabled,
    required this.projectId,
  });

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
              watermarkFilePath,
              pngBytes,
            );
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
