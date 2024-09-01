import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:agelapse/screens/stab_on_diff_face.dart';
import 'package:agelapse/widgets/yellow_tip_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../services/database_helper.dart';
import '../../services/face_stabilizer.dart';
import '../../services/settings_cache.dart';
import '../../styles/styles.dart';
import '../../utils/project_utils.dart';
import '../../utils/camera_utils.dart';
import '../../utils/dir_utils.dart';
import '../../utils/gallery_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/utils.dart';
import '../../widgets/progress_widget.dart';
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
    List<String> imageFiles,
    List<String> stabilizedImageFiles
  ) setRawAndStabPhotoStates;
  final Future<void> Function(
    FilePickerResult? pickedFiles,
    Future<void> Function(dynamic file) processFileCallback
  ) processPickedFiles;
  final void Function() refreshSettings;
  final String minutesRemaining;
  final bool userRanOutOfSpace;

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
  });

  @override
  GalleryPageState createState() => GalleryPageState();
}

class GalleryPageState extends State<GalleryPage> with SingleTickerProviderStateMixin {
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
  ValueNotifier<String> activeProcessingDateNotifier = ValueNotifier<String>('');
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

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_tabController.index == 0) {
              GalleryUtils.scrollToBottomInstantly(_stabilizedScrollController);
            } else {
              GalleryUtils.scrollToBottomInstantly(_rawScrollController);
            }
          });
        });
      }
    });
  }

  Future<void> _initializeFromCache() async {
    while (widget.settingsCache == null) {
      print("Waiting for cache...");
      await Future.delayed(const Duration(seconds: 1));
    }

    bool hasOpenedNonEmptyGallery = widget.settingsCache!.hasOpenedNonEmptyGallery;
    if (!hasOpenedNonEmptyGallery) {
      await SettingsUtil.setHasOpenedNonEmptyGalleryToTrue(projectIdStr);
      widget.refreshSettings();
    }
  }

  Future<void> _loadImages() async {
    await GalleryUtils.loadImages(
      projectId: projectId,
      projectIdStr: projectIdStr,
      onImagesLoaded: (rawImages, stabImageFiles) async {
        widget.setRawAndStabPhotoStates(rawImages, stabImageFiles);
      },
      onShowInfoDialog: () => showInfoDialog(context),
      stabilizedScrollController: _stabilizedScrollController,
    );
  }

  List<File> cloneList(List list) => List.from(list);

  Future<void> _init() async {
    final String projectOrientationRaw = await SettingsUtil.loadProjectOrientation(projectIdStr);
    final int gridAxisCountRaw = await SettingsUtil.loadGridAxisCount(projectIdStr);
    setState(() {
      gridAxisCount = gridAxisCountRaw;
      projectOrientation = projectOrientationRaw;
    });

    if (widget.userOnImportTutorial) {
      widget.setUserOnImportTutorialFalse();
      _showImportOptionsBottomSheet(context);
    }

    while (true) {
      int waitTimeInSeconds = 2;

      int stabCount = await DB.instance.getStabilizedPhotoCountByProjectID(projectId, projectOrientation!);
      if (stabCount != _stabCount) {
        _stabCount = stabCount;
        if (_isMounted) {
          await _loadImages();
        }
      }

      await Future.delayed(Duration(seconds: waitTimeInSeconds));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    activeProcessingDateNotifier.dispose();
    _stabilizedScrollController.dispose();
    _rawScrollController.dispose();
    _isMounted = false;
    super.dispose();
  }

  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.mediaLibrary.request();

    if (status.isGranted) {
      return true;
    } else if (status.isDenied) {
      status = await Permission.storage.request();

      return false;
    } else if (status.isPermanentlyDenied) {
      openAppSettings(); // Prompt user to open settings
      return false;
    }

    return false;
  }


  Future<void> _pickFromGallery() async {
    try {
      // Request permissions
      bool status = await requestPermission();
      if (!status) return;

      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 9,
          requestType: RequestType.image,
        ),
      );

      if (result == null) return;

      setState(() {
        _tabController.index = 1; // Switch to raw tab
      });

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
    final String tempOriginPhotoPath = await _getTemporaryPhotoPath(asset, originPath);

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

  Future<String> _getTemporaryPhotoPath(AssetEntity asset, String originPath) async {
    final String basename = path.basenameWithoutExtension(originPath).toLowerCase().replaceAll(".", "");
    final String extension = path.extension(originPath).toLowerCase();
    final String tempDir = await DirUtils.getTemporaryDirPath();
    return path.join(tempDir, "$basename$extension");
  }

  Future<bool> _isModifiedLivePhoto(AssetEntity asset, String originPath) async {
    final String extension = path.extension(originPath).toLowerCase();
    return asset.isLivePhoto && (extension == ".jpg" || extension == ".jpeg");
  }

  Future<void> _writeModifiedLivePhoto(AssetEntity asset, File tempOriginFile) async {
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
                _previousScale = _scale;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _scale = _previousScale * details.scale;
                  gridAxisCount = (4 / _scale).clamp(1, 5).toInt();
                });
              },
              child: Stack(
                children: [
                  (!isImporting && !widget.importRunningInMain) ? _buildTabBarView() : _buildLoadingView(),
                  _buildFloatingActionButton(
                    context,
                    right: -13,
                    icon: Icons.upload,
                    onPressed: isImporting
                        ? _showImportingDialog
                        : () => _showImportOptionsBottomSheet(context),
                  ),
                  _buildFloatingActionButton(
                    context,
                    right: 35,
                    icon: Icons.download,
                    onPressed: () => _showExportOptionsBottomSheet(context),
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
      }
      ) {
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
          Tab(text: 'Originals'),
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
        _buildImageGrid(widget.stabilizedImageFilesStr, _stabilizedScrollController),
        _buildImageGrid(widget.imageFilesStr, _rawScrollController),
      ],
    );
  }

  Widget _buildImageGrid(List<String> imageFiles, ScrollController scrollController) {
    if (widget.stabilizedImageFilesStr.isEmpty && widget.imageFilesStr.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          child: const YellowTipBar(
            message: "Your gallery is empty. Take or import photos to begin.",
          ),
        ),
      );
    }

    final bool isStabilizedTab = scrollController == _stabilizedScrollController;
    final List<String> files = isStabilizedTab ? widget.stabilizedImageFilesStr : imageFiles;
    final int itemCount = isStabilizedTab && widget.stabilizingRunningInMain
        ? files.length + 1
        : files.length;

    return GridView.builder(
      padding: EdgeInsets.zero,
      controller: scrollController,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridAxisCount,
        crossAxisSpacing: 2.0,
        mainAxisSpacing: 2.0,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (isStabilizedTab && index == widget.stabilizedImageFilesStr.length && widget.stabilizingRunningInMain) {
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
          Text("${widget.progressPercent.toStringAsFixed(1)}%"),
        ],
      ),
    );
  }

  void increaseSuccessfulImportCount() => successfullyImported++;

  void increasePhotosImported(int value) {
    photosImported = photosImported + value;
  }

  Future<void> _pickFiles() async {
    setState(() {
      photosImported = 0;
      successfullyImported = 0;
      _tabController.index = 1;
    });

    FilePickerResult? pickedFiles;
    try {
      pickedFiles = await FilePicker.platform.pickFiles(allowMultiple: true);
    } catch (e) {
      return;
    }

    if (pickedFiles == null) return;

    setState(() => isImporting = true);

    if (widget.stabilizingRunningInMain) {
      widget.cancelStabCallback();
    }

    await widget.processPickedFiles(pickedFiles, processPickedFile);

    widget.refreshSettings();
    widget.stabCallback();
    setState(() => isImporting = false);
    _loadImages();

    print("photosImported now: $photosImported");
    print("successfullyImported now: $successfullyImported");

    _showImportCompleteDialog(successfullyImported, photosImported - successfullyImported);
  }

  Future<void> processPickedFile(file) async {
    await GalleryUtils.processPickedFile(
        file,
        projectId,
        activeProcessingDateNotifier,
        onImagesLoaded: _loadImages,
        setProgressInMain: widget.setProgressInMain,
        increaseSuccessfulImportCount: increaseSuccessfulImportCount,
        increasePhotosImported: increasePhotosImported
    );
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
          content: Text('Imported: $imported\nSkipped (Already Imported): $skipped'),
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
    List<Widget> content = [
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
          title: const Text('Import from Files'),
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
    ];

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return _buildOptionsBottomSheet(context, 'Import Photos', content);
      },
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
                // Trick to filter to 1 decimal place, including .0
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
                const SizedBox(height: 24,),
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
                            const SnackBar(content: Text('Please select at least one type of files to export')),
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
                            String stabilizedDir = await DirUtils.getStabilizedDirPathFromProjectIdAndOrientation(widget.projectId, projectOrientation!);
                            List<String> stabilizedFiles = await listFilesInDirectory(stabilizedDir);
                            filesToExport['Stabilized']!.addAll(stabilizedFiles);
                          }

                          String res = await GalleryUtils.exportZipFile(
                              widget.projectId,
                              widget.projectName,
                              filesToExport,
                              setExportProgress
                          );
                          if (res == 'success') {
                            setState(() => exportSuccessful = true);
                            _shareZipFile();
                          }
                        } catch (e) {
                          // print(e);
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
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (localExportingToZip) ... [
                const CircularProgressIndicator(),
                Text("Exporting... $exportProgressPercent %"),
              ],
              if (!localExportingToZip && exportSuccessful) ... [
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
    String zipFileExportPath = await DirUtils.getZipFileExportPath(widget.projectId, widget.projectName);
    final result = await Share.shareXFiles([XFile(zipFileExportPath)]);

    if (result.status == ShareResultStatus.success) {
      // print('Share success.');
    }
  }

// Utility method to list files in a directory
  static Future<List<String>> listFilesInDirectory(String dirPath) async {
    Directory directory = Directory(dirPath);
    List<String> filePaths = [];
    if (await directory.exists()) {
      directory.listSync().forEach((file) {
        if (file is File) {
          filePaths.add(file.path);
        }
      });
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

  Widget _buildThumbnailContent({
    required Widget imageWidget,
    required String filepath,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          imageWidget
        ],
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
        "${path.basenameWithoutExtension(filepath)}.jpg"
    );

    final File file = File(thumbnailPath);

    return FutureBuilder(
      future: _waitForThumbnail(file),
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FlashingBox();
        } else {
          return _buildThumbnailContent(
            imageWidget: Image.file(
              File(thumbnailPath),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            filepath: filepath,
            onTap: () => _showImagePreviewDialog(File(filepath), isStabilized: false),
            onLongPress: () => _showDeleteDialog(File(filepath)),
          );
        }
      },
    );
  }

  Future<void> _waitForThumbnail(File file) async {
    while (!file.existsSync()) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }


  Widget _buildStabilizedThumbnail(String filepath) {
    final String thumbnailPath = FaceStabilizer.getStabThumbnailPath(filepath);

    return GestureDetector(
      onTap: () => _showImagePreviewDialog(File(filepath), isStabilized: true),
      onLongPress: () => _showDeleteDialog(File(filepath)),
      child: StabilizedThumbnail(thumbnailPath: thumbnailPath, projectId: widget.projectId,),
    );
  }


  Future<void> _showDialog(BuildContext context, Widget dialog) async {
    showDialog(
      context: context,
      builder: (BuildContext context) => dialog,
    );
  }

  Future<void> _showImagePreviewDialog(File imageFile, {required bool isStabilized}) async {
    final String timestamp = path.basenameWithoutExtension(imageFile.path);
    final bool isRaw = !isStabilized;

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
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const Icon(Icons.access_time_outlined),
                      const SizedBox(width: 8),
                      Text(
                        Utils.formatUnixTimestamp2(int.parse(timestamp)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
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

  Widget _buildImagePreview(StateSetter dialogSetState, File imageFile, bool isStabilized) {
    return activeImagePreviewPath != null
        ? Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isStabilized && activeButton != 'raw')
            FutureBuilder<String>(
              future: GalleryUtils.waitForThumbnail(FaceStabilizer.getStabThumbnailPath(imageFile.path), widget.projectId),
              builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
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
                } else if (snapshot.data == "no_faces_found" || snapshot.data == "stab_failed") {
                  var text = snapshot.data == "no_faces_found"
                      ? "Stabilization failed. No faces found."
                      : "Stabilization failed. We were unable to stabilize facial landmarks.";

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 50.0),
                        const SizedBox(height: 10),
                        Text(
                          text,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                } else if (snapshot.data == "success") {
                  return _buildResizableImage(File(activeImagePreviewPath!));
                } else {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
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
      ),
    );
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async {
    return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);
  }

  Widget _buildActionBar(StateSetter dialogSetState, File imageFile) {
    const double iconSize = 20.0;
    final String timestamp = path.basenameWithoutExtension(activeImagePreviewPath!);

    Future<String> getRawPhotoPathFromTimestamp(String timestamp) async {
      return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);
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

    Future<void> updateImagePreviewPath(StateSetter dialogSetState, Future<String> Function() getPathFunction, String buttonType) async {
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
          final RenderBox button = context.findRenderObject() as RenderBox;
          final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final Offset offset = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);
          await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(offset.dx - 10, offset.dy - 70, overlay.size.width - offset.dx, 0),
            items: <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'stabilize',
                child: const Text('Stabilize on Other Face'),
                onTap: () {
                  StabDiffFacePage stabNewFaceScreen = StabDiffFacePage(
                      projectId: projectId,
                      imageTimestamp: timestamp,
                      reloadImagesInGallery: _loadImages,
                      stabCallback: widget.stabCallback,
                      userRanOutOfSpaceCallback: widget.userRanOutOfSpaceCallback
                  );
                  Utils.navigateToScreenReplace(context, stabNewFaceScreen);
                },
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete',
                child: const Text('Delete Image'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteDialog(imageFile);
                },
              ),
            ],
          );
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
          IconButton(
            icon: Icon(Icons.raw_on, color: activeButton == 'raw' ? Colors.blue : Colors.white),
            iconSize: 25.0,
            onPressed: () => showRawImage(dialogSetState),
          ),
          projectOrientation == 'portrait'
              ? _buildActionButton(
            icon: Icons.video_stable,
            active: activeButton == 'portrait',
            onPressed: () => updateImagePreviewPath(
              dialogSetState,
                  () => DirUtils.getStabilizedPortraitImagePathFromRawPath(activeImagePreviewPath!, projectId),
              'portrait',
            ),
          )
              : _buildActionButton(
            icon: Icons.video_stable,
            active: activeButton == 'landscape',
            onPressed: () => updateImagePreviewPath(
              dialogSetState,
                  () => DirUtils.getStabilizedLandscapeImagePathFromRawPath(activeImagePreviewPath!, projectId),
              'landscape',
            ),
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
            setState(() => gallerySaveIsLoading = true);

            final XFile image = XFile(activeImagePreviewPath!);
            await CameraUtils.saveToGallery(image);

            setState(() {
              gallerySaveIsLoading = false;
              gallerySaveSuccessful = true;
            });

            await Future.delayed(const Duration(seconds: 1));

            setState(() => gallerySaveSuccessful = false);
          },
        );
      },
    );
  }

  Widget _buildActionButton({required IconData icon, required VoidCallback onPressed, bool active = false, double iconSize = 20.0}) {
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
          content: const Text("During stabilization, view the original photo in "
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
    _showDialog(context, AlertDialog(
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
            final bool isStabilizedImage = image.path.toLowerCase().contains("stabilized");

            if (isStabilizedImage) {
              final String timestamp = path.basenameWithoutExtension(image.path);
              final String rawPhotoPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, projectId);

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
    print("Deleting image result: $success");
    if (success) {
      _loadImages();
    }
  }
}