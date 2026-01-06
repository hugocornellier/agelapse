import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/database_helper.dart';
import '../../services/log_service.dart';
import '../../services/face_stabilizer.dart';
import '../../services/settings_cache.dart';
import '../../services/stab_update_event.dart';
import '../../services/thumbnail_service.dart';
import '../../styles/styles.dart';
import '../../utils/project_utils.dart';
import '../../utils/camera_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/utils.dart';
import '../../widgets/yellow_tip_bar.dart';
import '../manual_stab_page.dart';
import '../stab_on_diff_face.dart';
import 'gallery_widgets.dart';

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
  final int progressPercent;
  final bool userOnImportTutorial;
  final void Function() setUserOnImportTutorialFalse;
  final void Function(int progressIn) setProgressInMain;
  final SettingsCache? settingsCache;
  final List<String> imageFilesStr;
  final List<String> stabilizedImageFilesStr;
  final void Function(
          List<String> imageFiles, List<String> stabilizedImageFiles)
      setRawAndStabPhotoStates;
  final Future<void> Function(FilePickerResult? pickedFiles,
          Future<void> Function(dynamic file) processFileCallback)
      processPickedFiles;
  final Future<void> Function() refreshSettings;
  final String minutesRemaining;
  final bool userRanOutOfSpace;
  final Stream<StabUpdateEvent>? stabUpdateStream;
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
    required this.processPickedFiles,
    required this.imageFilesStr,
    required this.stabilizedImageFilesStr,
    required this.setRawAndStabPhotoStates,
    required this.settingsCache,
    required this.refreshSettings,
    required this.minutesRemaining,
    this.stabUpdateStream,
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
  bool imagePreviewIsOpen = false;
  VoidCallback? closeImagePreviewCallback;
  ValueNotifier<String> activeProcessingDateNotifier =
      ValueNotifier<String>('');
  late bool showFlashingCircle;
  late int projectId;
  late String projectIdStr;
  bool importingDialogActive = false;
  VoidCallback? closeImportingDialog;
  int photosImported = 0, successfullyImported = 0;
  int gridAxisCount = int.parse(DB.defaultValues['gridAxisCount']!);
  double progress = 0;
  bool _isMounted = false;
  int _stabCount = 0;
  double _scale = 1.0;
  double _previousScale = 1.0;
  final ScrollController _stabilizedScrollController = ScrollController();
  final ScrollController _rawScrollController = ScrollController();
  StreamSubscription<StabUpdateEvent>? _stabUpdateSubscription;
  Timer? _loadImagesDebounce;
  bool _stickyBottomEnabled = true;
  bool _isAutoScrolling = false;
  bool _isSelectionMode = false;
  Set<String> _selectedPhotos = {};

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
    _stabilizedScrollController.addListener(_onStabilizedScroll);
    _tabController.addListener(_onTabChanged);
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
    DateTime initialDate =
        DateTime.fromMillisecondsSinceEpoch(int.parse(currentTimestamp));
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
    DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );
    String newTimestamp = newDateTime.millisecondsSinceEpoch.toString();
    await _changePhotoDate(currentTimestamp, newTimestamp);
  }

  Future<void> _saveImageToDownloadsOrGallery(XFile image) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final bytes = await image.readAsBytes();
      final downloadsPath = await _preferredUserDownloads();
      await _ensureDirExists(downloadsPath);
      final targetPath =
          await _uniquePath(downloadsPath, path.basename(image.path));
      try {
        await File(targetPath).writeAsBytes(bytes, flush: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to ${path.normalize(targetPath)}')),
          );
        }
      } on FileSystemException {
        final location =
            await getSaveLocation(suggestedName: path.basename(image.path));
        if (location != null && location.path.isNotEmpty) {
          await File(location.path).writeAsBytes(bytes, flush: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Saved to ${path.normalize(location.path)}')),
            );
          }
        } else {
          final docs = (await getApplicationDocumentsDirectory()).path;
          final fallback = await _uniquePath(docs, path.basename(image.path));
          await File(fallback).writeAsBytes(bytes, flush: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved to ${path.normalize(fallback)}')),
            );
          }
        }
      }
    } else {
      await checkAndRequestPermissions();
      await CameraUtils.saveToGallery(image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Photos')),
        );
      }
    }
  }

  Future<String> _preferredUserDownloads() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return path.join(home, 'Downloads');
      }
    }
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null) {
        final oneDriveDownloads = path.join(profile, 'OneDrive', 'Downloads');
        if (await Directory(oneDriveDownloads).exists()) {
          return oneDriveDownloads;
        }
        return path.join(profile, 'Downloads');
      }
    }
    final d = await getDownloadsDirectory();
    if (d != null) {
      return d.path;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _ensureDirExists(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<String> _uniquePath(String dir, String filename) async {
    final name = path.basenameWithoutExtension(filename);
    final ext = path.extension(filename);
    var candidate = path.join(dir, filename);
    var i = 1;
    // Batch check existence to avoid multiple sequential awaits
    // First check if original filename is available
    if (!await File(candidate).exists()) {
      return candidate;
    }
    // If not, find a unique name by listing existing files once
    final directory = Directory(dir);
    final existingFiles = <String>{};
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) {
          existingFiles.add(path.basename(entity.path));
        }
      }
    }
    // Now find unique name without additional I/O
    while (existingFiles.contains('$name ($i)$ext')) {
      i++;
    }
    return path.join(dir, '$name ($i)$ext');
  }

  Future<void> _changePhotoDate(
      String oldTimestamp, String newTimestamp) async {
    try {
      setState(() {
        isImporting = true;
      });
      String oldRawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
              oldTimestamp, projectId);
      File oldRawFile = File(oldRawPhotoPath);
      if (!await oldRawFile.exists()) {
        throw Exception('Original file not found');
      }
      String fileExtension = path.extension(oldRawPhotoPath);
      String newRawPhotoPath = path.join(
          path.dirname(oldRawPhotoPath), '$newTimestamp$fileExtension');
      await oldRawFile.rename(newRawPhotoPath);
      String oldRawThumbPath = oldRawPhotoPath.replaceAll(
          DirUtils.photosRawDirname, DirUtils.thumbnailDirname);
      oldRawThumbPath = path.join(path.dirname(oldRawThumbPath),
          "${path.basenameWithoutExtension(oldRawPhotoPath)}.jpg");
      File oldRawThumbFile = File(oldRawThumbPath);
      if (await oldRawThumbFile.exists()) {
        String newRawThumbPath =
            path.join(path.dirname(oldRawThumbPath), "$newTimestamp.jpg");
        await oldRawThumbFile.rename(newRawThumbPath);
      }
      List<String> orientations = ['portrait', 'landscape'];
      for (String orientation in orientations) {
        try {
          String oldStabPath = await DirUtils
              .getStabilizedImagePathFromRawPathAndProjectOrientation(
                  projectId, oldRawPhotoPath, orientation);
          File oldStabFile = File(oldStabPath);
          if (await oldStabFile.exists()) {
            String newStabPath =
                path.join(path.dirname(oldStabPath), '$newTimestamp.png');
            await oldStabFile.rename(newStabPath);
            String oldStabThumbPath =
                FaceStabilizer.getStabThumbnailPath(oldStabPath);
            File oldStabThumbFile = File(oldStabThumbPath);
            if (await oldStabThumbFile.exists()) {
              String newStabThumbPath =
                  FaceStabilizer.getStabThumbnailPath(newStabPath);
              await DirUtils.createDirectoryIfNotExists(newStabThumbPath);
              await oldStabThumbFile.rename(newStabThumbPath);
            }
          }
        } catch (e) {
          LogService.instance
              .log('No stabilized file found for $orientation: $e');
        }
      }
      final oldPhotoRecord =
          await DB.instance.getPhotoByTimestamp(oldTimestamp, projectId);
      if (oldPhotoRecord == null) return;
      final int oldId = oldPhotoRecord['id'] as int;
      int? newId = await DB.instance
          .updatePhotoTimestamp(oldTimestamp, newTimestamp, projectId);
      final String currentGuidePhoto =
          await SettingsUtil.loadSelectedGuidePhoto(projectId.toString());
      if (currentGuidePhoto == oldId.toString() && newId != null) {
        await DB.instance.setSettingByTitle(
            "selected_guide_photo", newId.toString(), projectId.toString());
      }
      final int newTsInt = int.parse(newTimestamp);
      final int newOffsetMin =
          DateTime.fromMillisecondsSinceEpoch(newTsInt, isUtc: true)
              .toLocal()
              .timeZoneOffset
              .inMinutes;
      await DB.instance.setCaptureOffsetMinutesByTimestamp(
          newTimestamp, projectId, newOffsetMin);
      await _loadImages();
      await DB.instance.setNewVideoNeeded(projectId);
    } catch (e) {
      LogService.instance.log('Error changing photo date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to change photo date: $e')));
    } finally {
      setState(() {
        isImporting = false;
      });
    }
  }

  Future<void> _loadImages() async {
    await GalleryUtils.loadImages(
      projectId: projectId,
      projectIdStr: projectIdStr,
      onImagesLoaded: (rawImages, stabImageFiles) async {
        widget.setRawAndStabPhotoStates(rawImages, stabImageFiles);
        _retryingPhotoTimestamps.clear();
      },
      onShowInfoDialog: () => showInfoDialog(context),
    );

    if (_stickyBottomEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoScroll();
      });
    }
  }

  List<File> cloneList(List list) => List.from(list);
  Future<void> _init() async {
    final String projectOrientationRaw =
        await SettingsUtil.loadProjectOrientation(projectIdStr);
    final int gridAxisCountRaw =
        await SettingsUtil.loadGridAxisCount(projectIdStr);
    setState(() {
      gridAxisCount = gridAxisCountRaw;
      projectOrientation = projectOrientationRaw;
    });
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
    final newPath = await DirUtils.getStabilizedImagePathFromTimestamp(
        projectId, timestamp, projectOrientation!);

    // Check if already in list (avoid duplicates)
    final currentList = widget.stabilizedImageFilesStr;
    if (currentList.contains(newPath)) return;

    final newList = List<String>.from(currentList);
    int low = 0;
    int high = newList.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final midTimestamp = path.basenameWithoutExtension(newList[mid]);
      if (midTimestamp.compareTo(timestamp) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    newList.insert(low, newPath);
    widget.setRawAndStabPhotoStates(widget.imageFilesStr, newList);

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
    final String tempOriginPhotoPath =
        await _getTemporaryPhotoPath(asset, originPath);
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
      AssetEntity asset, String originPath) async {
    final String basename = path
        .basenameWithoutExtension(originPath)
        .toLowerCase()
        .replaceAll(".", "");
    final String extension = path.extension(originPath).toLowerCase();
    final String tempDir = await DirUtils.getTemporaryDirPath();
    return path.join(tempDir, "$basename$extension");
  }

  Future<bool> _isModifiedLivePhoto(
      AssetEntity asset, String originPath) async {
    final String extension = path.extension(originPath).toLowerCase();
    return asset.isLivePhoto && (extension == ".jpg" || extension == ".jpeg");
  }

  Future<void> _writeModifiedLivePhoto(
      AssetEntity asset, File tempOriginFile) async {
    File? assetFile = await asset.file;
    var bytes = await assetFile?.readAsBytes();
    if (bytes != null) {
      await tempOriginFile.writeAsBytes(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGrey,
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
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20.0),
                          padding: EdgeInsets.zero,
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
                            const PopupMenuItem(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.upload, size: 20),
                                  SizedBox(width: 12),
                                  Text('Import'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 20),
                                  SizedBox(width: 12),
                                  Text('Export'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'select',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 20),
                                  SizedBox(width: 12),
                                  Text('Select'),
                                ],
                              ),
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
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return _buildTabBarContainer();
  }

  Widget _buildTabBarContainer() {
    return Padding(
      padding: const EdgeInsets.only(top: 0.0),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Stabilized'),
          Tab(text: 'Raw'),
        ],
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.lightBlue,
        labelColor: AppColors.lightBlue,
        unselectedLabelColor: Colors.grey,
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
                widget.stabilizedImageFilesStr, _stabilizedScrollController),
            if (!_stickyBottomEnabled && !_hasNoScrollbar())
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottomAndReenableSticky,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.arrow_downward, size: 20),
                ),
              ),
          ],
        ),
        _buildImageGrid(widget.imageFilesStr, _rawScrollController),
      ],
    );
  }

  Widget _buildImageGrid(
      List<String> imageFiles, ScrollController scrollController) {
    if (widget.stabilizedImageFilesStr.isEmpty &&
        widget.imageFilesStr.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
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
    final int itemCount = isStabilizedTab && widget.stabilizingRunningInMain
        ? files.length + 1
        : files.length;
    return GridView.builder(
      padding: EdgeInsets.zero,
      controller: scrollController,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tileExtentForGridCount(context),
        crossAxisSpacing: 2.0,
        mainAxisSpacing: 2.0,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (isStabilizedTab &&
            index == widget.stabilizedImageFilesStr.length &&
            widget.stabilizingRunningInMain) {
          return const FlashingBox();
        } else {
          return _buildImageTile(files[index]);
        }
      },
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
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.settingsAccent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Importing...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.progressPercent}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  double _tileExtentForGridCount(BuildContext context) {
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    if (isDesktop) {
      const List<double> steps = [
        480,
        360,
        280,
        220,
        180,
        160,
        140,
        120,
        110,
        100,
        90,
        80
      ];
      final int idx = gridAxisCount.clamp(1, steps.length) - 1;
      return steps[idx];
    } else {
      final double width = MediaQuery.of(context).size.width;
      return width / gridAxisCount;
    }
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
        pickedFiles = await FilePicker.platform.pickFiles(allowMultiple: true);
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
          successfullyImported, photosImported - successfullyImported);
    } catch (e) {
      LogService.instance.log("ERROR CAUGHT IN PICK FILES");
    }
  }

  Future<void> processPickedFile(dynamic file) async {
    await GalleryUtils.processPickedFile(
        file, projectId, activeProcessingDateNotifier,
        onImagesLoaded: _loadImages,
        setProgressInMain: widget.setProgressInMain,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        increasePhotosImported: increasePhotosImported);
  }

  void _showImportCompleteDialog(int imported, int skipped) {
    if (importingDialogActive) {
      closeImportingDialog!();
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        void closeMe() => Navigator.of(context).pop();
        return AlertDialog(
          title: const Text('Import Complete'),
          content:
              Text('Imported: $imported\nSkipped (Already Imported): $skipped'),
          actions: [
            TextButton(
              onPressed: () => closeMe(),
              child: const Text('OK'),
            ),
          ],
        );
      },
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

  Widget _buildOptionsBottomSheet(
      BuildContext context, String title, List<Widget> content) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0),
      decoration: const BoxDecoration(
        color: Color(0xff1a1a1a),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.close, color: Colors.white70, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...content,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildImportOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.3), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOptionToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!isSelected),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.settingsAccent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.settingsAccent.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.settingsAccent : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color:
                    isSelected ? AppColors.settingsAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? AppColors.settingsAccent
                      : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showImportOptionsBottomSheet(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final List<Widget> content = [
      if (isMobile) ...[
        _buildImportOptionTile(
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
      _buildImportOptionTile(
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
      if (isDesktop) ...[
        const SizedBox(height: 16),
        _buildDesktopDropZone(),
      ],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _buildOptionsBottomSheet(context, 'Import Photos', content);
      },
    );
  }

  Widget _buildDesktopDropZone() {
    return DropTarget(
      onDragDone: (details) async {
        if (isImporting) return;
        Navigator.of(context).pop();
        setState(() {
          photosImported = 0;
          successfullyImported = 0;
          _tabController.index = 1;
          isImporting = true;
        });
        if (widget.stabilizingRunningInMain) {
          await widget.cancelStabCallback();
        }
        GalleryUtils.startImportBatch(details.files.length);
        for (final f in details.files) {
          await processPickedFile(File(f.path));
        }
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
            successfullyImported, photosImported - successfullyImported);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.upload_file_outlined,
                size: 26,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Drop files here',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'or drag and drop images',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportOptionsBottomSheet(BuildContext context) {
    bool exportRawFiles = true;
    bool exportStabilizedFiles = false;
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
                _buildExportOptionToggle(
                  icon: Icons.image_outlined,
                  title: 'Raw Photos',
                  subtitle: 'Original unprocessed images',
                  isSelected: exportRawFiles,
                  onChanged: (value) => setState(() => exportRawFiles = value),
                ),
                const SizedBox(height: 10),
                _buildExportOptionToggle(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Stabilized Photos',
                  subtitle: 'Face-aligned processed images',
                  isSelected: exportStabilizedFiles,
                  onChanged: (value) =>
                      setState(() => exportStabilizedFiles = value),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    if (!exportRawFiles && !exportStabilizedFiles) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please select at least one type of files to export')),
                      );
                      return;
                    }
                    setState(() {
                      localExportingToZip = true;
                    });
                    try {
                      Map<String, List<String>> filesToExport = {
                        'Raw': [],
                        'Stabilized': []
                      };
                      if (exportRawFiles) {
                        filesToExport['Raw']!.addAll(widget.imageFilesStr);
                      }
                      if (exportStabilizedFiles) {
                        String stabilizedDir = await DirUtils
                            .getStabilizedDirPathFromProjectIdAndOrientation(
                                widget.projectId, projectOrientation!);
                        List<String> stabilizedFiles =
                            await listFilesInDirectory(stabilizedDir);
                        filesToExport['Stabilized']!.addAll(stabilizedFiles);
                      }
                      String res = await GalleryUtils.exportZipFile(
                          widget.projectId,
                          widget.projectName,
                          filesToExport,
                          setExportProgress);
                      if (res == 'success') {
                        setState(() => exportSuccessful = true);
                        if (Platform.isAndroid || Platform.isIOS) {
                          _shareZipFile();
                        }
                      }
                    } catch (e) {
                      LogService.instance.log(e.toString());
                    } finally {
                      setState(() => localExportingToZip = false);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: (exportRawFiles || exportStabilizedFiles)
                          ? AppColors.settingsAccent
                          : AppColors.settingsAccent.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Export to ZIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (localExportingToZip) ...[
                _buildExportProgressIndicator(exportProgressPercent),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                _buildExportSuccessState(),
              ],
            ];
            return _buildOptionsBottomSheet(context, 'Export Photos', content);
          },
        );
      },
    );
  }

  Widget _buildExportProgressIndicator(double progressPercent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.settingsAccent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exporting...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progressPercent%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSuccessState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xff4CD964).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Color(0xff4CD964),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Export Complete!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your photos have been exported to a ZIP file',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _shareZipFile() async {
    String zipFileExportPath = await DirUtils.getZipFileExportPath(
        widget.projectId, widget.projectName);
    final params = ShareParams(files: [XFile(zipFileExportPath)]);
    final result = await SharePlus.instance.share(params);
    if (result.status == ShareResultStatus.success) {
      // LogService.instance.log('Share success.');
    }
  }

  static Future<List<String>> listFilesInDirectory(String dirPath) async {
    Directory directory = Directory(dirPath);
    List<String> filePaths = [];
    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is File) {
          filePaths.add(file.path);
        }
      }
    }
    return filePaths;
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
              child: Container(
                color: Colors.blue.withValues(alpha: 0.3),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.blue : Colors.black54,
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                isSelected ? Icons.check : Icons.circle_outlined,
                color: Colors.white,
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
      color: const Color(0xff1e1e1e),
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
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                color: Colors.white,
              ),
              tooltip: allSelected ? 'Deselect All' : 'Select All',
              onPressed: _selectAllPhotos,
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              tooltip: 'Export Selected',
              onPressed: _selectedPhotos.isEmpty ? null : _exportSelectedPhotos,
            ),
            IconButton(
              icon: Icon(
                Icons.delete,
                color: _selectedPhotos.isEmpty ? Colors.grey : Colors.red,
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photos?'),
        content: Text(
          'Are you sure you want to delete $count photo${count == 1 ? '' : 's'}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isImporting = true);

    int deleted = 0;
    int failed = 0;
    final List<String> photosToDelete = _selectedPhotos.toList();

    for (final imagePath in photosToDelete) {
      try {
        // For stabilized images, we need to get the raw path first
        final bool isStabilizedImage =
            imagePath.toLowerCase().contains('stabilized');
        File toDelete;
        if (isStabilizedImage) {
          final String timestamp = path.basenameWithoutExtension(imagePath);
          final String rawPhotoPath =
              await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
                  timestamp, projectId);
          toDelete = File(rawPhotoPath);
        } else {
          toDelete = File(imagePath);
        }

        final bool success =
            await ProjectUtils.deleteImage(toDelete, projectId);
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
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              AppColors.settingsAccent.withValues(alpha: 0.2),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
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
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
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
                    try {
                      Map<String, List<String>> filesToExport = {
                        'Raw': selectedRaw,
                        'Stabilized': selectedStabilized,
                      };

                      String res = await GalleryUtils.exportZipFile(
                        widget.projectId,
                        widget.projectName,
                        filesToExport,
                        setExportProgress,
                      );

                      if (res == 'success') {
                        setState(() => exportSuccessful = true);
                        if (Platform.isAndroid || Platform.isIOS) {
                          _shareZipFile();
                        }
                      }
                    } catch (e) {
                      LogService.instance.log(e.toString());
                    } finally {
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
                    child: const Center(
                      child: Text(
                        'Export to ZIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (localExportingToZip) ...[
                _buildExportProgressIndicator(exportProgressPercent),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                _buildExportSuccessState(),
              ],
            ];

            return _buildOptionsBottomSheet(
              context,
              'Export Selected',
              content,
            );
          },
        );
      },
    );
  }

  Future<void> _retryStabilization() async {
    if (activeImagePreviewPath == null) return;
    final String timestamp =
        path.basenameWithoutExtension(activeImagePreviewPath!);
    _retryingPhotoTimestamps.add(timestamp);
    final String rawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
            timestamp, widget.projectId);
    final String projectOrientation =
        await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final String stabilizedImagePath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
            widget.projectId, rawPhotoPath, projectOrientation);
    final String stabThumbPath =
        FaceStabilizer.getStabThumbnailPath(stabilizedImagePath);
    final File stabImageFile = File(stabilizedImagePath);
    final File stabThumbFile = File(stabThumbPath);
    if (await stabImageFile.exists()) {
      await stabImageFile.delete();
    }
    if (await stabThumbFile.exists()) {
      await stabThumbFile.delete();
    }
    await DB.instance
        .resetStabilizedColumnByTimestamp(projectOrientation, timestamp);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Retrying stabilization...')));
    widget.stabCallback(); // Navigator.of(context).pop();
  }

  Future<void> _showImageOptionsMenu(File imageFile) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xff121212),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.calendar_today,
                    color: Colors.white.withAlpha(204), size: 18.0),
                title: const Text('Change Date',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showChangeDateDialog(
                        path.basenameWithoutExtension(imageFile.path));
                  });
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.video_stable,
                    color: Colors.white.withAlpha(150), size: 18.0),
                title: const Text('Stabilize on Other Faces',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  StabDiffFacePage stabNewFaceScreen = StabDiffFacePage(
                      projectId: projectId,
                      imageTimestamp:
                          path.basenameWithoutExtension(imageFile.path),
                      reloadImagesInGallery: _loadImages,
                      stabCallback: widget.stabCallback,
                      userRanOutOfSpaceCallback:
                          widget.userRanOutOfSpaceCallback,
                      stabilizationRunningInMain:
                          widget.stabilizingRunningInMain);
                  Utils.navigateToScreenReplace(context, stabNewFaceScreen);
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.refresh,
                    color: Colors.white.withAlpha(150), size: 18.0),
                title: const Text('Retry Stabilization',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  Future.delayed(Duration.zero, () async {
                    await _retryStabilization();
                  });
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.photo,
                    color: Colors.white.withAlpha(150), size: 18.0),
                title: const Text('Set as Guide Photo',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () async {
                  Navigator.of(context).pop();
                  final photoRecord = await DB.instance.getPhotoByTimestamp(
                      path.basenameWithoutExtension(imageFile.path), projectId);
                  if (photoRecord != null) {
                    await DB.instance.setSettingByTitle("selected_guide_photo",
                        photoRecord['id'].toString(), projectId.toString());
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Guide photo updated')));
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.handyman,
                    color: Colors.white.withAlpha(150), size: 18.0),
                title: const Text('Manual Stabilization',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManualStabilizationPage(
                        imagePath: imageFile.path,
                        projectId: widget.projectId,
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.delete,
                    color: Colors.red.withAlpha(204), size: 18.0),
                title: const Text('Delete Image',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showDeleteDialog(imageFile);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumbnailContent({
    required Widget imageWidget,
    required String filepath,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Stack(
        children: [imageWidget],
      ),
    );
  }

  Widget _buildRawThumbnail(String filepath) {
    final String switched = filepath.replaceAll(
      DirUtils.photosRawDirname,
      DirUtils.thumbnailDirname,
    );
    final String thumbnailPath = path.join(
      path.dirname(switched),
      "${path.basenameWithoutExtension(filepath)}.jpg",
    );
    return _buildThumbnailContent(
      imageWidget: RawThumbnail(
        thumbnailPath: thumbnailPath,
        projectId: widget.projectId,
      ),
      filepath: filepath,
      onTap: () => _showImagePreviewDialog(File(filepath), isStabilized: false),
      onLongPress: () => _showImageOptionsMenu(File(filepath)),
    );
  }

  final Set<String> _retryingPhotoTimestamps = {};
  Future<Map<String, dynamic>?>? _previewPhotoFuture;

  Widget _buildStabilizedThumbnail(String filepath) {
    final String timestamp = path.basenameWithoutExtension(filepath);
    if (_retryingPhotoTimestamps.contains(timestamp)) {
      return const FlashingBox();
    }
    final String thumbnailPath = FaceStabilizer.getStabThumbnailPath(filepath);
    return GestureDetector(
      onTap: () => _showImagePreviewDialog(File(filepath), isStabilized: true),
      onLongPress: () => _showImageOptionsMenu(File(filepath)),
      onSecondaryTap: () => _showImageOptionsMenu(File(filepath)),
      child: StabilizedThumbnail(
          thumbnailPath: thumbnailPath, projectId: widget.projectId),
    );
  }

  Future<void> _showDialog(BuildContext context, Widget dialog) async {
    showDialog(
      context: context,
      builder: (BuildContext context) => dialog,
    );
  }

  Future<ui.Image> _getImageDimensions(File imageFile) async {
    final Uint8List bytes = await imageFile.readAsBytes();
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<void> _showImagePreviewDialog(File imageFile,
      {required bool isStabilized}) async {
    final String timestamp = path.basenameWithoutExtension(imageFile.path);
    final bool isRaw = !isStabilized;

    // Cache the future once before opening dialog to prevent recreation on rebuilds
    _previewPhotoFuture = DB.instance.getPhotoByTimestamp(timestamp, projectId);

    setState(() {
      activeImagePreviewPath = imageFile.path;
      activeButton = isRaw ? 'raw' : projectOrientation!.toLowerCase();
      imagePreviewIsOpen = true;
    });
    _showDialog(
      context,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Dialog(
            backgroundColor: const Color(0xff121212),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: const Color(0xff121212),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 0.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const Icon(Icons.access_time_outlined),
                      const SizedBox(width: 8),
                      FutureBuilder<Map<String, dynamic>?>(
                        future: _previewPhotoFuture,
                        builder: (context, snap) {
                          final int? off = snap.data != null &&
                                  snap.data!['captureOffsetMinutes'] is int
                              ? snap.data!['captureOffsetMinutes'] as int
                              : null;
                          return Text(
                            Utils.formatUnixTimestampPlatformAware(
                                int.parse(timestamp),
                                captureOffsetMinutes: off),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      FutureBuilder<ui.Image>(
                        future: _getImageDimensions(imageFile),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          return Text(
                            '${snap.data!.width}x${snap.data!.height}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                      Expanded(child: Container()),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() => imagePreviewIsOpen = false);
                        },
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: _buildImagePreview(setState, imageFile, isStabilized),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImagePreview(
      StateSetter dialogSetState, File imageFile, bool isStabilized) {
    return activeImagePreviewPath != null
        ? Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStabilized && activeButton != 'raw')
                  StabilizedImagePreview(
                    thumbnailPath:
                        FaceStabilizer.getStabThumbnailPath(imageFile.path),
                    imagePath: activeImagePreviewPath!,
                    projectId: widget.projectId,
                    buildImage: _buildResizableImage,
                  )
                else
                  _buildResizableImage(File(activeImagePreviewPath!)),
                _buildActionBar(dialogSetState, imageFile),
              ],
            ),
          )
        : Container();
  }

  Widget _buildResizableImage(File imageFile) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(color: Colors.black),
      ),
    );
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async {
    return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp, projectId);
  }

  Widget _buildActionBar(StateSetter dialogSetState, File imageFile) {
    const double iconSize = 20.0;
    final String timestamp =
        path.basenameWithoutExtension(activeImagePreviewPath!);
    Future<String> getRawPhotoPathFromTimestamp(String timestamp) async {
      return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          timestamp, projectId);
    }

    Future<void> showRawImage(StateSetter dialogSetState) async {
      String rawPhotoPath = await getRawPhotoPathFromTimestamp(timestamp);
      if (await File(rawPhotoPath).exists()) {
        dialogSetState(() {
          activeImagePreviewPath = rawPhotoPath;
          activeButton = 'raw';
        });
        setState(() {
          activeImagePreviewPath = rawPhotoPath;
          activeButton = 'raw';
        });
      }
    }

    Future<void> updateImagePreviewPath(StateSetter dialogSetState,
        Future<String> Function() getPathFunction, String buttonType) async {
      String newPath = await getPathFunction();
      dialogSetState(() {
        activeImagePreviewPath = newPath;
        activeButton = buttonType;
      });
      setState(() {
        activeImagePreviewPath = newPath;
        activeButton = buttonType;
      });
    }

    Widget buildMoreOptionsButton(BuildContext context) {
      return IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        iconSize: iconSize,
        onPressed: () async {
          if (activeImagePreviewPath != null) {
            await _showImageOptionsMenu(File(activeImagePreviewPath!));
          }
        },
      );
    }

    return Container(
      color: const Color(0xff121212),
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildDownloadButton(),
          projectOrientation == 'portrait'
              ? _buildActionButton(
                  icon: Icons.video_stable,
                  active: activeButton == 'portrait',
                  onPressed: () => updateImagePreviewPath(
                    dialogSetState,
                    () => DirUtils.getStabilizedPortraitImagePathFromRawPath(
                        activeImagePreviewPath!, projectId),
                    'portrait',
                  ),
                )
              : _buildActionButton(
                  icon: Icons.video_stable,
                  active: activeButton == 'landscape',
                  onPressed: () => updateImagePreviewPath(
                    dialogSetState,
                    () => DirUtils.getStabilizedLandscapeImagePathFromRawPath(
                        activeImagePreviewPath!, projectId),
                    'landscape',
                  ),
                ),
          IconButton(
            icon: Icon(Icons.raw_on,
                color: activeButton == 'raw' ? Colors.blue : Colors.white),
            iconSize: 25.0,
            onPressed: () => showRawImage(dialogSetState),
          ),
          Builder(
            builder: (BuildContext context) {
              return buildMoreOptionsButton(context);
            },
          ),
        ],
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

  Widget _buildDownloadButton() {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        return IconButton(
          iconSize: 20.0,
          icon: gallerySaveIsLoading
              ? const Icon(Icons.hourglass_top, color: Colors.white)
              : (gallerySaveSuccessful
                  ? const Icon(Icons.check, color: Colors.greenAccent)
                  : const Icon(Icons.download, color: Colors.white)),
          onPressed: () async {
            try {
              setState(() => gallerySaveIsLoading = true);
              final XFile image = XFile(activeImagePreviewPath!);
              await _saveImageToDownloadsOrGallery(image);
              setState(() {
                gallerySaveIsLoading = false;
                gallerySaveSuccessful = true;
              });
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) setState(() => gallerySaveSuccessful = false);
            } catch (e) {
              setState(() => gallerySaveIsLoading = false);
            }
          },
        );
      },
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required VoidCallback onPressed,
      bool active = false,
      double iconSize = 20.0}) {
    return IconButton(
      icon: Icon(icon, color: active ? Colors.blue : Colors.white),
      iconSize: iconSize,
      onPressed: onPressed,
    );
  }

  void showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Information'),
          content: const Text(
              "During stabilization, view the original photo in "
              "the 'Originals' tab or by tapping 'Raw' on the image preview."),
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
    _showDialog(
        context,
        AlertDialog(
          title: const Text('Delete Image?'),
          content: const Text('Do you want to delete this image?'),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () async {
                Navigator.of(context).pop();
                File toDelete = image;
                final bool isStabilizedImage =
                    image.path.toLowerCase().contains("stabilized");
                if (isStabilizedImage) {
                  final String timestamp =
                      path.basenameWithoutExtension(image.path);
                  final String rawPhotoPath =
                      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
                          timestamp, projectId);
                  toDelete = File(rawPhotoPath);
                }
                await _deleteImage(toDelete);
              },
            ),
          ],
        ));
  }

  Future<void> _deleteImage(File image) async {
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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('There was an error. Please try again.')),
        );
      }
    }
  }
}
