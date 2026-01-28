import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../services/database_helper.dart';
import '../../services/global_drop_service.dart';
import '../../services/log_service.dart';
import '../../services/face_stabilizer.dart';
import '../../services/settings_cache.dart';
import '../../services/stab_update_event.dart';
import '../../services/thumbnail_service.dart';
import '../../styles/styles.dart';
import '../../utils/project_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/date_stamp_utils.dart';
import '../../utils/capture_timezone.dart';
import '../../utils/utils.dart';
import '../../widgets/yellow_tip_bar.dart';
import '../../widgets/gallery_date_stamp_provider.dart';
import '../../widgets/info_dialog.dart';
import '../../widgets/confirm_action_dialog.dart';
import '../manual_stab_page.dart';
import '../stab_on_diff_face.dart';
import 'gallery_widgets.dart';
import 'gallery_bottom_sheets.dart';
import 'gallery_image_menu.dart';
import 'gallery_export_handler.dart';
import 'image_preview_navigator.dart';

/// Top-level function for compute() - checks if any paths are directories.
/// Runs in isolate to avoid blocking UI when dropping many files.
bool _checkForDirectories(List<String> paths) {
  for (final p in paths) {
    if (FileSystemEntity.isDirectorySync(p)) {
      return true;
    }
  }
  return false;
}

class GalleryPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final VoidCallback stabCallback;
  final VoidCallback userRanOutOfSpaceCallback;
  final Future<void> Function() cancelStabCallback;
  final VoidCallback hideFlashingCircle;
  final bool showFlashingCircle;
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
  final void Function(int index) goToPage;
  final double progressPercent;
  final bool userOnImportTutorial;
  final void Function() setUserOnImportTutorialFalse;
  final void Function(int progressIn) setProgressInMain;
  final void Function(bool value) setImportingInMain;
  final SettingsCache? settingsCache;
  final List<String> imageFilesStr;
  final List<String> stabilizedImageFilesStr;
  final void Function(
    List<String> imageFiles,
    List<String> stabilizedImageFiles,
  ) setRawAndStabPhotoStates;
  final void Function(String stabilizedImagePath) addStabilizedImagePath;
  final Future<void> Function(
    FilePickerResult? pickedFiles,
    Future<void> Function(dynamic file) processFileCallback,
  ) processPickedFiles;
  final Future<void> Function() refreshSettings;
  final Future<void> Function() recompileVideoCallback;
  final String minutesRemaining;
  final bool userRanOutOfSpace;
  final Stream<StabUpdateEvent>? stabUpdateStream;

  // Global drop support
  final void Function(bool isOpen) setImportSheetOpen;
  final List<String>? pendingDropFiles;
  final VoidCallback? clearPendingDropFiles;

  const GalleryPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.userRanOutOfSpace,
    required this.stabCallback,
    required this.userRanOutOfSpaceCallback,
    required this.cancelStabCallback,
    required this.showFlashingCircle,
    required this.hideFlashingCircle,
    required this.stabilizingRunningInMain,
    required this.videoCreationActiveInMain,
    required this.goToPage,
    required this.progressPercent,
    required this.userOnImportTutorial,
    required this.setUserOnImportTutorialFalse,
    required this.importRunningInMain,
    required this.setProgressInMain,
    required this.setImportingInMain,
    required this.processPickedFiles,
    required this.imageFilesStr,
    required this.stabilizedImageFilesStr,
    required this.setRawAndStabPhotoStates,
    required this.addStabilizedImagePath,
    required this.settingsCache,
    required this.refreshSettings,
    required this.recompileVideoCallback,
    required this.minutesRemaining,
    this.stabUpdateStream,
    required this.setImportSheetOpen,
    this.pendingDropFiles,
    this.clearPendingDropFiles,
  });
  @override
  GalleryPageState createState() => GalleryPageState();
}

class GalleryPageState extends State<GalleryPage>
    with SingleTickerProviderStateMixin {
  // Track last project to only clear cache on project switch, not every mount
  static int? _lastProjectId;

  late TabController _tabController;
  bool exportingToZip = false;
  bool gallerySaveIsLoading = false;
  bool gallerySaveSuccessful = false;
  String? activeImagePreviewPath;
  String activeButton = 'raw';
  String? projectOrientation;
  bool isImporting = false;
  bool preparingImport = false;
  int? dropReceivedCount; // Set when drop received, before onDragDone fires
  bool isDraggingOver =
      false; // True when user is dragging files over drop zone
  bool imagePreviewIsOpen = false;
  VoidCallback? closeImagePreviewCallback;
  ValueNotifier<String> activeProcessingDateNotifier = ValueNotifier<String>(
    '',
  );
  late bool showFlashingCircle;
  late int projectId;
  late String projectIdStr;
  bool importingDialogActive = false;
  VoidCallback? closeImportingDialog;
  int photosImported = 0, successfullyImported = 0;
  int gridAxisCount = int.parse(DB.defaultValues['gridAxisCount']!);
  String _galleryGridMode = 'auto';
  double progress = 0;
  bool _isMounted = false;
  int _stabCount = 0;
  double _scale = 1.0;
  double _previousScale = 1.0;
  final ScrollController _stabilizedScrollController = ScrollController();
  final ScrollController _rawScrollController = ScrollController();
  StreamSubscription<StabUpdateEvent>? _stabUpdateSubscription;
  Timer? _loadImagesDebounce;
  int _loadImagesRequestId = 0;
  bool _stickyBottomEnabled = true;
  bool _isAutoScrolling = false;
  bool _isSelectionMode = false;
  Set<String> _selectedPhotos = {};

  // Global drop support - idempotent processing flag
  bool _pendingFilesProcessed = false;

  // Date stamp settings for gallery labels
  bool _galleryDateLabelsEnabled = false;
  bool _galleryRawDateLabelsEnabled = false;
  String _galleryDateFormat = DateStampUtils.galleryFormatMMYY;
  String _galleryDateFont = DateStampUtils.defaultFont;

  // Cache for capture timezone offsets (timestamp -> offset minutes)
  Map<String, int?> _captureOffsetMap = {};

  /// Reload all gallery settings from DB. Call this after settings change.
  Future<void> reloadGallerySettings() async {
    final results = await Future.wait([
      SettingsUtil.loadGridAxisCount(projectIdStr),
      SettingsUtil.loadGalleryGridMode(projectIdStr),
      SettingsUtil.loadProjectOrientation(projectIdStr),
      SettingsUtil.loadGalleryDateLabelsEnabled(projectIdStr),
      SettingsUtil.loadGalleryRawDateLabelsEnabled(projectIdStr),
      SettingsUtil.loadGalleryDateFormat(projectIdStr),
      SettingsUtil.loadGalleryDateStampFont(projectIdStr),
    ]);
    if (mounted) {
      setState(() {
        gridAxisCount = results[0] as int;
        _galleryGridMode = results[1] as String;
        projectOrientation = results[2] as String;
        _galleryDateLabelsEnabled = results[3] as bool;
        _galleryRawDateLabelsEnabled = results[4] as bool;
        _galleryDateFormat = results[5] as String;
        _galleryDateFont = results[6] as String;
      });
    }
  }

  /// Load capture timezone offsets for all images.
  Future<void> _loadCaptureOffsets() async {
    try {
      final offsets = await CaptureTimezone.loadOffsetsForMultipleLists([
        widget.imageFilesStr,
        widget.stabilizedImageFilesStr,
      ], projectId);

      if (mounted) {
        setState(() => _captureOffsetMap = offsets);
      }
    } catch (e) {
      // Graceful degradation: continue with empty map (falls back to local time)
    }
  }

  bool _isAtBottom() {
    if (!_stabilizedScrollController.hasClients) return true;
    final maxScroll = _stabilizedScrollController.position.maxScrollExtent;
    final currentScroll = _stabilizedScrollController.offset;
    return (maxScroll - currentScroll) <= 20;
  }

  bool _hasNoScrollbar() {
    if (!_stabilizedScrollController.hasClients) return true;
    return _stabilizedScrollController.position.maxScrollExtent <= 0;
  }

  void _onStabilizedScroll() {
    if (_isAutoScrolling) return;

    final atBottom = _isAtBottom() || _hasNoScrollbar();

    if (atBottom && !_stickyBottomEnabled) {
      setState(() {
        _stickyBottomEnabled = true;
      });
    } else if (!atBottom && _stickyBottomEnabled) {
      setState(() {
        _stickyBottomEnabled = false;
      });
    }
  }

  void _scrollToBottomAndReenableSticky() {
    setState(() {
      _stickyBottomEnabled = true;
    });
    _performAutoScroll();
  }

  void _performAutoScroll() {
    if (!_stabilizedScrollController.hasClients) return;
    _isAutoScrolling = true;
    _stabilizedScrollController.jumpTo(
      _stabilizedScrollController.position.maxScrollExtent,
    );
    _isAutoScrolling = false;
  }

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    projectId = widget.projectId;
    projectIdStr = widget.projectId.toString();

    // Only clear thumbnail cache when switching projects, not on every mount.
    // This preserves cache state when returning from StabDiffFacePage.
    if (_lastProjectId != projectId) {
      ThumbnailService.instance.clearAllCache();
      _lastProjectId = projectId;
    }

    _initializeFromCache();
    _init();
    _tabController = TabController(length: 2, vsync: this);
    showFlashingCircle = widget.showFlashingCircle;
    _loadImages();
    _loadCaptureOffsets();
    _stabilizedScrollController.addListener(_onStabilizedScroll);
    _tabController.addListener(_onTabChanged);

    // Check for pending files from global drop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingDropFiles();
    });
  }

  @override
  void didUpdateWidget(covariant GalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reload settings when settingsCache reference changes
    // (indicates parent called refreshSettings after settings were modified)
    if (widget.settingsCache != oldWidget.settingsCache) {
      reloadGallerySettings();
    }

    // Reload offsets if image lists changed (new photos imported/deleted)
    if (widget.imageFilesStr != oldWidget.imageFilesStr ||
        widget.stabilizedImageFilesStr != oldWidget.stabilizedImageFilesStr) {
      _loadCaptureOffsets();
    }

    // Check for new pending files from global drop
    if (widget.pendingDropFiles != oldWidget.pendingDropFiles) {
      _pendingFilesProcessed = false; // Reset flag for new files
      _checkPendingDropFiles();
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          if (_tabController.index == 0) {
            _stickyBottomEnabled = true;
            GalleryUtils.scrollToBottomInstantly(_stabilizedScrollController);
          } else {
            GalleryUtils.scrollToBottomInstantly(_rawScrollController);
          }
        });
      });
    }
  }

  Future<void> _initializeFromCache() async {
    // Wait for cache with timeout and mounted check
    const timeout = Duration(seconds: 30);
    final deadline = DateTime.now().add(timeout);

    while (widget.settingsCache == null && mounted) {
      if (DateTime.now().isAfter(deadline)) {
        return; // Timeout - proceed without cache
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted || widget.settingsCache == null) return;

    bool hasOpenedNonEmptyGallery =
        widget.settingsCache!.hasOpenedNonEmptyGallery;
    if (!hasOpenedNonEmptyGallery) {
      await SettingsUtil.setHasOpenedNonEmptyGalleryToTrue(projectIdStr);
      widget.refreshSettings();
    }
  }

  Future<void> _showChangeDateDialog(String currentTimestamp) async {
    DateTime initialDate = DateTime.fromMillisecondsSinceEpoch(
      int.parse(currentTimestamp),
    );
    DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (newDate == null) return;
    if (!mounted) return;
    TimeOfDay initialTime = TimeOfDay.fromDateTime(initialDate);
    TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (newTime == null) return;
    if (!mounted) return;
    DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );
    String newTimestamp = newDateTime.millisecondsSinceEpoch.toString();

    // Check if this would change the photo order
    final orderChanged = _wouldChangeOrder(currentTimestamp, newTimestamp);

    // Check if the formatted date stamp text would change
    bool dateStampTextChanged = false;
    final exportStampsEnabled =
        await SettingsUtil.loadExportDateStampEnabled(projectIdStr);

    if (exportStampsEnabled && !orderChanged) {
      // Only check text if stamps are enabled and order didn't change
      final format = await SettingsUtil.loadExportDateStampFormat(projectIdStr);
      final oldText = DateStampUtils.formatTimestamp(
        int.parse(currentTimestamp),
        format,
      );
      final newText = DateStampUtils.formatTimestamp(
        int.parse(newTimestamp),
        format,
      );
      dateStampTextChanged = oldText != newText;
    }

    // Determine if we need to show a confirmation dialog and recompile
    final needsRecompile = orderChanged || dateStampTextChanged;

    if (needsRecompile) {
      if (!mounted) return;
      final confirmed = await ConfirmActionDialog.showDateChangeRecompile(
        context,
        orderChanged: orderChanged,
      );
      if (!confirmed) return;
    }

    await _changePhotoDate(currentTimestamp, newTimestamp, needsRecompile);
  }

  /// Checks if changing a photo's timestamp would change its position in the sorted list.
  bool _wouldChangeOrder(String oldTimestamp, String newTimestamp) {
    final currentFiles = widget.imageFilesStr;
    if (currentFiles.length <= 1) return false;

    // Extract all timestamps once
    final allTimestamps =
        currentFiles.map((f) => path.basenameWithoutExtension(f)).toList();
    final oldIndex = allTimestamps.indexOf(oldTimestamp);

    // Filter to get timestamps without the one being changed
    final timestamps = allTimestamps.where((t) => t != oldTimestamp).toList();

    // Add the new timestamp and sort to find new position
    timestamps.add(newTimestamp);
    timestamps.sort();
    final newIndex = timestamps.indexOf(newTimestamp);

    return oldIndex != newIndex;
  }

  Future<void> _changePhotoDate(
    String oldTimestamp,
    String newTimestamp,
    bool needsRecompile,
  ) async {
    try {
      String oldRawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        oldTimestamp,
        projectId,
      );
      File oldRawFile = File(oldRawPhotoPath);
      if (!await oldRawFile.exists()) {
        throw Exception('Original file not found');
      }
      String fileExtension = path.extension(oldRawPhotoPath);
      String newRawPhotoPath = path.join(
        path.dirname(oldRawPhotoPath),
        '$newTimestamp$fileExtension',
      );
      await oldRawFile.rename(newRawPhotoPath);
      String oldRawThumbPath = oldRawPhotoPath.replaceAll(
        DirUtils.photosRawDirname,
        DirUtils.thumbnailDirname,
      );
      oldRawThumbPath = path.join(
        path.dirname(oldRawThumbPath),
        "${path.basenameWithoutExtension(oldRawPhotoPath)}.jpg",
      );
      File oldRawThumbFile = File(oldRawThumbPath);
      if (await oldRawThumbFile.exists()) {
        String newRawThumbPath = path.join(
          path.dirname(oldRawThumbPath),
          "$newTimestamp.jpg",
        );
        await oldRawThumbFile.rename(newRawThumbPath);
      }
      List<String> orientations = ['portrait', 'landscape'];
      for (String orientation in orientations) {
        try {
          String oldStabPath = await DirUtils
              .getStabilizedImagePathFromRawPathAndProjectOrientation(
            projectId,
            oldRawPhotoPath,
            orientation,
          );
          File oldStabFile = File(oldStabPath);
          if (await oldStabFile.exists()) {
            String newStabPath = path.join(
              path.dirname(oldStabPath),
              '$newTimestamp.png',
            );
            await oldStabFile.rename(newStabPath);
            String oldStabThumbPath = FaceStabilizer.getStabThumbnailPath(
              oldStabPath,
            );
            File oldStabThumbFile = File(oldStabThumbPath);
            if (await oldStabThumbFile.exists()) {
              String newStabThumbPath = FaceStabilizer.getStabThumbnailPath(
                newStabPath,
              );
              await DirUtils.createDirectoryIfNotExists(newStabThumbPath);
              await oldStabThumbFile.rename(newStabThumbPath);
            }
          }
        } catch (e) {
          LogService.instance.log(
            'No stabilized file found for $orientation: $e',
          );
        }
      }
      final oldPhotoRecord = await DB.instance.getPhotoByTimestamp(
        oldTimestamp,
        projectId,
      );
      if (oldPhotoRecord == null) return;
      final int oldId = oldPhotoRecord['id'] as int;
      int? newId = await DB.instance.updatePhotoTimestamp(
        oldTimestamp,
        newTimestamp,
        projectId,
      );
      final String currentGuidePhoto =
          await SettingsUtil.loadSelectedGuidePhoto(projectId.toString());
      if (currentGuidePhoto == oldId.toString() && newId != null) {
        await DB.instance.setSettingByTitle(
          "selected_guide_photo",
          newId.toString(),
          projectId.toString(),
        );
      }
      final int newTsInt = int.parse(newTimestamp);
      final int newOffsetMin = DateTime.fromMillisecondsSinceEpoch(
        newTsInt,
        isUtc: true,
      ).toLocal().timeZoneOffset.inMinutes;
      await DB.instance.setCaptureOffsetMinutesByTimestamp(
        newTimestamp,
        projectId,
        newOffsetMin,
      );
      await _loadImages();

      // Trigger video recompilation if needed
      if (needsRecompile) {
        await widget.recompileVideoCallback();
      }
    } catch (e) {
      LogService.instance.log('Error changing photo date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to change photo date: $e')),
      );
    }
  }

  Future<void> _loadImages() async {
    // Guard against race conditions: capture request ID to detect if a newer
    // request started while this one was running (stale snapshot prevention)
    final int thisRequestId = ++_loadImagesRequestId;

    await GalleryUtils.loadImages(
      projectId: projectId,
      projectIdStr: projectIdStr,
      onImagesLoaded: (rawImages, stabImageFiles) async {
        // Discard stale results if a newer request has started
        if (thisRequestId != _loadImagesRequestId) return;

        var finalStabFiles = stabImageFiles;

        // Preserve paths for photos being retried (files temporarily deleted)
        if (_retryingPhotoTimestamps.isNotEmpty) {
          final diskTimestamps = stabImageFiles
              .map((p) => path.basenameWithoutExtension(p))
              .toSet();

          // Find retry paths not in the new disk scan
          final pathsToPreserve = <String>[];
          for (final ts in _retryingPhotoTimestamps) {
            if (!diskTimestamps.contains(ts)) {
              // Find this path in the current list
              final existingPath = widget.stabilizedImageFilesStr
                  .where((p) => path.basenameWithoutExtension(p) == ts)
                  .firstOrNull;
              if (existingPath != null) {
                pathsToPreserve.add(existingPath);
              }
            }
          }

          if (pathsToPreserve.isNotEmpty) {
            // Merge: use disk scan as base, insert preserved paths at their original positions
            final currentList = widget.stabilizedImageFilesStr;
            final mergedList = <String>[];
            final diskSet = stabImageFiles.toSet();
            final preserveSet = pathsToPreserve.toSet();

            // Walk through current list order, include items from disk or preserve set
            for (final p in currentList) {
              if (diskSet.contains(p) || preserveSet.contains(p)) {
                mergedList.add(p);
                diskSet.remove(p);
                preserveSet.remove(p);
              }
            }
            // Add any remaining disk items (shouldn't happen, but just in case)
            mergedList.addAll(diskSet);

            finalStabFiles = mergedList;
          }

          // Clear retry flags for photos that now have files on disk
          _retryingPhotoTimestamps.removeWhere(diskTimestamps.contains);
        }

        widget.setRawAndStabPhotoStates(rawImages, finalStabFiles);
      },
      onShowInfoDialog: () => showInfoDialog(context),
    );

    // Also guard scroll operation against stale requests
    if (thisRequestId != _loadImagesRequestId) return;

    if (_stickyBottomEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoScroll();
      });
    }
  }

  List<File> cloneList(List list) => List.from(list);
  Future<void> _init() async {
    await reloadGallerySettings();
    if (widget.userOnImportTutorial) {
      widget.setUserOnImportTutorialFalse();
      if (mounted) _showImportOptionsBottomSheet(context);
    }

    if (widget.stabUpdateStream != null) {
      _stabUpdateSubscription = widget.stabUpdateStream!.listen((event) {
        if (!_isMounted) return;

        // For completion events, reload immediately without debounce
        if (event.isCompletionEvent) {
          _loadImages();
          return;
        }

        // For normal progress updates, use incremental update if timestamp available
        final newCount = event.photoIndex ?? 0;
        if (newCount != _stabCount) {
          _stabCount = newCount;

          // Use incremental update if timestamp is available
          if (event.timestamp != null && projectOrientation != null) {
            _handleIncrementalStabUpdate(event.timestamp!);
          } else {
            // Fall back to debounced full reload
            _loadImagesDebounce?.cancel();
            _loadImagesDebounce = Timer(const Duration(milliseconds: 500), () {
              if (_isMounted) _loadImages();
            });
          }
        }
      });
    }
  }

  /// Handles incremental update when a single photo is stabilized.
  Future<void> _handleIncrementalStabUpdate(String timestamp) async {
    // Check if this is a retry completion - if so, clear the flag and rebuild
    final isRetry = _retryingPhotoTimestamps.contains(timestamp);
    if (isRetry) {
      setState(() {
        _retryingPhotoTimestamps.remove(timestamp);
      });
      // For retries, the path is already in the list - just rebuild to show new thumbnail
      return;
    }

    final newPath = await DirUtils.getStabilizedImagePathFromTimestamp(
      projectId,
      timestamp,
      projectOrientation!,
    );

    widget.addStabilizedImagePath(newPath);

    if (_stickyBottomEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoScroll();
      });
    }
  }

  @override
  void dispose() {
    _loadImagesDebounce?.cancel();
    _stabUpdateSubscription?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    activeProcessingDateNotifier.dispose();
    _stabilizedScrollController.removeListener(_onStabilizedScroll);
    _stabilizedScrollController.dispose();
    _rawScrollController.dispose();
    _isMounted = false;
    _retryingPhotoTimestamps.clear();
    super.dispose();
  }

  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.photos.request();
    if (status.isGranted) {
      return true;
    } else if (status.isDenied) {
      status = await Permission.storage.request();
      return false;
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }
    return false;
  }

  Future<void> _pickFromGallery() async {
    try {
      await checkAndRequestPermissions();
      if (!mounted) return;
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 100,
          requestType: RequestType.image,
        ),
      );
      if (result == null) {
        return; // for reference this means switching to the raw tab in the gallery
      }
      setState(() {
        _tabController.index = 1;
      });
      GalleryUtils.startImportBatch(result.length);
      for (final AssetEntity asset in result) {
        await _processAsset(asset);
      }
      widget.refreshSettings();
      _loadImages();
      widget.stabCallback();
    } catch (e) {
      LogService.instance.log("Error picking images: $e");
    }
  }

  Future<void> _processAsset(AssetEntity asset) async {
    final Uint8List? originBytes = await asset.originBytes;
    if (originBytes == null) return;
    final String originPath = (await asset.originFile)!.path;
    final String tempOriginPhotoPath = await _getTemporaryPhotoPath(
      asset,
      originPath,
    );
    final File tempOriginFile = File(tempOriginPhotoPath);
    if (await _isModifiedLivePhoto(asset, originPath)) {
      await _writeModifiedLivePhoto(asset, tempOriginFile);
    } else {
      await tempOriginFile.writeAsBytes(originBytes);
    }
    await GalleryUtils.processPickedImage(
      tempOriginPhotoPath,
      projectId,
      activeProcessingDateNotifier,
      onImagesLoaded: _loadImages,
      timestamp: asset.createDateTime.millisecondsSinceEpoch,
    );
  }

  Future<String> _getTemporaryPhotoPath(
    AssetEntity asset,
    String originPath,
  ) async {
    final String basename = path
        .basenameWithoutExtension(originPath)
        .toLowerCase()
        .replaceAll(".", "");
    final String extension = path.extension(originPath).toLowerCase();
    final String tempDir = await DirUtils.getTemporaryDirPath();
    return path.join(tempDir, "$basename$extension");
  }

  Future<bool> _isModifiedLivePhoto(
    AssetEntity asset,
    String originPath,
  ) async {
    final String extension = path.extension(originPath).toLowerCase();
    return asset.isLivePhoto && (extension == ".jpg" || extension == ".jpeg");
  }

  Future<void> _writeModifiedLivePhoto(
    AssetEntity asset,
    File tempOriginFile,
  ) async {
    File? assetFile = await asset.file;
    var bytes = await assetFile?.readAsBytes();
    if (bytes != null) {
      await tempOriginFile.writeAsBytes(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStampConfig = GalleryDateStampConfig(
      stabilizedLabelsEnabled: _galleryDateLabelsEnabled,
      rawLabelsEnabled: _galleryRawDateLabelsEnabled,
      dateFormat: _galleryDateFormat,
      captureOffsetMap: _captureOffsetMap,
      fontFamily: _galleryDateFont,
    );

    return GalleryDateStampProvider(
      config: dateStampConfig,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        body: Column(
          children: [
            _buildCustomHeader(context),
            Expanded(
              child: GestureDetector(
                onScaleStart: (details) {
                  if (Platform.isAndroid || Platform.isIOS) {
                    _previousScale = _scale;
                  }
                },
                onScaleUpdate: (details) {
                  if (Platform.isAndroid || Platform.isIOS) {
                    setState(() {
                      _scale = _previousScale * details.scale;
                      const int maxSteps = 5;
                      gridAxisCount = (4 / _scale).clamp(1, maxSteps).toInt();
                    });
                  }
                },
                child: Stack(
                  children: [
                    (!isImporting && !widget.importRunningInMain)
                        ? _buildTabBarView()
                        : _buildLoadingView(),
                    if (!_isSelectionMode)
                      Positioned(
                        top: 7,
                        right: 8,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceElevated,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.overlay.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 20.0,
                              color: AppColors.textPrimary,
                            ),
                            padding: EdgeInsets.zero,
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            offset: const Offset(0, 48),
                            onSelected: (value) {
                              switch (value) {
                                case 'import':
                                  if (isImporting) {
                                    _showImportingDialog();
                                  } else {
                                    _showImportOptionsBottomSheet(context);
                                  }
                                  break;
                                case 'export':
                                  _showExportOptionsBottomSheet(context);
                                  break;
                                case 'select':
                                  setState(() => _isSelectionMode = true);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              _buildModernMenuItem(
                                value: 'import',
                                icon: Icons.file_upload_outlined,
                                label: 'Import',
                              ),
                              const PopupMenuDivider(height: 1),
                              _buildModernMenuItem(
                                value: 'export',
                                icon: Icons.file_download_outlined,
                                label: 'Export',
                              ),
                              const PopupMenuDivider(height: 1),
                              _buildModernMenuItem(
                                value: 'select',
                                icon: Icons.check_circle_outline,
                                label: 'Select',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isSelectionMode) _buildSelectionActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return _buildTabBarContainer();
  }

  Widget _buildTabBarContainer() {
    return Container(
      color: AppColors.background,
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Stabilized'),
          Tab(text: 'Raw'),
        ],
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.accentLight,
        labelColor: AppColors.accentLight,
        unselectedLabelColor: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Stack(
          children: [
            _buildImageGrid(
              widget.stabilizedImageFilesStr,
              _stabilizedScrollController,
            ),
            if (!_stickyBottomEnabled && !_hasNoScrollbar())
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surfaceElevated,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.overlay.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.small(
                    onPressed: _scrollToBottomAndReenableSticky,
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    child: const Icon(Icons.arrow_downward, size: 20),
                  ),
                ),
              ),
          ],
        ),
        _buildImageGrid(widget.imageFilesStr, _rawScrollController),
      ],
    );
  }

  Widget _buildImageGrid(
    List<String> imageFiles,
    ScrollController scrollController,
  ) {
    if (widget.stabilizedImageFilesStr.isEmpty &&
        widget.imageFilesStr.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: const YellowTipBar(
            message: "Your gallery is empty. Take or import photos to begin.",
          ),
        ),
      );
    }
    final bool isStabilizedTab =
        scrollController == _stabilizedScrollController;
    final List<String> files =
        isStabilizedTab ? widget.stabilizedImageFilesStr : imageFiles;

    // Only show end-of-grid FlashingBox if there are NEW photos being stabilized,
    // not just retries. If all raw photos are already in stabilized list, it's only retries.
    final bool onlyRetrying = _retryingPhotoTimestamps.isNotEmpty &&
        widget.imageFilesStr.length == widget.stabilizedImageFilesStr.length;
    final bool showStabProgressIndicator =
        isStabilizedTab && widget.stabilizingRunningInMain && !onlyRetrying;

    final int itemCount =
        showStabProgressIndicator ? files.length + 1 : files.length;
    // Wrap grid in dark container so spacing between photos is dark, not white
    return Container(
      color: AppColors.galleryBackground,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        controller: scrollController,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _tileExtentForGridCount(context),
          crossAxisSpacing: 2.0,
          mainAxisSpacing: 2.0,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (showStabProgressIndicator && index == files.length) {
            return const FlashingBox();
          } else if (index < files.length) {
            return _buildImageTile(files[index]);
          } else {
            // Defensive fallback - should never reach here after fix
            return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.settingsAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            preparingImport ? 'Preparing import...' : 'Importing...',
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.9),
              fontSize: AppTypography.lg,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preparingImport
                ? 'Scanning folders'
                : '${widget.progressPercent.toStringAsFixed(1)}%',
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.5),
              fontSize: AppTypography.md,
            ),
          ),
        ],
      ),
    );
  }

  double _tileExtentForGridCount(BuildContext context) {
    if (_galleryGridMode == 'auto') {
      return 180;
    }
    final double width = MediaQuery.of(context).size.width;
    return width / gridAxisCount;
  }

  void increaseSuccessfulImportCount() => successfullyImported++;
  void increasePhotosImported(int value) {
    photosImported = photosImported + value;
  }

  Future<void> _pickFiles() async {
    try {
      setState(() {
        photosImported = 0;
        successfullyImported = 0;
        _tabController.index = 1;
      });
      FilePickerResult? pickedFiles;
      try {
        pickedFiles = await FilePicker.pickFiles(allowMultiple: true);
      } catch (e) {
        LogService.instance.log(e.toString());
        return;
      }
      if (pickedFiles == null) return;
      setState(() => isImporting = true);
      if (widget.stabilizingRunningInMain) {
        await widget.cancelStabCallback();
      }
      GalleryUtils.startImportBatch(pickedFiles.files.length);
      await widget.processPickedFiles(pickedFiles, processPickedFile);
      final String projectOrientationRaw =
          await SettingsUtil.loadProjectOrientation(projectIdStr);
      setState(() {
        projectOrientation = projectOrientationRaw;
      });
      widget.refreshSettings();
      widget.stabCallback();
      setState(() => isImporting = false);
      _loadImages();
      _showImportCompleteDialog(
        successfullyImported,
        photosImported - successfullyImported,
      );
    } catch (e) {
      LogService.instance.log("ERROR CAUGHT IN PICK FILES");
    }
  }

  Future<void> processPickedFile(dynamic file) async {
    await GalleryUtils.processPickedFile(
      file,
      projectId,
      activeProcessingDateNotifier,
      onImagesLoaded: _loadImages,
      setProgressInMain: widget.setProgressInMain,
      increaseSuccessfulImportCount: increaseSuccessfulImportCount,
      increasePhotosImported: increasePhotosImported,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Global Drop Support
  // ─────────────────────────────────────────────────────────────────────────────

  /// Check for pending files from global drag-and-drop.
  /// Called from initState and didUpdateWidget.
  void _checkPendingDropFiles() {
    // IDEMPOTENT: Only process once per set of files
    if (_pendingFilesProcessed) return;
    if (widget.pendingDropFiles == null || widget.pendingDropFiles!.isEmpty) {
      return;
    }

    _pendingFilesProcessed = true; // Mark as processed BEFORE async work

    // Clear immediately to prevent re-processing on rebuild
    final filesToProcess = List<String>.from(widget.pendingDropFiles!);
    widget.clearPendingDropFiles?.call();

    _processGlobalDropFiles(filesToProcess);
  }

  /// Process files from global drag-and-drop.
  /// Uses the same logic as the import sheet's drop zone.
  Future<void> _processGlobalDropFiles(List<String> filePaths) async {
    // If already importing, queue the files
    if (isImporting) {
      GlobalDropService.instance.queueFiles(filePaths, widget.projectId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${filePaths.length} files queued for import'),
          ),
        );
      }
      return;
    }

    setState(() {
      photosImported = 0;
      successfullyImported = 0;
      _tabController.index = 1; // Switch to Raw tab
      isImporting = true;
    });

    widget.setImportingInMain(true);

    if (widget.stabilizingRunningInMain) {
      await widget.cancelStabCallback();
    }

    setState(() => preparingImport = true);
    await Future.delayed(Duration.zero); // Yield to UI

    final bool hasDirectories = await compute(_checkForDirectories, filePaths);

    if (hasDirectories) {
      await _handleDropWithDirectories(filePaths);
    } else {
      setState(() => preparingImport = false);
      GalleryUtils.startImportBatch(filePaths.length);
      for (final filePath in filePaths) {
        await processPickedFile(File(filePath));
      }
    }

    widget.setImportingInMain(false);

    // Check queue for more files (for THIS project only)
    await _processQueuedFiles();

    if (!mounted) return;

    final String projectOrientationRaw =
        await SettingsUtil.loadProjectOrientation(projectIdStr);
    setState(() {
      projectOrientation = projectOrientationRaw;
      isImporting = false;
    });

    widget.refreshSettings();
    widget.stabCallback();
    _loadImages();
    _showImportCompleteDialog(
      successfullyImported,
      photosImported - successfullyImported,
    );
  }

  /// Process any queued files from GlobalDropService.
  Future<void> _processQueuedFiles() async {
    // Only consume files for THIS project (prevents cross-project imports)
    final queuedFiles =
        GlobalDropService.instance.consumeQueuedFiles(widget.projectId);
    if (queuedFiles.isNotEmpty) {
      // Recursively process queued files
      await _processGlobalDropFiles(queuedFiles);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────

  void _showImportCompleteDialog(int imported, int skipped) {
    if (importingDialogActive) {
      closeImportingDialog!();
    }
    showStyledInfoDialog(
      context,
      'Imported: $imported\nSkipped (already imported): $skipped',
      title: 'Import Complete',
      icon: Icons.check_circle_outline_rounded,
      iconColor: AppColors.success,
      primaryActionLabel: 'View Stabilized',
      onPrimaryAction: () => _tabController.animateTo(0),
    );
  }

  void _showImportingDialog() {
    setState(() => importingDialogActive = true);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        void closeMe() => Navigator.of(context).pop();
        closeImportingDialog = closeMe;
        return AlertDialog(
          title: const Text("Importing Active"),
          content: ValueListenableBuilder<String>(
            valueListenable: activeProcessingDateNotifier,
            builder: (context, value, child) {
              return Text("Currently processing image taken $value...");
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                setState(() => importingDialogActive = false);
                closeMe();
              },
            ),
          ],
        );
      },
    );
  }

  PopupMenuItem<String> _buildModernMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppTypography.md,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showImportOptionsBottomSheet(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final List<Widget> content = [
      if (isMobile) ...[
        GalleryBottomSheets.buildImportOptionTile(
          icon: Icons.photo_library_outlined,
          title: 'Photo Library',
          subtitle: 'Select photos from your device',
          onTap: isImporting
              ? null
              : () {
                  Navigator.of(context).pop();
                  try {
                    _pickFromGallery();
                  } catch (e) {
                    LogService.instance.log(e.toString());
                  }
                },
        ),
        const SizedBox(height: 10),
      ],
      GalleryBottomSheets.buildImportOptionTile(
        icon: Icons.folder_outlined,
        title: isDesktop ? 'Browse Files' : 'Files',
        subtitle:
            isDesktop ? 'Select images or folders' : 'Import from file manager',
        onTap: isImporting
            ? null
            : () {
                try {
                  _pickFiles();
                } finally {
                  Navigator.of(context).pop();
                }
              },
      ),
    ];
    // Reset modal-specific state
    isDraggingOver = false;
    dropReceivedCount = null;

    // Notify that import sheet is opening (disables global drop overlay)
    widget.setImportSheetOpen(true);

    bool isDateInfoExpanded = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible:
          dropReceivedCount == null, // Can't dismiss while processing
      enableDrag: dropReceivedCount == null,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final List<Widget> modalContent = [
              ...content,
              if (isDesktop) ...[
                const SizedBox(height: 16),
                _buildDesktopDropZoneWithState(
                  setModalState: setModalState,
                  isDraggingOver: isDraggingOver,
                  dropReceivedCount: dropReceivedCount,
                  onDraggingChanged: (value) {
                    isDraggingOver = value;
                    setModalState(() {});
                  },
                  onDropReceivedCountChanged: (value) {
                    dropReceivedCount = value;
                    setModalState(() {});
                  },
                ),
              ],
              const SizedBox(height: 16),
              GalleryBottomSheets.buildPhotoDateInfoBanner(
                isExpanded: isDateInfoExpanded,
                onToggle: () {
                  isDateInfoExpanded = !isDateInfoExpanded;
                  setModalState(() {});
                },
              ),
            ];
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: GalleryBottomSheets.buildOptionsSheet(
                  context, 'Import Photos', modalContent),
            );
          },
        );
      },
    ).whenComplete(() {
      // Always reset when sheet closes (success, error, ESC, back, etc.)
      widget.setImportSheetOpen(false);
    });
  }

  Widget _buildDesktopDropZoneWithState({
    required StateSetter setModalState,
    required bool isDraggingOver,
    required int? dropReceivedCount,
    required void Function(bool) onDraggingChanged,
    required void Function(int?) onDropReceivedCountChanged,
  }) {
    return DropTarget(
      onDragEntered: (details) {
        onDraggingChanged(true);
      },
      onDragExited: (details) {
        onDraggingChanged(false);
      },
      onDragDone: (details) async {
        // Reset dragging state immediately when drop occurs
        onDraggingChanged(false);

        // Reset drop received state (modal will close anyway)
        onDropReceivedCountChanged(null);

        if (isImporting) return;
        Navigator.of(context).pop();

        setState(() {
          photosImported = 0;
          successfullyImported = 0;
          _tabController.index = 1;
          isImporting = true;
        });

        widget.setImportingInMain(true);

        if (widget.stabilizingRunningInMain) {
          await widget.cancelStabCallback();
        }

        setState(() => preparingImport = true);

        await Future.delayed(Duration.zero);

        final List<String> itemPaths =
            details.files.map((f) => f.path).toList();

        final bool hasDirectories =
            await compute(_checkForDirectories, itemPaths);

        if (hasDirectories) {
          await _handleDropWithDirectories(itemPaths);
        } else {
          // Files-only path - done preparing, start import
          setState(() => preparingImport = false);

          GalleryUtils.startImportBatch(details.files.length);

          for (final f in details.files) {
            await processPickedFile(File(f.path));
          }
        }

        // Always reset parent state even if widget is disposed
        widget.setImportingInMain(false);

        if (!mounted) return;

        final String projectOrientationRaw =
            await SettingsUtil.loadProjectOrientation(projectIdStr);
        setState(() {
          projectOrientation = projectOrientationRaw;
          isImporting = false;
        });
        widget.refreshSettings();
        widget.stabCallback();
        _loadImages();
        _showImportCompleteDialog(
          successfullyImported,
          photosImported - successfullyImported,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: isDraggingOver
              ? AppColors.info.withValues(alpha: 0.15)
              : AppColors.textPrimary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDraggingOver
                ? AppColors.info.withValues(alpha: 0.5)
                : AppColors.textPrimary.withValues(alpha: 0.12),
            width: isDraggingOver ? 2.0 : 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: dropReceivedCount != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.textPrimary.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Preparing import...',
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.7),
                      fontSize: AppTypography.md,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dropReceivedCount items',
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.4),
                      fontSize: AppTypography.sm,
                    ),
                  ),
                ],
              )
            : isDraggingOver
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.file_download_outlined,
                          size: 26,
                          color: AppColors.info.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Release to import',
                        style: TextStyle(
                          color: AppColors.info.withValues(alpha: 0.9),
                          fontSize: AppTypography.md,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'drop files to begin',
                        style: TextStyle(
                          color: AppColors.info.withValues(alpha: 0.6),
                          fontSize: AppTypography.sm,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.upload_file_outlined,
                          size: 26,
                          color: AppColors.textPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drop files or folders here',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.7),
                          fontSize: AppTypography.md,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'images and folders supported',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.4),
                          fontSize: AppTypography.sm,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// Handles drops that may contain directories.
  /// Collects all valid images from directories, merges with dropped files,
  /// and processes them.
  Future<void> _handleDropWithDirectories(List<String> itemPaths) async {
    final List<String> filePaths = [];
    final List<String> directoryPaths = [];

    // Classify items as files or directories
    for (final itemPath in itemPaths) {
      if (await FileSystemEntity.isDirectory(itemPath)) {
        directoryPaths.add(itemPath);
      } else if (await FileSystemEntity.isFile(itemPath)) {
        filePaths.add(itemPath);
      }
    }

    // Collect all files from directories (runs in isolate)
    if (directoryPaths.isNotEmpty) {
      // Show "Preparing import..." while scanning directories
      if (mounted) {
        setState(() => preparingImport = true);
      }

      for (final dirPath in directoryPaths) {
        if (!mounted) return;

        final scanResult =
            await GalleryUtils.collectFilesFromDirectory(dirPath);

        if (scanResult.wasCancelled) {
          if (mounted) {
            setState(() {
              isImporting = false;
              preparingImport = false;
            });
            widget.setImportingInMain(false);
          }
          return;
        }

        filePaths.addAll(scanResult.validImagePaths);
      }

      // Done scanning, switch to importing mode
      if (mounted) {
        setState(() => preparingImport = false);
      }
    }

    // Confirm large imports
    if (filePaths.length > GalleryUtils.largeDirectoryThreshold) {
      if (!mounted) return;

      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Large Import',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            'Found ${filePaths.length} images. This may take a while.\n\n'
            'Continue with import?',
            style:
                TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        if (mounted) {
          setState(() {
            isImporting = false;
            preparingImport = false;
          });
          widget.setImportingInMain(false);
        }
        return;
      }
    }

    if (filePaths.isEmpty) {
      if (mounted) {
        setState(() {
          isImporting = false;
          preparingImport = false;
        });
        widget.setImportingInMain(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No valid images found in dropped items')),
        );
      }
      return;
    }

    // Sort alphabetically for consistent ordering (matches ZIP behavior)
    filePaths.sort((a, b) => path.basename(a).toLowerCase().compareTo(
          path.basename(b).toLowerCase(),
        ));

    // Process all files
    GalleryUtils.startImportBatch(filePaths.length);
    for (final filePath in filePaths) {
      if (!mounted) return;
      await processPickedFile(File(filePath));
    }
  }

  void _showExportOptionsBottomSheet(BuildContext context) {
    GalleryExportHandler.showExportOptionsSheet(
      context: context,
      projectId: widget.projectId,
      projectName: widget.projectName,
      projectIdStr: projectIdStr,
      projectOrientation: projectOrientation,
      rawImageFiles: widget.imageFilesStr,
      listFilesInDirectory: GalleryExportHandler.listFilesInDirectory,
    );
  }

  Widget _buildImageTile(String imagePath) {
    final bool isRawPhoto = imagePath.contains(DirUtils.photosRawDirname);
    Widget tile;
    if (isRawPhoto) {
      tile = _buildRawThumbnail(imagePath);
    } else {
      tile = _buildStabilizedThumbnail(imagePath);
    }

    if (_isSelectionMode) {
      return _buildSelectableTile(imagePath, tile);
    }
    return tile;
  }

  Widget _buildSelectableTile(String imagePath, Widget tile) {
    final isSelected = _selectedPhotos.contains(imagePath);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedPhotos.remove(imagePath);
          } else {
            _selectedPhotos.add(imagePath);
          }
        });
      },
      child: Stack(
        children: [
          Positioned.fill(child: AbsorbPointer(child: tile)),
          if (isSelected)
            Positioned.fill(
              child: Container(color: AppColors.info.withValues(alpha: 0.3)),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.info
                    : AppColors.overlay.withValues(alpha: 0.54),
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                isSelected ? Icons.check : Icons.circle_outlined,
                color: AppColors.textPrimary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPhotos.clear();
    });
  }

  void _selectAllPhotos() {
    final bool isStabilizedTab = _tabController.index == 0;
    final List<String> currentFiles =
        isStabilizedTab ? widget.stabilizedImageFilesStr : widget.imageFilesStr;
    setState(() {
      if (_selectedPhotos.length == currentFiles.length) {
        _selectedPhotos.clear();
      } else {
        _selectedPhotos = currentFiles.toSet();
      }
    });
  }

  Widget _buildSelectionActionBar() {
    final bool isStabilizedTab = _tabController.index == 0;
    final List<String> currentFiles =
        isStabilizedTab ? widget.stabilizedImageFilesStr : widget.imageFilesStr;
    final bool allSelected = _selectedPhotos.length == currentFiles.length &&
        currentFiles.isNotEmpty;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _exitSelectionMode,
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Cancel'),
            ),
            const Spacer(),
            Text(
              '${_selectedPhotos.length} selected',
              style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.7),
                  fontSize: AppTypography.md),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                color: AppColors.textPrimary,
              ),
              tooltip: allSelected ? 'Deselect All' : 'Select All',
              onPressed: _selectAllPhotos,
            ),
            IconButton(
              icon: Icon(Icons.download, color: AppColors.textPrimary),
              tooltip: 'Export Selected',
              onPressed: _selectedPhotos.isEmpty ? null : _exportSelectedPhotos,
            ),
            IconButton(
              icon: Icon(
                Icons.delete,
                color: _selectedPhotos.isEmpty
                    ? AppColors.textSecondary
                    : AppColors.danger,
              ),
              tooltip: 'Delete Selected',
              onPressed: _selectedPhotos.isEmpty ? null : _deleteSelectedPhotos,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelectedPhotos() async {
    final int count = _selectedPhotos.length;
    final int totalPhotos = widget.imageFilesStr.length;
    final int remainingAfterDelete = totalPhotos - count;
    final bool shouldRecompile = remainingAfterDelete >= 2;

    final bool confirmed;
    if (shouldRecompile) {
      confirmed = await ConfirmActionDialog.showDeleteRecompile(
        context,
        photoCount: count,
      );
    } else {
      confirmed = await ConfirmActionDialog.showDeleteSimple(
        context,
        photoCount: count,
      );
    }

    if (!confirmed) return;

    setState(() => isImporting = true);

    int deleted = 0;
    int failed = 0;
    final List<String> photosToDelete = _selectedPhotos.toList();

    for (final imagePath in photosToDelete) {
      try {
        // For stabilized images, we need to get the raw path first
        final bool isStabilizedImage = imagePath.toLowerCase().contains(
              'stabilized',
            );
        File toDelete;
        if (isStabilizedImage) {
          final String timestamp = path.basenameWithoutExtension(imagePath);
          final String rawPhotoPath =
              await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
            timestamp,
            projectId,
          );
          toDelete = File(rawPhotoPath);
        } else {
          toDelete = File(imagePath);
        }

        final bool success = await ProjectUtils.deleteImage(
          toDelete,
          projectId,
        );
        if (success) {
          deleted++;
          // Clear thumbnail cache
          final String switched = toDelete.path.replaceAll(
            DirUtils.photosRawDirname,
            DirUtils.thumbnailDirname,
          );
          final String thumbnailPath = path.join(
            path.dirname(switched),
            "${path.basenameWithoutExtension(toDelete.path)}.jpg",
          );
          ThumbnailService.instance.clearCache(thumbnailPath);
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
        LogService.instance.log('Error deleting image: $e');
      }
    }

    await _loadImages();
    _exitSelectionMode();

    // Trigger video recompilation if photos were deleted and enough remain
    if (deleted > 0 && shouldRecompile) {
      await widget.recompileVideoCallback();
    }

    setState(() => isImporting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Deleted $deleted photo${deleted == 1 ? '' : 's'}'
                : 'Deleted $deleted, failed to delete $failed',
          ),
        ),
      );
    }
  }

  Future<void> _exportSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    // Categorize selected photos by type based on their path
    final List<String> selectedStabilized = [];
    final List<String> selectedRaw = [];

    for (final photoPath in _selectedPhotos) {
      if (photoPath.toLowerCase().contains('stabilized')) {
        selectedStabilized.add(photoPath);
      } else {
        selectedRaw.add(photoPath);
      }
    }

    final int stabCount = selectedStabilized.length;
    final int rawCount = selectedRaw.length;
    final int totalCount = stabCount + rawCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        bool localExportingToZip = false;
        bool exportSuccessful = false;
        double exportProgressPercent = 0;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            void setExportProgress(double exportProgressIn) {
              setState(() {
                exportProgressPercent = (exportProgressIn * 10).round() / 10;
              });
            }

            List<Widget> content = [
              if (!localExportingToZip && !exportSuccessful) ...[
                // Summary box
                Container(
                  padding: const EdgeInsets.all(14),
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.settingsAccent.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.photo_library_outlined,
                          color: AppColors.settingsAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalCount photo${totalCount == 1 ? '' : 's'} selected',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: AppTypography.lg,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (rawCount > 0) '$rawCount raw',
                                if (stabCount > 0) '$stabCount stabilized',
                              ].join(' • '),
                              style: TextStyle(
                                color: AppColors.textPrimary
                                    .withValues(alpha: 0.5),
                                fontSize: AppTypography.sm,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    setState(() {
                      localExportingToZip = true;
                    });

                    String? dateStampTempDir;
                    try {
                      Map<String, List<String>> filesToExport = {
                        'Raw': selectedRaw,
                        'Stabilized': [],
                      };

                      // Check if date stamp export is enabled for stabilized files
                      if (selectedStabilized.isNotEmpty) {
                        final dateStampEnabled =
                            await SettingsUtil.loadExportDateStampEnabled(
                          projectIdStr,
                        );

                        if (dateStampEnabled) {
                          // Load date stamp settings
                          final dateFormat =
                              await SettingsUtil.loadExportDateStampFormat(
                            projectIdStr,
                          );
                          final datePosition =
                              await SettingsUtil.loadExportDateStampPosition(
                            projectIdStr,
                          );
                          final dateSize =
                              await SettingsUtil.loadExportDateStampSize(
                            projectIdStr,
                          );
                          final dateOpacity =
                              await SettingsUtil.loadExportDateStampOpacity(
                            projectIdStr,
                          );

                          // Load watermark settings for overlap prevention
                          final watermarkEnabled =
                              await SettingsUtil.loadWatermarkSetting(
                            projectIdStr,
                          );
                          final String? watermarkPos = watermarkEnabled
                              ? (await DB.instance.getSettingValueByTitle(
                                  'watermark_position',
                                ))
                                  .toLowerCase()
                              : null;

                          // Load timezone offsets for accurate date stamps
                          final captureOffsetMap =
                              await CaptureTimezone.loadOffsetsForFiles(
                            selectedStabilized,
                            widget.projectId,
                          );

                          // Create temp directory for date-stamped files
                          final tempBase = await DirUtils.getTemporaryDirPath();
                          dateStampTempDir =
                              '$tempBase/date_stamp_export_${DateTime.now().millisecondsSinceEpoch}';

                          // Pre-process files with date stamps
                          final processedMap =
                              await DateStampUtils.processBatchWithDateStamps(
                            inputPaths: selectedStabilized,
                            tempDir: dateStampTempDir,
                            format: dateFormat,
                            position: datePosition,
                            sizePercent: dateSize,
                            opacity: dateOpacity,
                            captureOffsetMap: captureOffsetMap,
                            watermarkPosition: watermarkPos,
                            onProgress: (current, total) {
                              setExportProgress((current / total) * 30);
                            },
                          );

                          // Use processed files for export
                          filesToExport['Stabilized']!.addAll(
                            selectedStabilized.map(
                              (original) => processedMap[original] ?? original,
                            ),
                          );
                        } else {
                          filesToExport['Stabilized']!.addAll(
                            selectedStabilized,
                          );
                        }
                      }

                      // Adjust progress callback
                      void adjustedProgress(double p) {
                        if (dateStampTempDir != null) {
                          setExportProgress(30 + (p * 0.7));
                        } else {
                          setExportProgress(p);
                        }
                      }

                      String res = await GalleryUtils.exportZipFile(
                        widget.projectId,
                        widget.projectName,
                        filesToExport,
                        adjustedProgress,
                      );

                      if (res == 'success') {
                        setState(() => exportSuccessful = true);
                        if (Platform.isAndroid || Platform.isIOS) {
                          GalleryExportHandler.shareZipFile(
                            widget.projectId,
                            widget.projectName,
                          );
                        }
                      }
                    } catch (e) {
                      LogService.instance.log(e.toString());
                    } finally {
                      // Clean up temp directory
                      if (dateStampTempDir != null) {
                        try {
                          final dir = Directory(dateStampTempDir);
                          if (await dir.exists()) {
                            await dir.delete(recursive: true);
                          }
                        } catch (_) {}
                      }
                      setState(() => localExportingToZip = false);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.settingsAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Export to ZIP',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppTypography.lg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (localExportingToZip) ...[
                GalleryBottomSheets.buildExportProgressIndicator(
                    exportProgressPercent),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                GalleryBottomSheets.buildExportSuccessState(),
              ],
            ];

            return GalleryBottomSheets.buildOptionsSheet(
              context,
              'Export Selected',
              content,
            );
          },
        );
      },
    );
  }

  Future<void> _retryStabilization(String imagePath) async {
    final String timestamp = path.basenameWithoutExtension(imagePath);

    // Get paths first (before setState)
    final String rawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      widget.projectId,
    );
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final String stabilizedImagePath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      widget.projectId,
      rawPhotoPath,
      projectOrientation,
    );
    final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(
      stabilizedImagePath,
    );

    // Clear caches BEFORE deleting files
    ThumbnailService.instance.clearCache(stabThumbPath);

    // Evict specific images from Flutter's cache
    final stabImageProvider = FileImage(File(stabilizedImagePath));
    final stabThumbProvider = FileImage(File(stabThumbPath));
    stabImageProvider.evict();
    stabThumbProvider.evict();

    // Update state to show loader immediately
    setState(() {
      _retryingPhotoTimestamps.add(timestamp);
    });

    // Delete files
    final File stabImageFile = File(stabilizedImagePath);
    final File stabThumbFile = File(stabThumbPath);
    if (await stabImageFile.exists()) {
      await stabImageFile.delete();
    }
    if (await stabThumbFile.exists()) {
      await stabThumbFile.delete();
    }

    // Reset DB
    await DB.instance.resetStabilizedColumnByTimestamp(
      projectOrientation,
      timestamp,
      widget.projectId,
    );

    // Trigger re-stabilization
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Retrying stabilization...')));
    widget.stabCallback();
  }

  Future<void> _showImageOptionsMenu(File imageFile) async {
    final timestamp = path.basenameWithoutExtension(imageFile.path);
    await GalleryImageMenu.show(
      context: context,
      imageFile: imageFile,
      onChangeDate: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showChangeDateDialog(timestamp);
        });
      },
      onStabDiffFace: () {
        StabDiffFacePage stabNewFaceScreen = StabDiffFacePage(
          projectId: projectId,
          imageTimestamp: timestamp,
          reloadImagesInGallery: _loadImages,
          stabCallback: widget.stabCallback,
          userRanOutOfSpaceCallback: widget.userRanOutOfSpaceCallback,
          stabilizationRunningInMain: widget.stabilizingRunningInMain,
        );
        Utils.navigateToScreen(context, stabNewFaceScreen);
      },
      onRetryStab: () {
        Future.delayed(Duration.zero, () async {
          await _retryStabilization(imageFile.path);
        });
      },
      onSetGuidePhoto: () async {
        final photoRecord = await DB.instance.getPhotoByTimestamp(
          timestamp,
          projectId,
        );
        if (photoRecord != null) {
          await DB.instance.setSettingByTitle(
            "selected_guide_photo",
            photoRecord['id'].toString(),
            projectId.toString(),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Guide photo updated')),
          );
        }
      },
      onManualStab: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ManualStabilizationPage(
              imagePath: imageFile.path,
              projectId: widget.projectId,
              onSaveComplete: _loadImages,
            ),
          ),
        );
      },
      onDelete: () => _showDeleteDialog(imageFile),
    );
  }

  final Set<String> _retryingPhotoTimestamps = {};

  Widget _buildRawThumbnail(String filepath) =>
      _buildThumbnailInternal(filepath, isStabilized: false);

  Widget _buildStabilizedThumbnail(String filepath) =>
      _buildThumbnailInternal(filepath, isStabilized: true);

  Widget _buildThumbnailInternal(String filepath,
      {required bool isStabilized}) {
    final String timestamp = path.basenameWithoutExtension(filepath);

    // Show loading indicator for retrying stabilized photos
    if (isStabilized && _retryingPhotoTimestamps.contains(timestamp)) {
      return const FlashingBox();
    }

    // Compute thumbnail path based on photo type
    final String thumbnailPath;
    if (isStabilized) {
      thumbnailPath = FaceStabilizer.getStabThumbnailPath(filepath);
    } else {
      final String switched = filepath.replaceAll(
        DirUtils.photosRawDirname,
        DirUtils.thumbnailDirname,
      );
      thumbnailPath = path.join(path.dirname(switched), "$timestamp.jpg");
    }

    return GestureDetector(
      key: ValueKey('${isStabilized ? 'stab' : 'raw'}_$timestamp'),
      onTap: () =>
          _showImagePreviewDialog(File(filepath), isStabilized: isStabilized),
      onLongPress: () => _showImageOptionsMenu(File(filepath)),
      onSecondaryTap: () => _showImageOptionsMenu(File(filepath)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Widget thumbnail = isStabilized
              ? StabilizedThumbnail(
                  thumbnailPath: thumbnailPath, projectId: widget.projectId)
              : RawThumbnail(
                  thumbnailPath: thumbnailPath, projectId: widget.projectId);

          final config = GalleryDateStampProvider.of(context);
          final bool labelsEnabled = isStabilized
              ? config.stabilizedLabelsEnabled
              : config.rawLabelsEnabled;

          if (!labelsEnabled) {
            return thumbnail;
          }

          final int? timestampMs = int.tryParse(timestamp);
          if (timestampMs == null) {
            return thumbnail;
          }

          final String formattedDate = DateStampUtils.formatTimestamp(
            timestampMs,
            config.dateFormat,
            captureOffsetMinutes: config.captureOffsetMap[timestamp],
          );

          return Stack(
            children: [
              thumbnail,
              Positioned(
                right: 4,
                bottom: 4,
                child: DateStampUtils.buildGalleryDateLabel(
                  formattedDate,
                  constraints.maxHeight,
                  fontFamily: config.fontFamily,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImagePreviewDialog(File imageFile, {required bool isStabilized}) {
    final List<String> currentList =
        isStabilized ? widget.stabilizedImageFilesStr : widget.imageFilesStr;

    final int initialIndex = currentList.indexOf(imageFile.path);
    if (initialIndex < 0 || currentList.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImagePreviewNavigator(
          rawImageFiles: widget.imageFilesStr,
          stabilizedImageFiles: widget.stabilizedImageFilesStr,
          initialIndex: initialIndex,
          initialIsRaw: !isStabilized,
          projectId: widget.projectId,
          projectOrientation: projectOrientation ?? 'portrait',
          stabCallback: widget.stabCallback,
          userRanOutOfSpaceCallback: widget.userRanOutOfSpaceCallback,
          stabilizingRunningInMain: widget.stabilizingRunningInMain,
          loadImages: _loadImages,
          recompileVideoCallback: widget.recompileVideoCallback,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final int sdkInt = androidInfo.version.sdkInt;
      try {
        if (sdkInt >= 33) {
          PermissionStatus imagesStatus = await Permission.photos.request();
          PermissionStatus videosStatus = await Permission.videos.request();
          PermissionStatus audioStatus = await Permission.audio.request();
          if (imagesStatus.isGranted &&
              videosStatus.isGranted &&
              audioStatus.isGranted) {
            return;
          }
          if (imagesStatus.isPermanentlyDenied ||
              videosStatus.isPermanentlyDenied ||
              audioStatus.isPermanentlyDenied) {
            await openAppSettings();
          }
        } else {
          PermissionStatus storageStatus = await Permission.storage.request();
          if (storageStatus.isGranted) return;
          if (storageStatus.isPermanentlyDenied) {
            await openAppSettings();
          }
        }
      } catch (e) {
        LogService.instance.log('Error checking permissions: $e');
      }
    }
  }

  void showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Information'),
          content: const Text(
            "During stabilization, view the original photo in "
            "the 'Originals' tab or by tapping 'Raw' on the image preview.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteDialog(File image) async {
    final int totalPhotos = widget.imageFilesStr.length;
    final int remainingAfterDelete = totalPhotos - 1;
    final bool shouldRecompile = remainingAfterDelete >= 2;

    final bool confirmed;
    if (shouldRecompile) {
      confirmed = await ConfirmActionDialog.showDeleteRecompile(
        context,
        photoCount: 1,
      );
    } else {
      confirmed = await ConfirmActionDialog.showDeleteSimple(
        context,
        photoCount: 1,
      );
    }

    if (!confirmed || !mounted) return;

    File toDelete = image;
    final bool isStabilizedImage = image.path.toLowerCase().contains(
          "stabilized",
        );
    if (isStabilizedImage) {
      final String timestamp = path.basenameWithoutExtension(
        image.path,
      );
      final String rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
      );
      toDelete = File(rawPhotoPath);
    }
    await _deleteImage(toDelete, triggerRecompile: shouldRecompile);
  }

  Future<void> _deleteImage(File image,
      {required bool triggerRecompile}) async {
    final bool success = await ProjectUtils.deleteImage(image, projectId);
    if (success) {
      final String switched = image.path.replaceAll(
        DirUtils.photosRawDirname,
        DirUtils.thumbnailDirname,
      );
      final String thumbnailPath = path.join(
        path.dirname(switched),
        "${path.basenameWithoutExtension(image.path)}.jpg",
      );
      ThumbnailService.instance.clearCache(thumbnailPath);
      _loadImages();
      if (triggerRecompile) {
        await widget.recompileVideoCallback();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('There was an error. Please try again.'),
          ),
        );
      }
    }
  }
}
