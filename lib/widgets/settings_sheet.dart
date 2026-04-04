import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:provider/provider.dart';
import '../screens/set_eye_position_page.dart';
import '../services/custom_font_manager.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../services/theme_provider.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../models/video_background.dart';
import '../models/video_codec.dart';
import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/linked_source_utils.dart';
import '../utils/platform_utils.dart';
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
import 'section_header.dart';
import 'setting_list_tile.dart';

typedef _SectionBuilder = Widget Function();

class _Section {
  final String title;
  final IconData icon;
  final _SectionBuilder builder;
  final Future<dynamic> Function() futureGetter;
  final bool isDangerZone;

  const _Section(
    this.title,
    this.icon,
    this.builder,
    this.futureGetter, {
    this.isDangerZone = false,
  });
}

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
  final Future<void> _defaultSettingsFuture = Future<void>.value();

  Future<Map<String, bool>> get _settingsFuture => _settingsCompleter.future;
  Future<void> get _notificationInitialization => _notificationCompleter.future;
  Future<void> get _videoSettingsFuture => _videoSettingsCompleter.future;
  Future<void> get _watermarkSettingsFuture =>
      _watermarkSettingsCompleter.future;
  Future<int> get _gridCountFuture => _gridCountCompleter.future;
  Future<void> get _projectSettingsFuture => _projectSettingsCompleter.future;
  Future<void> get _dateStampSettingsFuture =>
      _dateStampSettingsCompleter.future;

  int _selectedSectionIndex = 0;

  bool _isDefaultProject = false;
  bool _linkedSourceEnabled = false;
  String _linkedSourceDisplayPath = '';
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
  String _backgroundColor = '#000000';

  // Video codec settings
  VideoCodec _videoCodec = VideoCodec.h264;
  VideoBackground _videoBackground = const VideoBackground.transparent();

  // Lossless storage
  bool _losslessStorage = false;

  // Date stamp settings
  bool _galleryDateLabelsEnabled = false;
  bool _galleryRawDateLabelsEnabled = false;
  String _galleryDateFormat = DateStampUtils.galleryFormatMMYY;
  String _galleryDateStampFont = DateStampUtils.defaultFont;
  int _galleryDateStampSize = DateStampUtils.defaultGallerySizeLevel;
  bool _exportDateStampEnabled = false;
  String _exportDateStampPosition = DateStampUtils.positionLowerRight;
  String _exportDateStampFormat = DateStampUtils.exportFormatLong;
  int _exportDateStampSize = 3;
  int _exportDateStampMargin = 2;
  bool _isCustomMargin = false;
  double _customMarginH = 2.0;
  double _customMarginV = 2.0;
  final TextEditingController _customMarginHController =
      TextEditingController();
  final TextEditingController _customMarginVController =
      TextEditingController();
  String? _customMarginHError;
  String? _customMarginVError;
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
    _customMarginHController.dispose();
    _customMarginVController.dispose();
    super.dispose();
  }

  /// Wires a future to a completer: completes on success, propagates error on failure.
  void _wireCompleter<T>(Future<T> future, Completer<T> completer) {
    future.then(completer.complete).catchError(completer.completeError);
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

    _wireCompleter(_initializeVideoSettings(), _videoSettingsCompleter);
    _wireCompleter(_initializeWatermarkSettings(), _watermarkSettingsCompleter);
    _wireCompleter(_initializeGridCount(), _gridCountCompleter);
    _wireCompleter(_initializeProjectSettings(), _projectSettingsCompleter);
    _wireCompleter(_initializeDateStampSettings(), _dateStampSettingsCompleter);
  }

  Future<void> _initializeProjectSettings() async {
    final data = await DB.instance.getSettingByTitle('default_project');
    final defaultProject = data?['value'];
    final linkedConfig = await LinkedSourceUtils.loadConfig(widget.projectId);

    if (defaultProject == null || defaultProject == "none") {
      _isDefaultProject = false;
    } else {
      _isDefaultProject = int.tryParse(defaultProject) == widget.projectId;
    }
    _linkedSourceEnabled = linkedConfig.enabled;
    _linkedSourceDisplayPath = linkedConfig.displayPath;
    setStateIfMounted(() {});
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
      SettingsUtil.loadBackgroundColor(projectIdStr),
      SettingsUtil.loadVideoCodec(projectIdStr),
      SettingsUtil.loadVideoBackground(projectIdStr),
      SettingsUtil.loadLosslessStorage(projectIdStr),
    ]);

    resolution = results[0] as String;
    aspectRatio = results[1] as String;
    framerate = results[2] as int;
    final poSetting = results[3] as String;
    projectOrientation =
        poSetting[0].toUpperCase() + poSetting.substring(1).toLowerCase();
    _autoCompileVideo = results[4] as bool;
    _backgroundColor = results[5] as String;
    _videoCodec = results[6] as VideoCodec;
    _videoBackground = results[7] as VideoBackground;
    _losslessStorage = results[8] as bool;

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

    setStateIfMounted(() {});
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
    setStateIfMounted(() {});
  }

  Future<int> _initializeGridCount() async {
    final projectIdStr = widget.projectId.toString();
    final results = await Future.wait([
      SettingsUtil.loadGridAxisCount(projectIdStr),
      SettingsUtil.loadGalleryGridMode(projectIdStr),
    ]);
    gridCount = results[0] as int;
    _galleryGridMode = results[1] as String;
    if (!mounted) return gridCount;
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
    _galleryDateStampSize = settings.gallerySizeLevel;
    _exportDateStampEnabled = settings.exportEnabled;
    _exportDateStampPosition = settings.exportPosition;
    _exportDateStampFormat = settings.exportFormat;
    _exportDateStampSize = settings.exportSizePercent;
    _exportDateStampMargin = settings.exportMarginPercent;
    _customMarginH = settings.exportMarginH;
    _customMarginV = settings.exportMarginV;
    _isCustomMargin =
        settings.exportMarginPercent == DateStampUtils.marginCustom;
    if (_isCustomMargin) {
      _customMarginHController.text = _customMarginH.toString();
      _customMarginVController.text = _customMarginV.toString();
    }
    _exportDateStampOpacity = settings.exportOpacity;
    _exportDateStampFont = settings.exportFont;

    // Check if gallery format is custom (not a preset)
    _isGalleryCustomFormat = !DateStampUtils.isGalleryPreset(
      _galleryDateFormat,
    );
    if (_isGalleryCustomFormat) {
      _galleryCustomFormatController.text = _galleryDateFormat;
    }

    // Check if export format is custom (not a preset)
    _isExportCustomFormat = !DateStampUtils.isExportPreset(
      _exportDateStampFormat,
    );
    if (_isExportCustomFormat) {
      _exportCustomFormatController.text = _exportDateStampFormat;
    }

    // Load custom fonts
    await _loadCustomFonts();

    setStateIfMounted(() {});
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
        if (!mounted) return null;
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        if (!mounted) return null;
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      // Validate the font file
      final validation = await CustomFontManager.instance.validateFontFile(
        filePath,
      );
      if (!validation.isValid) {
        if (!mounted) return null;
        setState(() => _isLoadingCustomFonts = false);
        _showFontErrorDialog(validation.errorMessage ?? 'Invalid font file');
        return null;
      }

      // Show dialog to confirm font name
      final displayName = await _showFontNameDialog(
        validation.suggestedName ?? 'Custom Font',
      );
      if (displayName == null) {
        if (!mounted) return null;
        setState(() => _isLoadingCustomFonts = false);
        return null;
      }

      // Install the font
      final font = await CustomFontManager.instance.installFont(
        filePath,
        displayName,
      );

      // Refresh custom fonts list
      await _loadCustomFonts();
      if (!mounted) return null;
      setState(() => _isLoadingCustomFonts = false);

      return font.familyName;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _isLoadingCustomFonts = false);
      _showFontErrorDialog(e.toString());
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
              Text(
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
                  focusedBorder: OutlineInputBorder(
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
                    () => error = 'A font with this name already exists',
                  );
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
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
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
                          style: TextStyle(
                            fontSize: AppTypography.sm,
                            color: AppColors.settingsTextSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final confirm = await _showDeleteFontConfirmation(
                              font,
                            );
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
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
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
          child: Text(
            DateStampUtils.getFontDisplayName(DateStampUtils.fontSameAsGallery),
          ),
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

  /// Saves a font setting to DB and refreshes, optionally triggering recompile.
  Future<void> _saveFontSetting(
    String dbKey,
    String fontValue,
    VoidCallback setStateUpdate, {
    bool recompile = false,
  }) async {
    setState(setStateUpdate);
    await DB.instance.setSettingByTitle(
      dbKey,
      fontValue,
      widget.projectId.toString(),
    );
    await widget.refreshSettings();
    if (recompile) await widget.recompileVideoCallback();
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

        await _saveFontSetting(
          'gallery_date_stamp_font',
          familyName,
          () => _galleryDateStampFont = familyName,
          recompile: affectsExport,
        );
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

    await _saveFontSetting(
      'gallery_date_stamp_font',
      value,
      () => _galleryDateStampFont = value,
      recompile: affectsExport,
    );
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

        await _saveFontSetting(
          'export_date_stamp_font',
          familyName,
          () => _exportDateStampFont = familyName,
          recompile: true,
        );
      }
      return;
    }

    // Regular font selection
    final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
      context,
      'font',
    );
    if (!shouldProceed) return;

    await _saveFontSetting(
      'export_date_stamp_font',
      value,
      () => _exportDateStampFont = value,
      recompile: true,
    );
  }

  void _updateSetting(String title, bool value) {
    DB.instance.setSettingByTitle(title, value.toString().toLowerCase());
    widget.refreshSettings();
  }

  Future<void> _saveProjectSetting(String key, String value) async {
    await DB.instance
        .setSettingByTitle(key, value, widget.projectId.toString());
    widget.refreshSettings();
  }

  Future<void> _saveGlobalSetting(String key, String value) async {
    await DB.instance.setSettingByTitle(key, value);
    widget.refreshSettings();
  }

  /// Shows recompile-video confirmation, then saves the setting and triggers recompile.
  /// [confirmLabel] is the setting name shown in the dialog.
  /// [updateState] should call setState to update the local variable.
  /// [dbKey] is the DB setting key; [dbValue] is the new value to save.
  Future<void> _confirmAndSaveVideoSetting({
    required String confirmLabel,
    required VoidCallback updateState,
    required String dbKey,
    required String dbValue,
  }) async {
    final shouldProceed = await ConfirmActionDialog.showRecompileVideo(
      context,
      confirmLabel,
    );
    if (!shouldProceed || !mounted) return;
    setState(updateState);
    await DB.instance.setSettingByTitle(
      dbKey,
      dbValue,
      widget.projectId.toString(),
    );
    await widget.refreshSettings();
    await widget.recompileVideoCallback();
  }

  /// Builds a [BoolSettingSwitch] that saves a per-project boolean setting.
  /// On toggle: calls setState, persists to DB, and calls refreshSettings.
  Widget _buildSimpleBoolSetting({
    required String title,
    required bool initialValue,
    required void Function(bool) setStateValue,
    required String dbKey,
    bool showDivider = true,
    bool showInfo = false,
    String infoContent = '',
  }) {
    return BoolSettingSwitch(
      title: title,
      initialValue: initialValue,
      showDivider: showDivider,
      showInfo: showInfo,
      infoContent: infoContent,
      onChanged: (bool value) async {
        setState(() => setStateValue(value));
        await DB.instance.setSettingByTitle(
          dbKey,
          value.toString(),
          widget.projectId.toString(),
        );
        widget.refreshSettings();
      },
    );
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
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

      await _saveProjectSetting(
          'daily_notification_time', dailyNotificationTime);

      await _scheduleDailyNotification();
    }
  }

  Future<void> _scheduleDailyNotification() async {
    NotificationUtil.scheduleDailyNotification(
      widget.projectId,
      dailyNotificationTime,
    );
  }

  List<_Section> get _visibleSections {
    final video = widget.onlyShowVideoSettings;
    final notif = widget.onlyShowNotificationSettings;
    return [
      if (!video && !notif)
        _Section(
          'Projects',
          Icons.folder_outlined,
          _buildProjectSettings,
          () => _projectSettingsFuture,
        ),
      if (!notif)
        _Section(
          'Stabilization',
          Icons.center_focus_strong_outlined,
          () => Column(
            children: [
              _buildStabilizationModeDropdown(),
              _buildEyeScaleButton()
            ],
          ),
          () => _settingsFuture,
        ),
      if (!notif)
        _Section(
          'Video',
          Icons.movie_outlined,
          _buildVideoSettings,
          () => _videoSettingsFuture,
        ),
      if (!notif)
        _Section(
          'Background Colour',
          Icons.format_color_fill_outlined,
          _buildBackgroundColourSettings,
          () => _videoSettingsFuture,
        ),
      if (!video && !notif)
        _Section(
          'Camera',
          Icons.camera_alt_outlined,
          _buildCameraSettings,
          () => _settingsFuture,
        ),
      if (!video && isMobile)
        _Section(
          'Notifications',
          Icons.notifications_outlined,
          _buildNotificationSettings,
          () => _notificationInitialization,
        ),
      if (!video && !notif)
        _Section(
          'Gallery',
          Icons.grid_view_outlined,
          () => Column(
            children: [
              _buildGalleryGridModeDropdown(),
              if (_galleryGridMode == 'manual')
                _buildGridColumnsControl(isDesktop),
            ],
          ),
          () => _gridCountFuture,
        ),
      if (!notif)
        _Section(
          'Date Stamp',
          Icons.calendar_today_outlined,
          _buildDateStampSettings,
          () => _dateStampSettingsFuture,
        ),
      if (!notif)
        _Section(
          'Watermark',
          Icons.branding_watermark_outlined,
          _buildWatermarkSettings,
          () => _watermarkSettingsFuture,
        ),
      if (!video && !notif)
        _Section(
          'Appearance',
          Icons.palette_outlined,
          _buildAppearanceSettings,
          () => _defaultSettingsFuture,
        ),
      if (!video && !notif)
        _Section(
          'Advanced',
          Icons.tune_outlined,
          _buildAdvancedSettings,
          () => _settingsFuture,
        ),
      if (!video && !notif)
        _Section(
          'Danger Zone',
          Icons.warning_amber_rounded,
          () => const SizedBox.shrink(),
          () => _defaultSettingsFuture,
          isDangerZone: true,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    final sections = _visibleSections;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.settingsBackground,
        borderRadius: const BorderRadius.only(
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
                  for (final section in sections)
                    if (section.isDangerZone)
                      _buildDangerZoneSection()
                    else
                      _buildSettingsSection(
                        section.title,
                        section.icon,
                        section.builder,
                        section.futureGetter(),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final sections = _visibleSections;
    final safeIndex = _selectedSectionIndex.clamp(0, sections.length - 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          minHeight: 400,
          minWidth: 600,
        ),
        decoration: BoxDecoration(
          color: AppColors.settingsBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.settingsCardBorder, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              _buildDesktopHeader(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSidebar(sections, safeIndex),
                    VerticalDivider(width: 1, color: AppColors.settingsDivider),
                    Expanded(child: _buildContentPane(sections, safeIndex)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.settingsDivider, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: AppTypography.display,
              fontWeight: FontWeight.w700,
              color: AppColors.settingsTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<_Section> sections, int selectedIndex) {
    return SizedBox(
      width: 220,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final section = sections[index];
          final isSelected = index == selectedIndex;
          final isDanger = section.isDangerZone;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDanger)
                Divider(
                  height: 1,
                  color: AppColors.settingsDivider,
                  indent: 16,
                  endIndent: 16,
                ),
              if (isDanger) const SizedBox(height: 8),
              _buildSidebarItem(section, isSelected, isDanger, () {
                FocusScope.of(context).unfocus();
                setState(() => _selectedSectionIndex = index);
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebarItem(
    _Section section,
    bool isSelected,
    bool isDanger,
    VoidCallback onTap,
  ) {
    final accentColor = isDanger ? AppColors.danger : AppColors.settingsAccent;
    final labelColor = isSelected
        ? accentColor
        : isDanger
            ? AppColors.danger.withValues(alpha: 0.7)
            : AppColors.settingsTextSecondary;
    final bgColor =
        isSelected ? accentColor.withValues(alpha: 0.12) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.settingsTextPrimary.withValues(alpha: 0.05),
          splashColor: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    section.icon,
                    size: 18,
                    color: labelColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.title,
                      style: TextStyle(
                        fontSize: AppTypography.md,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentPane(List<_Section> sections, int selectedIndex) {
    final section = sections[selectedIndex];

    if (section.isDangerZone) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Danger Zone',
              icon: Icons.warning_amber_rounded,
              color: _dangerRed.withValues(alpha: 0.8),
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
                child: _buildDangerZoneContent(),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: section.title, icon: section.icon),
          Container(
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            child: FutureBuilder<void>(
              future: section.futureGetter(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
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
                        color: AppColors.danger,
                        fontSize: AppTypography.md,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: section.builder(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delete this project',
          style: TextStyle(
            fontSize: AppTypography.lg,
            fontWeight: FontWeight.w600,
            color: AppColors.settingsTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Once deleted, there is no going back. This will permanently delete all photos and videos associated with this project.',
          style: TextStyle(
            fontSize: AppTypography.md,
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
            child: Center(
              child: Text(
                'Delete this project',
                style: TextStyle(
                  color: _dangerRed,
                  fontSize: AppTypography.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: BoxDecoration(
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
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: AppTypography.display,
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
          color: AppColors.textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          widget.onlyShowNotificationSettings ? Icons.check : Icons.close,
          color: AppColors.textPrimary.withValues(alpha: 0.7),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSettingsSection(
    String title,
    IconData icon,
    Widget Function() buildSettings,
    Future<dynamic> sectionFuture,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, icon: icon),
          Container(
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            ),
            child: FutureBuilder<void>(
              future: sectionFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
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
                        color: AppColors.danger,
                        fontSize: AppTypography.md,
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

  static Color get _dangerRed => AppColors.danger;

  Widget _buildDangerZoneSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Danger Zone',
            icon: Icons.warning_amber_rounded,
            color: _dangerRed.withValues(alpha: 0.8),
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
              child: _buildDangerZoneContent(),
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

  Widget _buildAppearanceSettings() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return Column(
      children: [
        SettingListTile(
          title: 'Theme',
          contentWidget: CustomDropdownButton<String>(
            value: themeProvider.themeMode,
            items: const [
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'light', child: Text('Light')),
              DropdownMenuItem(value: 'dark', child: Text('Dark')),
            ],
            onChanged: (String? newValue) async {
              if (newValue != null) {
                themeProvider.themeMode = newValue;
                await DB.instance.setSettingByTitle(
                  'theme',
                  newValue,
                  'global',
                );
              }
            },
          ),
          showDivider: false,
          showInfo: false,
          infoContent: '',
        ),
      ],
    );
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
        const SizedBox(height: 8),
        _buildLinkedSourceSettings(),
      ],
    );
  }

  Widget _buildLinkedSourceSettings() {
    final supportsLinkedSource = LinkedSourceUtils.supportsDesktopLinkedFolders;

    return Column(
      children: [
        BoolSettingSwitch(
          title: 'Sync source photos from folder',
          initialValue: _linkedSourceEnabled,
          showInfo: true,
          showDivider: _linkedSourceEnabled,
          infoContent:
              'When enabled, the project can watch a desktop folder for new source photos and prefer those originals for export/save.',
          onChanged: (bool value) async {
            if (!supportsLinkedSource) {
              setState(() => _linkedSourceEnabled = false);
              return;
            }

            if (!value) {
              await LinkedSourceUtils.disableLinkedSource(widget.projectId);
              setStateIfMounted(() {
                _linkedSourceEnabled = false;
                _linkedSourceDisplayPath = '';
              });
              await widget.refreshSettings();
              return;
            }

            final selectedPath = await _pickLinkedSourceFolder();
            if (selectedPath == null) {
              if (!mounted) return;
              setState(() => _linkedSourceEnabled = false);
              return;
            }

            await LinkedSourceUtils.persistDesktopFolderSelection(
              widget.projectId,
              selectedPath,
            );
            setStateIfMounted(() {
              _linkedSourceEnabled = true;
              _linkedSourceDisplayPath = selectedPath;
            });
            await widget.refreshSettings();
          },
        ),
        if (_linkedSourceEnabled) ...[
          SettingListTile(
            title: 'Linked folder',
            infoContent:
                'This folder is treated as the external source-photo home for this project.',
            showInfo: true,
            showDivider: true,
            contentWidget: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                _linkedSourceDisplayPath.isEmpty
                    ? 'Not set'
                    : _linkedSourceDisplayPath,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.sm,
                ),
              ),
            ),
          ),
          SettingListTile(
            title: 'Folder actions',
            infoContent: '',
            showInfo: false,
            showDivider: false,
            contentWidget: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () async {
                    final selectedPath = await _pickLinkedSourceFolder();
                    if (selectedPath == null) return;
                    await LinkedSourceUtils.persistDesktopFolderSelection(
                      widget.projectId,
                      selectedPath,
                    );
                    setStateIfMounted(() {
                      _linkedSourceEnabled = true;
                      _linkedSourceDisplayPath = selectedPath;
                    });
                    await widget.refreshSettings();
                  },
                  child: const Text('Change'),
                ),
                TextButton(
                  onPressed: () async {
                    await LinkedSourceUtils.disableLinkedSource(
                        widget.projectId);
                    setStateIfMounted(() {
                      _linkedSourceEnabled = false;
                      _linkedSourceDisplayPath = '';
                    });
                    await widget.refreshSettings();
                  },
                  child: const Text('Disable'),
                ),
              ],
            ),
          ),
        ] else if (!supportsLinkedSource) ...[
          SettingListTile(
            title: 'Linked folder',
            infoContent: '',
            showInfo: false,
            showDivider: false,
            contentWidget: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                'Desktop only',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontSize: AppTypography.sm,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<String?> _pickLinkedSourceFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    if (selectedPath == null || selectedPath.trim().isEmpty) return null;

    final projectDirPath = await DirUtils.getProjectDirPath(widget.projectId);
    final validationError = LinkedSourceUtils.validateLinkedFolderPath(
      projectId: widget.projectId,
      selectedPath: selectedPath,
      projectDirPath: projectDirPath,
    );

    if (validationError != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return null;
    }

    return selectedPath;
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
            await _saveGlobalSetting('enable_notifications', value.toString());
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
                    style: TextStyle(
                      fontSize: AppTypography.md,
                      color: AppColors.settingsTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
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
              DropdownMenuItem<String>(value: 'auto', child: Text('Auto')),
              DropdownMenuItem<String>(value: 'manual', child: Text('Manual')),
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
              await _saveProjectSetting('gridAxisCount', value.toString());
            }
          },
        );
      },
    );
  }

  Widget _buildAdvancedSettings() {
    return Column(
      children: [
        BoolSettingSwitch(
          title: 'RAW photo support',
          initialValue: _losslessStorage,
          showDivider: false,
          showInfo: true,
          infoContent:
              'When enabled, stabilized frames preserve source bit depth (up to 16-bit). '
              'This only benefits RAW/DNG imports — standard JPEG/HEIC photos are always 8-bit regardless.\n\n'
              'Lossless 16-bit frames are roughly double the file size of 8-bit frames.',
          onChanged: (bool value) async {
            final bool shouldProceed = await Utils.showConfirmChangeDialog(
              context,
              "RAW photo support",
            );

            if (shouldProceed && mounted) {
              setState(() => _losslessStorage = value);

              await widget.cancelStabCallback();
              await SettingsUtil.setLosslessStorage(
                widget.projectId.toString(),
                value,
              );
              await widget.refreshSettings();

              await resetStabStatusAndRestartStabilization();
            } else if (mounted) {
              setState(() {}); // Revert switch visual state
            }
          },
        ),
      ],
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
        _buildCodecDropdown(),
        _buildFramerateDropdown(framerate ?? 30),
        _buildAutoCompileVideoSwitch(),
      ],
    );
  }

  /// Whether the video output is transparent (determines codec options).
  bool get _videoKeepsTransparency =>
      _isTransparentBackground && _videoBackground.keepTransparent;

  /// Whether the current resolution exceeds H.264 VideoToolbox limits on macOS/iOS.
  /// h264_videotoolbox cannot encode beyond ~4096px on any dimension.
  bool get _resolutionExceedsH264Limit {
    if (!Platform.isMacOS && !Platform.isIOS) return false;
    if (resolution == '8K') return true;
    // Check custom resolutions (e.g., "7680x4320")
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      return w > 4096 || h > 4096;
    }
    return false;
  }

  Widget _buildCodecDropdown() {
    final bool isLockedTransparent = _videoKeepsTransparency;
    final bool isLockedResolution =
        !isLockedTransparent && _resolutionExceedsH264Limit;

    VideoCodec effectiveCodec;
    List<VideoCodec> availableCodecs;
    Set<VideoCodec>? disabledCodecs;

    if (isLockedTransparent) {
      effectiveCodec = VideoCodec.defaultCodec(isTransparentVideo: true);
      availableCodecs = VideoCodec.availableCodecs(isTransparentVideo: true);
    } else if (isLockedResolution) {
      // 8K on macOS/iOS: H.264 disabled, default to HEVC if H.264 was selected
      availableCodecs = VideoCodec.availableCodecs(isTransparentVideo: false);
      disabledCodecs = {VideoCodec.h264};
      effectiveCodec =
          _videoCodec == VideoCodec.h264 ? VideoCodec.hevc : _videoCodec;
    } else {
      effectiveCodec = _videoCodec;
      availableCodecs = VideoCodec.availableCodecs(isTransparentVideo: false);
    }

    String infoText;
    if (isLockedTransparent) {
      infoText =
          'Codec is locked to ${effectiveCodec.displayName} because transparent video output requires an alpha-capable codec.\n\n'
          'To unlock all codecs, set "Video background" to solid colour or blurred below.';
    } else if (isLockedResolution) {
      final codecDescriptions = availableCodecs
          .where((c) => c != VideoCodec.h264)
          .map((c) => '${c.displayName}: ${c.description}')
          .join('\n\n');
      infoText =
          'H.264 is unavailable at 8K resolution on macOS (hardware encoder limit).\n\n'
          '$codecDescriptions';
    } else {
      final codecDescriptions = availableCodecs
          .map((c) => '${c.displayName}: ${c.description}')
          .join('\n\n');
      infoText = 'Choose the video encoding format.\n\n$codecDescriptions';
    }

    return SettingListTile(
      title: 'Codec',
      showDivider: true,
      contentWidget: isLockedTransparent
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.settingsTextTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  effectiveCodec.displayName,
                  style: TextStyle(
                    color: AppColors.settingsTextTertiary,
                    fontSize: AppTypography.md,
                  ),
                ),
              ],
            )
          : CustomDropdownButton<VideoCodec>(
              value: effectiveCodec,
              disabledValues: disabledCodecs,
              items: availableCodecs
                  .map(
                    (codec) => DropdownMenuItem<VideoCodec>(
                      value: codec,
                      child: Text(codec.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (VideoCodec? newCodec) async {
                if (newCodec == null || newCodec == _videoCodec) return;

                final shouldProceed =
                    await ConfirmActionDialog.showRecompileVideoSetting(
                  context,
                  'video codec',
                );

                if (shouldProceed && mounted) {
                  setState(() => _videoCodec = newCodec);
                  await SettingsUtil.saveVideoCodec(
                    widget.projectId.toString(),
                    newCodec,
                  );
                  await widget.recompileVideoCallback();
                }
              },
            ),
      infoContent: infoText,
      showInfo: true,
    );
  }

  Future<Color?> _showColorPickerHelper({
    required String title,
    required Color initialColor,
  }) async {
    Color pickerColor = initialColor;
    Color? selectedColor;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: AppColors.settingsAccent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: AppTypography.xl,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (Color color) {
                pickerColor = color;
              },
              enableAlpha: false,
              hexInputBar: true,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.7,
              displayThumbColor: true,
              portraitOnly: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                selectedColor = pickerColor;
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.settingsAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Select',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppTypography.md,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    return selectedColor;
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
        style: TextStyle(
          color: AppColors.settingsTextPrimary,
          fontSize: AppTypography.md,
        ),
      ),
      infoContent:
          'Final video dimensions. Derived from your resolution, orientation, and aspect ratio.\n\n'
          'To specify exact dimensions manually, choose "Custom" under the Resolution setting.',
      showInfo: true,
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
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.settingsTextSecondary,
            ),
          ),
        ),
        // Stabilized thumbnails toggle
        _buildSimpleBoolSetting(
          title: 'Show on stabilized',
          initialValue: _galleryDateLabelsEnabled,
          setStateValue: (v) => _galleryDateLabelsEnabled = v,
          dbKey: 'gallery_date_labels_enabled',
        ),
        // Raw thumbnails toggle
        _buildSimpleBoolSetting(
          title: 'Show on raw',
          initialValue: _galleryRawDateLabelsEnabled,
          setStateValue: (v) => _galleryRawDateLabelsEnabled = v,
          dbKey: 'gallery_raw_date_labels_enabled',
        ),
        // Gallery date format dropdown with Custom option
        ..._buildDateFormatSection(
          isCustomFormat: _isGalleryCustomFormat,
          currentFormat: _galleryDateFormat,
          customSentinel: DateStampUtils.galleryFormatCustom,
          presetItems: [
            DropdownMenuItem<String>(
              value: DateStampUtils.galleryFormatMMYY,
              child: Text(DateStampUtils.getGalleryFormatExample(
                  DateStampUtils.galleryFormatMMYY)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.galleryFormatMMMDD,
              child: Text(DateStampUtils.getGalleryFormatExample(
                  DateStampUtils.galleryFormatMMMDD)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.galleryFormatMMMDDYY,
              child: Text(DateStampUtils.getGalleryFormatExample(
                  DateStampUtils.galleryFormatMMMDDYY)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.galleryFormatDDMMM,
              child: Text(DateStampUtils.getGalleryFormatExample(
                  DateStampUtils.galleryFormatDDMMM)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.galleryFormatMMMYYYY,
              child: Text(DateStampUtils.getGalleryFormatExample(
                  DateStampUtils.galleryFormatMMMYYYY)),
            ),
          ],
          customController: _galleryCustomFormatController,
          customError: _galleryCustomFormatError,
          maxLength: DateStampUtils.galleryFormatMaxLength,
          validateFn: DateStampUtils.validateGalleryFormat,
          helpText: DateStampUtils.galleryFormatHelpText,
          enabled: galleryEnabled,
          onSwitchToCustom: () {
            _isGalleryCustomFormat = true;
            _galleryCustomFormatController.text = _galleryDateFormat;
          },
          onPresetSelected: (value) async {
            setState(() {
              _isGalleryCustomFormat = false;
              _galleryDateFormat = value;
              _galleryCustomFormatError = null;
            });
            await _saveProjectSetting('gallery_date_format', value);
          },
          onCustomChanged: (value) {
            final error = DateStampUtils.validateGalleryFormat(value);
            setState(() => _galleryCustomFormatError = error);
          },
          onCustomSubmit: (value) async {
            final error = DateStampUtils.validateGalleryFormat(value);
            if (error == null) {
              setState(() {
                _galleryDateFormat = value;
                _galleryCustomFormatError = null;
              });
              await _saveProjectSetting('gallery_date_format', value);
            } else {
              setState(() => _galleryCustomFormatError = error);
            }
          },
        ),
        // Gallery font dropdown (includes custom fonts and import option)
        _buildFontDropdownTile(
          fontValue: _galleryDateStampFont,
          enabled: galleryEnabled,
          onChanged: _handleGalleryFontSelection,
          includeSameAsGallery: false,
          showInfo: true,
          infoContent:
              'Select "Custom (TTF/OTF)" to import your own font file.',
        ),
        // Gallery font size dropdown
        SettingListTile(
          title: 'Font size',
          showDivider: _customFonts.isEmpty,
          contentWidget: CustomDropdownButton<int>(
            value: _galleryDateStampSize,
            items: List.generate(6, (index) {
              final size = index + 1;
              final px = DateStampUtils.gallerySizePx[index].round();
              return DropdownMenuItem<int>(value: size, child: Text('${px}px'));
            }),
            onChanged: galleryEnabled
                ? (int? value) async {
                    if (value == null) return;
                    // Check cascade BEFORE persisting
                    final affectsExport = _exportDateStampEnabled &&
                        _exportDateStampSize ==
                            DateStampUtils.sizeSameAsGallery;
                    if (affectsExport) {
                      final shouldProceed =
                          await ConfirmActionDialog.showRecompileVideo(
                        context,
                        'font size',
                      );
                      if (!shouldProceed) return;
                    }

                    setState(() => _galleryDateStampSize = value);
                    await DB.instance.setSettingByTitle(
                      'gallery_date_stamp_size',
                      value.toString(),
                      widget.projectId.toString(),
                    );
                    await widget.refreshSettings();

                    if (affectsExport) {
                      await widget.recompileVideoCallback();
                    }
                  }
                : null,
          ),
          infoContent: '',
          showInfo: false,
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
                style: const TextStyle(fontSize: AppTypography.sm),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.settingsAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),

        // Export section header
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            'Export & Video',
            style: TextStyle(
              fontSize: AppTypography.sm,
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
            await _confirmAndSaveVideoSetting(
              confirmLabel: value
                  ? 'settings (enabling date stamps)'
                  : 'settings (disabling date stamps)',
              updateState: () => _exportDateStampEnabled = value,
              dbKey: 'export_date_stamp_enabled',
              dbValue: value.toString(),
            );
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
                      await _confirmAndSaveVideoSetting(
                        confirmLabel: 'position',
                        updateState: () => _exportDateStampPosition = value,
                        dbKey: 'export_date_stamp_position',
                        dbValue: value,
                      );
                    }
                  }
                : null,
          ),
          infoContent:
              'Corner of the image or video frame where the date stamp is placed.',
          showInfo: true,
          disabled: !_exportDateStampEnabled,
        ),
        // Export format dropdown with Custom option
        ..._buildDateFormatSection(
          isCustomFormat: _isExportCustomFormat,
          currentFormat: _exportDateStampFormat,
          customSentinel: DateStampUtils.exportFormatCustom,
          presetItems: [
            DropdownMenuItem<String>(
              value: DateStampUtils.exportFormatLong,
              child: Text(DateStampUtils.getExportFormatExample(
                  DateStampUtils.exportFormatLong)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.exportFormatISO,
              child: Text(DateStampUtils.getExportFormatExample(
                  DateStampUtils.exportFormatISO)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.exportFormatUS,
              child: Text(DateStampUtils.getExportFormatExample(
                  DateStampUtils.exportFormatUS)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.exportFormatEU,
              child: Text(DateStampUtils.getExportFormatExample(
                  DateStampUtils.exportFormatEU)),
            ),
            DropdownMenuItem<String>(
              value: DateStampUtils.exportFormatShort,
              child: Text(DateStampUtils.getExportFormatExample(
                  DateStampUtils.exportFormatShort)),
            ),
          ],
          customController: _exportCustomFormatController,
          customError: _exportCustomFormatError,
          maxLength: DateStampUtils.exportFormatMaxLength,
          validateFn: DateStampUtils.validateExportFormat,
          helpText: DateStampUtils.exportFormatHelpText,
          enabled: _exportDateStampEnabled,
          onSwitchToCustom: () {
            _isExportCustomFormat = true;
            _exportCustomFormatController.text = _exportDateStampFormat;
          },
          onPresetSelected: (value) async {
            await _confirmAndSaveVideoSetting(
              confirmLabel: 'format',
              updateState: () {
                _isExportCustomFormat = false;
                _exportDateStampFormat = value;
                _exportCustomFormatError = null;
              },
              dbKey: 'export_date_stamp_format',
              dbValue: value,
            );
          },
          onCustomChanged: (value) {
            final error = DateStampUtils.validateExportFormat(value);
            setState(() => _exportCustomFormatError = error);
          },
          onCustomSubmit: (value) async {
            final error = DateStampUtils.validateExportFormat(value);
            if (error == null) {
              await _confirmAndSaveVideoSetting(
                confirmLabel: 'format',
                updateState: () {
                  _exportDateStampFormat = value;
                  _exportCustomFormatError = null;
                },
                dbKey: 'export_date_stamp_format',
                dbValue: value,
              );
            } else {
              setState(() => _exportCustomFormatError = error);
            }
          },
        ),
        // Export font dropdown (includes custom fonts and import option)
        _buildFontDropdownTile(
          fontValue: _exportDateStampFont,
          enabled: _exportDateStampEnabled,
          onChanged: _handleExportFontSelection,
          includeSameAsGallery: true,
          showInfo: false,
          infoContent: '',
        ),
        // Export size dropdown
        SettingListTile(
          title: 'Size',
          showDivider: true,
          contentWidget: CustomDropdownButton<int>(
            value: _exportDateStampSize,
            items: [
              const DropdownMenuItem<int>(
                value: DateStampUtils.sizeSameAsGallery,
                child: Text('Same as thumbnail'),
              ),
              ...List.generate(6, (index) {
                final size = index + 1;
                final px = DateStampUtils.exportSizeApproxPx[index];
                return DropdownMenuItem<int>(
                  value: size,
                  child: Text('${px}px'),
                );
              }),
            ],
            onChanged: _exportDateStampEnabled
                ? (int? value) async {
                    if (value != null) {
                      await _confirmAndSaveVideoSetting(
                        confirmLabel: 'size',
                        updateState: () => _exportDateStampSize = value,
                        dbKey: 'export_date_stamp_size',
                        dbValue: value.toString(),
                      );
                    }
                  }
                : null,
          ),
          infoContent:
              'Font size of the date stamp, as a percentage of image height. Approximate pixel values shown at 1080p.',
          showInfo: true,
          disabled: !_exportDateStampEnabled,
        ),
        // Export margin dropdown with Custom option
        ..._buildMarginSection(),
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
                      await _confirmAndSaveVideoSetting(
                        confirmLabel: 'opacity',
                        updateState: () => _exportDateStampOpacity = value,
                        dbKey: 'export_date_stamp_opacity',
                        dbValue: value.toString(),
                      );
                    }
                  }
                : null,
          ),
          infoContent:
              'Transparency of the date stamp overlay. 100% is fully opaque, 30% is mostly transparent.',
          showInfo: true,
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
              fontFamily: 'JetBrainsMono',
              fontSize: AppTypography.md,
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
                  color:
                      hasError ? AppColors.danger : AppColors.settingsDivider,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color:
                      hasError ? AppColors.danger : AppColors.settingsDivider,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? AppColors.danger : AppColors.settingsAccent,
                  width: 1.5,
                ),
              ),
              counterText: '',
              hintText: 'e.g. MMM d, yyyy',
              hintStyle: TextStyle(
                color: AppColors.settingsTextSecondary.withValues(alpha: 0.5),
                fontFamily: 'JetBrainsMono',
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
                    fontSize: AppTypography.sm,
                    color: AppColors.settingsTextSecondary,
                  ),
                ),
              ),
              // Character count
              Text(
                '${controller.text.length}/$maxLength',
                style: TextStyle(
                  fontSize: AppTypography.xs,
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
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  color: AppColors.danger,
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
                backgroundColor: AppColors.settingsAccent.withValues(
                  alpha: 0.1,
                ),
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

  /// Builds the margin dropdown plus conditional custom H/V inputs.
  List<Widget> _buildMarginSection() {
    return [
      SettingListTile(
        title: 'Margin',
        showDivider: !_isCustomMargin,
        contentWidget: CustomDropdownButton<int>(
          value: _isCustomMargin
              ? DateStampUtils.marginCustom
              : _exportDateStampMargin,
          items: [
            ...List.generate(6, (index) {
              final margin = index + 1;
              final px = DateStampUtils.exportMarginApproxPx[index];
              return DropdownMenuItem<int>(
                value: margin,
                child: Text('$margin% (~${px}px)'),
              );
            }),
            DropdownMenuItem<int>(
              value: DateStampUtils.marginCustom,
              child: const Text('Custom...'),
            ),
          ],
          onChanged: _exportDateStampEnabled
              ? (int? value) async {
                  if (value == DateStampUtils.marginCustom) {
                    setState(() {
                      _isCustomMargin = true;
                      _customMarginHController.text = _customMarginH.toString();
                      _customMarginVController.text = _customMarginV.toString();
                    });
                    await _confirmAndSaveVideoSetting(
                      confirmLabel: 'margin',
                      updateState: () =>
                          _exportDateStampMargin = DateStampUtils.marginCustom,
                      dbKey: 'export_date_stamp_margin',
                      dbValue: DateStampUtils.marginCustom.toString(),
                    );
                  } else if (value != null) {
                    await _confirmAndSaveVideoSetting(
                      confirmLabel: 'margin',
                      updateState: () {
                        _isCustomMargin = false;
                        _exportDateStampMargin = value;
                        _customMarginHError = null;
                        _customMarginVError = null;
                      },
                      dbKey: 'export_date_stamp_margin',
                      dbValue: value.toString(),
                    );
                  }
                }
              : null,
        ),
        infoContent:
            'Distance from the image edge to the date stamp, as a percentage of image dimensions. '
            'Select "Custom" to set horizontal and vertical margins independently.',
        showInfo: true,
        disabled: !_exportDateStampEnabled,
      ),
      if (_isCustomMargin) _buildCustomMarginInputs(),
    ];
  }

  /// Builds the custom margin H/V input fields shown when "Custom" is selected.
  Widget _buildCustomMarginInputs() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMarginTextField(
            label: 'Horizontal %',
            controller: _customMarginHController,
            error: _customMarginHError,
            enabled: _exportDateStampEnabled,
            onChanged: (value) {
              final error = DateStampUtils.validateCustomMargin(value);
              setState(() => _customMarginHError = error);
            },
          ),
          const SizedBox(height: 8),
          _buildMarginTextField(
            label: 'Vertical %',
            controller: _customMarginVController,
            error: _customMarginVError,
            enabled: _exportDateStampEnabled,
            onChanged: (value) {
              final error = DateStampUtils.validateCustomMargin(value);
              setState(() => _customMarginVError = error);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _exportDateStampEnabled &&
                      _customMarginHError == null &&
                      _customMarginVError == null
                  ? () async {
                      final h = double.tryParse(_customMarginHController.text);
                      final v = double.tryParse(_customMarginVController.text);
                      if (h == null || v == null) return;
                      await _confirmAndSaveVideoSetting(
                        confirmLabel: 'margin',
                        updateState: () {
                          _customMarginH = h;
                          _customMarginV = v;
                        },
                        dbKey: 'export_date_stamp_margin_h',
                        dbValue: h.toString(),
                      );
                      await DB.instance.setSettingByTitle(
                        'export_date_stamp_margin_v',
                        v.toString(),
                        widget.projectId.toString(),
                      );
                    }
                  : null,
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarginTextField({
    required String label,
    required TextEditingController controller,
    required String? error,
    required bool enabled,
    required void Function(String) onChanged,
  }) {
    final hasError = error != null;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.md,
              color: enabled
                  ? AppColors.settingsTextPrimary
                  : AppColors.settingsTextSecondary,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: AppTypography.md,
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
                  color:
                      hasError ? AppColors.danger : AppColors.settingsDivider,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color:
                      hasError ? AppColors.danger : AppColors.settingsDivider,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? AppColors.danger : AppColors.settingsAccent,
                  width: 1.5,
                ),
              ),
              counterText: '',
              errorText: error,
              suffixText: '%',
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Builds a date format dropdown row plus (conditionally) a custom-format
  /// text input below it.  Returns a list so the caller can spread it into a
  /// Column with `..._buildDateFormatSection(...)`.
  ///
  /// [isCustomFormat]   - whether the custom text-field is currently active.
  /// [currentFormat]    - the active preset format string.
  /// [customSentinel]   - the sentinel value that triggers custom mode.
  /// [presetItems]      - dropdown items for all presets (excluding Custom...).
  /// [customController] - controller for the custom text field.
  /// [customError]      - current validation error (null = valid).
  /// [maxLength]        - max chars for the custom field.
  /// [validateFn]       - validates the custom string; returns null if valid.
  /// [helpText]         - info-icon content for the SettingListTile.
  /// [enabled]          - whether the dropdown/field is interactive.
  /// [onSwitchToCustom] - called (inside setState) when user picks Custom...
  /// [onPresetSelected] - called when user picks a real preset value.
  /// [onCustomChanged]  - called on every keystroke in the custom field.
  /// [onCustomSubmit]   - called when the user taps Apply or submits the field.
  List<Widget> _buildDateFormatSection({
    required bool isCustomFormat,
    required String currentFormat,
    required String customSentinel,
    required List<DropdownMenuItem<String>> presetItems,
    required TextEditingController customController,
    required String? customError,
    required int maxLength,
    required String? Function(String) validateFn,
    required String helpText,
    required bool enabled,
    required void Function() onSwitchToCustom,
    required Future<void> Function(String) onPresetSelected,
    required void Function(String) onCustomChanged,
    required Future<void> Function(String) onCustomSubmit,
  }) {
    return [
      SettingListTile(
        title: 'Format',
        showDivider: !isCustomFormat,
        contentWidget: CustomDropdownButton<String>(
          value: isCustomFormat ? customSentinel : currentFormat,
          items: [
            ...presetItems,
            DropdownMenuItem<String>(
              value: customSentinel,
              child: const Text('Custom...'),
            ),
          ],
          onChanged: enabled
              ? (String? value) async {
                  if (value == customSentinel) {
                    setState(onSwitchToCustom);
                  } else if (value != null) {
                    await onPresetSelected(value);
                  }
                }
              : null,
        ),
        infoContent: helpText,
        showInfo: true,
        disabled: !enabled,
      ),
      if (isCustomFormat)
        _buildCustomFormatInput(
          controller: customController,
          error: customError,
          maxLength: maxLength,
          enabled: enabled,
          onChanged: onCustomChanged,
          onSubmit: onCustomSubmit,
        ),
    ];
  }

  Widget _buildLoading() {
    return Center(
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
        style: TextStyle(color: AppColors.danger),
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
        if (isMobile) _buildSaveToCameraRollSwitch(saveToCameraRoll),
        BoolSettingSwitch(
          title: 'Mirror front camera',
          initialValue: cameraMirror,
          showInfo: true,
          infoContent:
              'Flips the camera preview and captured photos horizontally.',
          onChanged: (bool value) async {
            setState(() {
              cameraMirror = value;
            });

            LogService.instance.log(
              "Setting camera_mirror to ${value.toString()}",
            );

            await _saveProjectSetting('camera_mirror', value.toString());
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
            await _saveProjectSetting('grid_mode_index', newValue.toString());
          }
        },
      ),
      infoContent:
          'Alignment overlay for camera preview only. Ghost = guide photo, Grid = guide lines.',
      showInfo: true,
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
              await _saveProjectSetting(
                  'project_orientation', value.toLowerCase());

              await resetStabStatusAndRestartStabilization();
            }
          }
        },
      ),
      infoContent: 'Portrait = vertical video. Landscape = horizontal video.',
      showInfo: true,
    );
  }

  Widget _buildFramerateDropdown(int framerate) {
    return DropdownWithCustomTextField(
      projectId: widget.projectId,
      title: 'Framerate (FPS)',
      initialValue: framerate,
      showDivider: true,
      showInfo: true,
      infoContent:
          'Frames per second in output video. Higher = smoother playback, larger file size.',
      onChanged: (newValue) async {
        await _saveProjectSetting('framerate', newValue.toString());
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
    Utils.clearFlutterImageCache();
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
            items: const [
              DropdownMenuItem<String>(value: "1080p", child: Text("1080p")),
              DropdownMenuItem<String>(value: "4K", child: Text("4K")),
              DropdownMenuItem<String>(value: "8K", child: Text("8K")),
              DropdownMenuItem<String>(value: "Custom", child: Text("Custom")),
            ],
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
                  await _saveProjectSetting('video_resolution', value);

                  await resetStabStatusAndRestartStabilization();
                }
              }
            },
          ),
          infoContent:
              'Output resolution. Higher values increase quality and file size.',
          showInfo: true,
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
                child: _buildDimensionField(
                  controller: _customWidthController,
                  hint: '1920',
                  label: 'width',
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
                      fontSize: AppTypography.xxl,
                    ),
                  ),
                ),
              ),
              // Height field
              Expanded(
                child: _buildDimensionField(
                  controller: _customHeightController,
                  hint: '1080',
                  label: 'height',
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
                    ? AppColors.textPrimary
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
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: AppTypography.sm,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFontDropdownTile({
    required String fontValue,
    required bool enabled,
    required Future<void> Function(String?) onChanged,
    bool includeSameAsGallery = false,
    bool showInfo = false,
    String infoContent = '',
  }) {
    return SettingListTile(
      title: 'Font',
      showDivider: true,
      contentWidget: _isLoadingCustomFonts
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : CustomDropdownButton<String>(
              value: fontValue,
              items: _buildFontDropdownItems(
                includeSameAsGallery: includeSameAsGallery,
              ),
              onChanged: enabled ? onChanged : null,
            ),
      infoContent: infoContent,
      showInfo: showInfo,
      disabled: !enabled,
    );
  }

  Widget _buildDimensionField({
    required TextEditingController controller,
    required String hint,
    required String label,
  }) {
    return Column(
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            color: AppColors.settingsTextPrimary,
            fontSize: AppTypography.lg,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.settingsTextTertiary,
              fontSize: AppTypography.lg,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.settingsTextTertiary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.settingsTextTertiary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.settingsAccent),
            ),
          ),
          onSubmitted: (_) => _applyCustomResolution(),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.settingsTextTertiary,
            fontSize: AppTypography.xs,
          ),
        ),
      ],
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
      await _saveProjectSetting('video_resolution', newResolution);

      await resetStabStatusAndRestartStabilization();
    }
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
      infoContent:
          'Output aspect ratio. 16:9 is widescreen, 4:3 is standard format.',
      showInfo: true,
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
          child: Text(
            'Configure',
            style: TextStyle(
              color: AppColors.settingsAccent,
              fontSize: AppTypography.md,
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

  bool get _isTransparentBackground =>
      SettingsUtil.isTransparent(_backgroundColor);

  String get _backgroundMode {
    if (!_isTransparentBackground) return 'solid';
    if (_videoBackground.isBlurred) return 'blurred';
    return 'transparent';
  }

  Widget _buildBackgroundColourSettings() {
    final mode = _backgroundMode;
    return Column(
      children: [
        SettingListTile(
          title: 'Background mode',
          showDivider: mode == 'solid',
          showInfo: true,
          infoContent:
              'Solid colour: Fills areas not covered by the stabilized image with a solid colour.\n\n'
              'Transparent: Preserves the alpha channel on photos and video. '
              'Locks video codec to ProRes 4444 (.mov) on Apple or VP9 (.webm) on other platforms. '
              'Transparent video files are significantly larger.\n\n'
              'Blurred: Photos are exported with transparency, but the video background is filled '
              'with a blurred copy of each frame for a natural look. All codecs available.',
          contentWidget: CustomDropdownButton<String>(
            value: mode,
            items: const [
              DropdownMenuItem(value: 'solid', child: Text('Solid colour')),
              DropdownMenuItem(
                  value: 'transparent', child: Text('Transparent')),
              DropdownMenuItem(value: 'blurred', child: Text('Blurred')),
            ],
            onChanged: (String? newValue) async {
              if (newValue == null || newValue == mode) return;

              final bool wasTransparentPhotos = _isTransparentBackground;
              final bool willBeTransparentPhotos = newValue != 'solid';

              // Solid ↔ transparent/blurred changes the photo pipeline (re-stabilization).
              // Transparent ↔ blurred only changes video output (recompile).
              final bool photosPipelineChanges =
                  wasTransparentPhotos != willBeTransparentPhotos;

              if (photosPipelineChanges) {
                final shouldProceed = await Utils.showConfirmChangeDialog(
                  context,
                  "background mode",
                );
                if (!shouldProceed || !mounted) {
                  if (mounted) setState(() {});
                  return;
                }

                setState(() {
                  if (newValue == 'solid') {
                    _backgroundColor = SettingsUtil.fallbackBackgroundColor;
                    _videoBackground = const VideoBackground.transparent();
                  } else if (newValue == 'transparent') {
                    _backgroundColor = SettingsUtil.transparentBackgroundValue;
                    _videoBackground = const VideoBackground.transparent();
                    _videoCodec = VideoCodec.defaultCodec(
                      isTransparentVideo: true,
                    );
                  } else {
                    _backgroundColor = SettingsUtil.transparentBackgroundValue;
                    _videoBackground = const VideoBackground.blurred();
                    if (!VideoCodec.availableCodecs(
                      isTransparentVideo: false,
                    ).contains(_videoCodec)) {
                      _videoCodec = VideoCodec.defaultCodec(
                        isTransparentVideo: false,
                      );
                    }
                  }
                });

                await widget.cancelStabCallback();
                await SettingsUtil.saveBackgroundColor(
                  widget.projectId.toString(),
                  _backgroundColor,
                );
                await SettingsUtil.saveVideoBackground(
                  widget.projectId.toString(),
                  _videoBackground,
                );
                await SettingsUtil.saveVideoCodec(
                  widget.projectId.toString(),
                  _videoCodec,
                );
                await widget.refreshSettings();
                await resetStabStatusAndRestartStabilization();
              } else {
                // Transparent ↔ blurred: video-only recompile.
                final shouldProceed =
                    await ConfirmActionDialog.showRecompileVideoSetting(
                  context,
                  'background mode',
                );
                if (!shouldProceed || !mounted) return;

                setState(() {
                  if (newValue == 'transparent') {
                    _videoBackground = const VideoBackground.transparent();
                    _videoCodec = VideoCodec.defaultCodec(
                      isTransparentVideo: true,
                    );
                  } else {
                    _videoBackground = const VideoBackground.blurred();
                    if (!VideoCodec.availableCodecs(
                      isTransparentVideo: false,
                    ).contains(_videoCodec)) {
                      _videoCodec = VideoCodec.defaultCodec(
                        isTransparentVideo: false,
                      );
                    }
                  }
                });

                await SettingsUtil.saveVideoBackground(
                  widget.projectId.toString(),
                  _videoBackground,
                );
                await SettingsUtil.saveVideoCodec(
                  widget.projectId.toString(),
                  _videoCodec,
                );
                await widget.recompileVideoCallback();
              }
            },
          ),
        ),
        if (mode == 'solid')
          SettingListTile(
            title: 'Background colour',
            showDivider: false,
            contentWidget: GestureDetector(
              onTap: _showColorPickerDialog,
              child: Container(
                width: 44,
                height: 32,
                decoration: BoxDecoration(
                  color: _hexToColor(_backgroundColor),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.settingsCardBorder,
                    width: 1,
                  ),
                ),
                child: _backgroundColor.toUpperCase() == '#000000'
                    ? null
                    : Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
              ),
            ),
            infoContent:
                'The fill colour for areas not covered by the transformed image. '
                'This appears as the border colour when photos are rotated or scaled '
                'during stabilization.',
            showInfo: true,
          ),
      ],
    );
  }

  /// Converts a hex string like '#FF0000' to a Flutter Color.
  /// Returns black for transparent values (used as fallback).
  Color _hexToColor(String hex) {
    if (SettingsUtil.isTransparent(hex)) {
      return Colors.black;
    }
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Add full opacity
    }
    return Color(int.parse(hex, radix: 16));
  }

  /// Converts a Flutter Color to a hex string like '#FF0000'.
  String _colorToHex(Color color) {
    int c(double v) => (v * 255.0).round().clamp(0, 255);
    return '#${c(color.r).toRadixString(16).padLeft(2, '0')}'
            '${c(color.g).toRadixString(16).padLeft(2, '0')}'
            '${c(color.b).toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Future<void> _showColorPickerDialog() async {
    final selectedColor = await _showColorPickerHelper(
      title: 'Background Colour',
      initialColor: _hexToColor(_backgroundColor),
    );

    if (selectedColor != null && mounted) {
      final newHex = _colorToHex(selectedColor);
      if (newHex != _backgroundColor) {
        final bool shouldProceed = await Utils.showConfirmChangeDialog(
          context,
          "background colour",
        );

        if (shouldProceed && mounted) {
          setState(() => _backgroundColor = newHex);

          await widget.cancelStabCallback();
          await SettingsUtil.saveBackgroundColor(
            widget.projectId.toString(),
            newHex,
          );
          await widget.refreshSettings();

          await resetStabStatusAndRestartStabilization();
        }
      }
    }
  }

  Widget _buildWatermarkSwitch() {
    return _buildSimpleBoolSetting(
      title: 'Enable watermark',
      initialValue: enableWatermark,
      setStateValue: (v) => enableWatermark = v,
      dbKey: 'enable_watermark',
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
                  await _saveGlobalSetting('watermark_position', value);
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
            await _saveGlobalSetting('watermark_opacity', value);
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
    if (!mounted) return;
    setState(() => uploading = true);

    if (result != null && result.files.isNotEmpty) {
      String imagePath = result.files.single.path!;
      File file = File(imagePath);
      Uint8List bytes = await file.readAsBytes();

      // Decode and re-encode as PNG using opencv
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (!mat.isEmpty) {
        try {
          final (success, pngBytes) = cv.imencode(
            '.png',
            mat,
            params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]),
          );
          mat.dispose();
          if (success) {
            await DirUtils.createDirectoryIfNotExists(watermarkFilePath);
            await StabUtils.writePngBytesToFileInIsolate(
              watermarkFilePath,
              pngBytes,
            );
          }
          if (!mounted) return;
          setState(() => uploading = false);
        } catch (e) {
          mat.dispose();
          if (!mounted) return;
          setState(() => uploading = false);
        }
      } else {
        mat.dispose();
        if (!mounted) return;
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
              SizedBox(
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
                  fontSize: AppTypography.md,
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
