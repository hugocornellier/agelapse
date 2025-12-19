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
import '../../services/face_stabilizer.dart';
import '../../services/settings_cache.dart';
import '../../styles/styles.dart';
import '../../utils/project_utils.dart';
import '../../utils/camera_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/utils.dart';
import '../../widgets/progress_widget.dart';
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
  final void Function() refreshSettings;
  final String minutesRemaining;
  final bool userRanOutOfSpace;
  final Stream<int>? stabUpdateStream;
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
  StreamSubscription<int>? _stabUpdateSubscription;
  Timer? _loadImagesDebounce;
  bool _stickyBottomEnabled = true;
  bool _isAutoScrolling = false;

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
    while (widget.settingsCache == null) {
      await Future.delayed(const Duration(seconds: 1));
    }
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
          print('No stabilized file found for $orientation: $e');
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
      print('Error changing photo date: $e');
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
      _showImportOptionsBottomSheet(context);
    }

    // Subscribe to stabilization updates from MainNavigation instead of polling.
    // This eliminates the 2-second polling loop that was causing unnecessary
    // database queries and potential UI blocking.
    if (widget.stabUpdateStream != null) {
      _stabUpdateSubscription = widget.stabUpdateStream!.listen((newCount) {
        if (!_isMounted) return;
        if (newCount != _stabCount) {
          _stabCount = newCount;
          // Debounce: cancel pending reload, schedule new one after 500ms
          // This prevents O(n²) DB queries when stabilizing many photos
          _loadImagesDebounce?.cancel();
          _loadImagesDebounce = Timer(const Duration(milliseconds: 500), () {
            if (_isMounted) _loadImages();
          });
        }
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
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 100,
          requestType: RequestType.image,
        ),
      );
      if (result == null)
        return; // for reference this means switching to the raw tab in the gallery
      setState(() {
        _tabController.index = 1;
      });
      GalleryUtils.startImportBatch(result.length);
      for (final AssetEntity asset in result) {
        await _processAsset(asset);
        _loadImages();
      }
      widget.refreshSettings();
      _loadImages();
      widget.stabCallback();
    } catch (e) {
      print("Error picking images: $e");
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
                  Positioned(
                    top: 7,
                    right: 8,
                    child: Row(
                      children: [
                        RawMaterialButton(
                          onPressed: () =>
                              _showExportOptionsBottomSheet(context),
                          elevation: 2.0,
                          fillColor: Theme.of(context).primaryColor,
                          constraints: const BoxConstraints.tightFor(
                              width: 44, height: 44),
                          shape: const CircleBorder(),
                          child: const Icon(Icons.download, size: 20.0),
                        ),
                        const SizedBox(width: 12),
                        RawMaterialButton(
                          onPressed: isImporting
                              ? _showImportingDialog
                              : () => _showImportOptionsBottomSheet(context),
                          elevation: 2.0,
                          fillColor: Theme.of(context).primaryColor,
                          constraints: const BoxConstraints.tightFor(
                              width: 44, height: 44),
                          shape: const CircleBorder(),
                          child: const Icon(Icons.upload, size: 20.0),
                        ),
                      ],
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

  Widget _buildFloatingActionButton(
    BuildContext context, {
    required double right,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Positioned(
      top: 7,
      right: right,
      child: Opacity(
        opacity: widget.imageFilesStr.length > 2 ? 0.85 : 1,
        child: RawMaterialButton(
          onPressed: onPressed,
          elevation: 2.0,
          fillColor: Theme.of(context).primaryColor,
          padding: const EdgeInsets.all(10.0),
          shape: const CircleBorder(),
          child: Icon(
            icon,
            size: 20.0,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        ProgressWidget(
          stabilizingRunningInMain: widget.stabilizingRunningInMain,
          videoCreationActiveInMain: widget.videoCreationActiveInMain,
          progressPercent: widget.progressPercent,
          goToPage: widget.goToPage,
          importRunningInMain: widget.importRunningInMain,
          selectedIndex: -1,
          minutesRemaining: widget.minutesRemaining,
          userRanOutOfSpace: widget.userRanOutOfSpace,
        ),
        _buildTabBarContainer(),
      ],
    );
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Importing..."),
          const SizedBox(height: 8.0),
          const CircularProgressIndicator(),
          const SizedBox(height: 8.0),
          Text("${widget.progressPercent}%"),
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
        print(e);
        return;
      }
      if (pickedFiles == null) return;
      setState(() => isImporting = true);
      if (widget.stabilizingRunningInMain) {
        widget.cancelStabCallback();
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
      print("ERROR CAUGHT IN PICK FILES");
    }
  }

  Future<void> processPickedFile(file) async {
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
      padding: const EdgeInsets.all(16.0),
      height: MediaQuery.of(context).size.height * 0.6,
      width: MediaQuery.of(context).size.width,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: content,
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
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
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

  void _showImportOptionsBottomSheet(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final String filesLabel = isDesktop ? 'Browse Files' : 'Import from Files';
    final List<Widget> content = [
      if (isMobile)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_library),
            title: const Text('Import from Gallery'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: isImporting
                ? null
                : () {
                    Navigator.of(context).pop();
                    try {
                      _pickFromGallery();
                    } catch (e) {
                      print(e);
                    }
                  },
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_open),
          title: Text(filesLabel),
          trailing: const Icon(Icons.arrow_forward_ios),
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
      ),
      if (isDesktop)
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: _buildDesktopDropZone(),
        ),
    ];
    showModalBottomSheet(
      context: context,
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
          widget.cancelStabCallback();
        }
        GalleryUtils.startImportBatch(details.files.length);
        for (final f in details.files) {
          await processPickedFile(File(f.path));
          _loadImages();
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
      child: CustomPaint(
        foregroundPainter: _DashedRectPainter(
          color: Colors.white24,
          strokeWidth: 2,
          dash: 8,
          gap: 6,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.file_upload_outlined, size: 28),
              SizedBox(height: 8),
              Text('Drop files here to import'),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportOptionsBottomSheet(BuildContext context) {
    bool exportRawFiles = true;
    bool exportStabilizedFiles = false;
    showModalBottomSheet(
      context: context,
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
                CheckboxListTile(
                  title: const Text('Raw Image Files'),
                  value: exportRawFiles,
                  onChanged: (bool? value) {
                    setState(() {
                      exportRawFiles = value ?? false;
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Stabilized Image Files'),
                  value: exportStabilizedFiles,
                  onChanged: (bool? value) {
                    setState(() {
                      exportStabilizedFiles = value ?? false;
                    });
                  },
                ),
                const SizedBox(
                  height: 24,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: FractionallySizedBox(
                    widthFactor: 1.0,
                    child: ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          localExportingToZip = true;
                        });
                        if (!exportRawFiles && !exportStabilizedFiles) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please select at least one type of files to export')),
                          );
                          return;
                        }
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
                            filesToExport['Stabilized']!
                                .addAll(stabilizedFiles);
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
                          print(e);
                        } finally {
                          setState(() => localExportingToZip = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkerLightBlue,
                        minimumSize: const Size(double.infinity, 50),
                        padding: const EdgeInsets.symmetric(vertical: 18.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                      ),
                      child: Text(
                        'Export '.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
              if (localExportingToZip) ...[
                const CircularProgressIndicator(),
                Text("Exporting... $exportProgressPercent %"),
              ],
              if (!localExportingToZip && exportSuccessful) ...[
                const Text("Export successful!")
              ],
            ];
            return _buildOptionsBottomSheet(context, 'Export Photos', content);
          },
        );
      },
    );
  }

  Future<void> _shareZipFile() async {
    String zipFileExportPath = await DirUtils.getZipFileExportPath(
        widget.projectId, widget.projectName);
    final params = ShareParams(files: [XFile(zipFileExportPath)]);
    final result = await SharePlus.instance.share(params);
    if (result.status == ShareResultStatus.success) {
      // print('Share success.');
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
    if (isRawPhoto) {
      return _buildRawThumbnail(imagePath);
    } else {
      return _buildStabilizedThumbnail(imagePath);
    }
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
                          widget.userRanOutOfSpaceCallback);
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
    final File file = File(thumbnailPath);
    _rawThumbnailFutures[thumbnailPath] ??= _waitForThumbnail(file);
    return FutureBuilder<bool>(
      future: _rawThumbnailFutures[thumbnailPath],
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.data == null) {
          return const FlashingBox();
        }
        if (snapshot.data == false) {
          return Container(color: Colors.black);
        }
        return _buildThumbnailContent(
          imageWidget: Image.file(
            File(thumbnailPath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stack) =>
                Container(color: Colors.black),
          ),
          filepath: filepath,
          onTap: () =>
              _showImagePreviewDialog(File(filepath), isStabilized: false),
          onLongPress: () => _showImageOptionsMenu(File(filepath)),
        );
      },
    );
  }

  Future<bool> _waitForThumbnail(File file,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final sw = Stopwatch()..start();
    int? lastLen;
    while (sw.elapsed < timeout) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && lastLen != null && len == lastLen) {
          // Validate image in isolate to avoid blocking UI
          final valid = await ImageUtils.validateImageInIsolate(file.path);
          if (valid) return true;
        }
        lastLen = len;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  final Set<String> _retryingPhotoTimestamps = {};
  final Map<String, Future<bool>> _rawThumbnailFutures = {};
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
                  FutureBuilder<String>(
                    future: GalleryUtils.waitForThumbnail(
                        FaceStabilizer.getStabThumbnailPath(imageFile.path),
                        widget.projectId),
                    builder:
                        (BuildContext context, AsyncSnapshot<String> snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting ||
                          !snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 32.0, horizontal: 20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Image being stabilized. Please wait...",
                                style: TextStyle(color: Colors.white),
                              ),
                              SizedBox(height: 10),
                              Text('View raw photo by tapping "RAW"')
                            ],
                          ),
                        );
                      } else if (snapshot.data == "no_faces_found" ||
                          snapshot.data == "stab_failed") {
                        var text = snapshot.data == "no_faces_found"
                            ? "Stabilization failed. No faces found. Try the 'manual stabilization' option."
                            : "Stabilization failed. We were unable to stabilize facial landmarks. Try the 'manual stabilization' option.";
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 32.0, horizontal: 20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error,
                                  color: Colors.red, size: 50.0),
                              const SizedBox(height: 10),
                              Text(
                                text,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      } else if (snapshot.data == "success") {
                        return _buildResizableImage(
                            File(activeImagePreviewPath!));
                      } else {
                        return const Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 32.0, horizontal: 20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Unknown error occurred.",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      }
                    },
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
              audioStatus.isGranted) return;
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
        print('Error checking permissions: $e');
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
      _rawThumbnailFutures.remove(thumbnailPath);
      _loadImages();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There was an error. Please try again.')),
        );
      }
    }
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;
  _DashedRectPainter({
    required this.color,
    this.strokeWidth = 2,
    this.dash = 8,
    this.gap = 6,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final ui.Path outline = ui.Path()..addRect(rect);
    final ui.Path dashedPath = _dashPath(outline, dash, gap);
    canvas.drawPath(dashedPath, p);
  }

  ui.Path _dashPath(ui.Path source, double dashLength, double gapLength) {
    final ui.Path dest = ui.Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double next = distance + dashLength;
        dest.addPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          ui.Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
