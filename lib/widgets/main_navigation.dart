import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/services.dart';
import '../screens/create_page.dart';
import '../services/log_service.dart';
import '../screens/gallery_page/gallery_page.dart';
import '../screens/project_page.dart';
import '../screens/info_page.dart';
import '../screens/camera_page/camera_page.dart';
import '../services/database_helper.dart';
import '../services/settings_cache.dart';
import '../services/stabilization_service.dart';
import '../services/stabilization_progress.dart';
import '../services/stabilization_state.dart';
import '../services/stab_update_event.dart';
import '../utils/gallery_utils.dart';
import 'package:path/path.dart' as path;
import '../styles/styles.dart';
import '../widgets/custom_app_bar.dart';

class MainNavigation extends StatefulWidget {
  final int projectId;
  final int? index;
  final bool showFlashingCircle;
  final String projectName;
  final bool? takingGuidePhoto;
  final SettingsCache? initialSettingsCache;
  final bool newProject;

  const MainNavigation({
    super.key,
    required this.projectId,
    this.index,
    required this.showFlashingCircle,
    required this.projectName,
    this.takingGuidePhoto,
    this.initialSettingsCache,
    this.newProject = false,
  });

  @override
  MainNavigationState createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation> {
  late int _selectedIndex;
  int _prevIndex = 0;
  bool _isImporting = false;
  int photoCount = 0;
  late bool _showFlashingCircle;
  late String projectIdStr;
  bool _hideNavBar = false;
  int _importMaxProgress = 0;
  bool userOnImportTutorial = false;
  List<String> _imageFiles = [];
  List<String> _stabilizedImageFiles = [];
  SettingsCache? _settingsCache;
  bool _photoTakenToday = false;
  bool _userRanOutOfSpace = false;

  /// Current stabilization progress from the service stream.
  StabilizationProgress _stabProgress = StabilizationProgress.idle();

  /// Subscription to the stabilization service progress stream.
  StreamSubscription<StabilizationProgress>? _stabSubscription;

  /// Stream controller to notify UI components of stabilization updates.
  /// Emits typed events for progress updates, completion, cancellation, etc.
  final StreamController<StabUpdateEvent> _stabUpdateController =
      StreamController<StabUpdateEvent>.broadcast();

  /// Separate progress tracking for imports (not part of stabilization).
  int _importProgressPercent = 0;

  // Derived getters for compatibility with child widgets
  bool get _stabilizingActive =>
      _stabProgress.state == StabilizationState.stabilizing ||
      _stabProgress.state == StabilizationState.preparing ||
      _stabProgress.state == StabilizationState.cancelling;
  bool get _videoCreationActive =>
      _stabProgress.state == StabilizationState.compilingVideo ||
      _stabProgress.state == StabilizationState.cancellingVideo;
  int get progressPercent =>
      _isImporting ? _importProgressPercent : _stabProgress.progressPercent;
  String get minutesRemaining => _stabProgress.eta ?? "";
  int get _photoIndex => _stabProgress.currentPhoto;
  int get _unstabilizedPhotoCount => _stabProgress.totalPhotos;
  int get _currentFrame => _stabProgress.currentFrame ?? 0;

  @override
  void initState() {
    super.initState();
    projectIdStr = widget.projectId.toString();
    _selectedIndex = widget.index ?? 0;
    _showFlashingCircle = widget.showFlashingCircle;

    // Subscribe to stabilization progress stream for reactive UI updates
    _stabSubscription = StabilizationService.instance.progressStream.listen((
      progress,
    ) {
      if (mounted) {
        final prevState = _stabProgress.state;
        setState(() => _stabProgress = progress);

        // Emit typed events for UI components (gallery, app bar, project page)
        switch (progress.state) {
          case StabilizationState.stabilizing:
            _stabUpdateController.add(
              StabUpdateEvent.photoStabilized(
                progress.currentPhoto,
                timestamp: progress.lastStabilizedTimestamp,
              ),
            );
            break;
          case StabilizationState.completed:
            _stabUpdateController.add(StabUpdateEvent.stabilizationComplete());
            break;
          case StabilizationState.compilingVideo:
            // Emit completion when video starts (stabilization done)
            // Only emit once when transitioning to video phase
            if (prevState != StabilizationState.compilingVideo) {
              _stabUpdateController.add(
                StabUpdateEvent.stabilizationComplete(),
              );
            }
            break;
          case StabilizationState.cancelled:
            _stabUpdateController.add(StabUpdateEvent.cancelled());
            break;
          case StabilizationState.error:
            _stabUpdateController.add(StabUpdateEvent.error());
            break;
          default:
            break;
        }
      }
    });

    // If the project is a newly created one, we use a settingsCache filled
    // default values instead of loading project data
    if (widget.initialSettingsCache != null) {
      _settingsCache = widget.initialSettingsCache;
      _initPhotosThenStabilize();
    } else {
      _refreshSettingsCache().then((_) {
        _initPhotosThenStabilize();
      });
    }

    initPhotoCount();
  }

  @override
  void dispose() {
    _stabSubscription?.cancel();
    _stabUpdateController.close();
    _settingsCache?.dispose();
    super.dispose();
  }

  Future<void> _initPhotosThenStabilize() async {
    await loadPhotos();
    if (!mounted) return;

    _checkPhotoTakenToday();
    _startStabilization();
  }

  Future<void> loadPhotos() async {
    final List<Object> results = await Future.wait([
      GalleryUtils.getAllRawImagePaths(widget.projectId),
      GalleryUtils.getAllStabAndFailedImagePaths(widget.projectId),
    ]);

    if (!mounted) return;
    setRawAndStabPhotoStates(
      results[0] as List<String>,
      results[1] as List<String>,
    );
  }

  void _checkPhotoTakenToday() {
    if (!mounted) return;
    setState(() {
      _photoTakenToday = photoWasTakenToday(_imageFiles);
    });
  }

  static bool photoWasTakenToday(List<String> photos) {
    final DateTime today = DateTime.now();
    return photos.any((photoPath) {
      final timestampInt = int.parse(path.basenameWithoutExtension(photoPath));
      final photoDate = DateTime.fromMillisecondsSinceEpoch(timestampInt);
      return photoDate.isSameDate(today);
    });
  }

  void setRawAndStabPhotoStates(
    List<String> imageFiles,
    List<String> stabilizedImageFiles,
  ) {
    if (!mounted) return;
    setState(() {
      _imageFiles = imageFiles;
      _stabilizedImageFiles = stabilizedImageFiles;
    });
  }

  void clearRawAndStabPhotos() {
    if (!mounted) return;
    setState(() {
      _imageFiles.clear();
      _stabilizedImageFiles.clear();
    });
  }

  void userRanOutOfSpaceCallback() {
    if (mounted) {
      setState(() {
        _userRanOutOfSpace = true;
      });
    }
  }

  Future<void> _refreshSettingsCache() async {
    final oldCache = _settingsCache;
    SettingsCache settingsCache = await SettingsCache.initialize(
      widget.projectId,
    );
    if (!mounted) {
      settingsCache.dispose();
      return;
    }
    setState(() => _settingsCache = settingsCache);
    oldCache?.dispose(); // Dispose old cache after replacing
  }

  Future<void> refreshSettings() async {
    LogService.instance.log("Settings are being refreshed...");
    await _refreshSettingsCache();
  }

  Future<void> initPhotoCount() async {
    final List<Map<String, dynamic>> rawPhotos =
        await DB.instance.getPhotosByProjectID(widget.projectId);
    photoCount = rawPhotos.length;
  }

  Future<void> setUserOnImportTutorialTrue() async {
    if (!mounted) return;
    setState(() {
      userOnImportTutorial = true;
    });
  }

  void setUserOnImportTutorialFalse() {
    if (!mounted) return;
    setState(() {
      userOnImportTutorial = false;
    });
  }

  Future<void> hideNavBar() async {
    await initPhotoCount();
    if (!mounted) return;
    setState(() {
      _hideNavBar = true;
    });
  }

  Future<void> processPickedFiles(
    FilePickerResult? pickedFiles,
    Future<void> Function(dynamic file) processFileCallback,
  ) async {
    if (pickedFiles == null) return;
    if (!mounted) return;

    setState(() {
      _isImporting = true;
    });

    _importMaxProgress = 0;

    final List<String> allPhotosBefore =
        await DB.instance.getAllPhotoPathsByProjectID(widget.projectId);
    final int photoCountBeforeImport = allPhotosBefore.length;

    final List<File> files =
        pickedFiles.paths.map((path) => File(path!)).toList();
    for (File file in files) {
      await processFileCallback(file);
    }

    if (photoCountBeforeImport == 0) {
      LogService.instance.log(
        "[processPickedFiles] photoCountBeforeImport == 0 is true",
      );

      String? importedPhotosOrientation =
          await DB.instance.checkPhotoOrientationThreshold(widget.projectId);
      if (importedPhotosOrientation == 'landscape') {
        LogService.instance.log(
          "[processPickedFiles] importedPhotosOrientation == 'landscape' is true",
        );

        DB.instance.setSettingByTitle(
          "project_orientation",
          'landscape',
          projectIdStr,
        );
        DB.instance.setSettingByTitle("aspect_ratio", "4:3", projectIdStr);
      } else {
        LogService.instance.log(
          "[processPickedFiles] importedPhotosOrientation == 'landscape' NOT true. importedPhotosOrientation = $importedPhotosOrientation",
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _importProgressPercent = 0;
    });

    _importMaxProgress = 0;
  }

  void setProgressInMain(int progressIn) {
    if (!mounted) return;
    int next = progressIn;
    if (_isImporting && progressIn < _importMaxProgress && progressIn != 100) {
      next = _importMaxProgress;
    } else {
      if (progressIn > _importMaxProgress) {
        _importMaxProgress = progressIn;
      }
      if (progressIn == 100) {
        _importMaxProgress = 100;
      }
    }
    setState(() {
      _importProgressPercent = next;
    });
  }

  /// Start stabilization using the centralized service.
  ///
  /// This method delegates to [StabilizationService] which handles:
  /// - Isolate management and instant cancellation
  /// - Progress streaming via reactive updates
  /// - Video compilation with FFmpeg process tracking
  Future<void> _startStabilization() async {
    // Wait for import to finish before starting stabilization
    while (_isImporting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Delegate to service - progress comes via stream subscription
    await StabilizationService.instance.startStabilization(
      widget.projectId,
      onUserRanOutOfSpace: userRanOutOfSpaceCallback,
    );
  }

  void _hideFlashingCircle() {
    if (!mounted) return;
    setState(() => _showFlashingCircle = false);
  }

  /// Cancel stabilization INSTANTLY.
  ///
  /// This method returns immediately after initiating cancellation.
  /// The service kills all active isolates and FFmpeg processes.
  /// UI updates come via the progress stream (shows "Cancelling..." state).
  Future<void> _cancelStabilizationProcess() async {
    LogService.instance.log("_cancelStabilizationProcess called");
    await StabilizationService.instance.cancel();
    // No waiting needed - state updates come via stream
  }

  List<Widget> get _widgetOptions => [
        ProjectPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          stabilizingRunningInMain: _stabilizingActive,
          stabCallback: _startStabilization,
          cancelStabCallback: _cancelStabilizationProcess,
          goToPage: _onItemTapped,
          setUserOnImportTutorialTrue: setUserOnImportTutorialTrue,
          settingsCache: _settingsCache,
          refreshSettings: refreshSettings,
          clearRawAndStabPhotos: clearRawAndStabPhotos,
          photoTakenToday: _photoTakenToday,
          stabUpdateStream: _stabUpdateController.stream,
        ),
        GalleryPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          stabCallback: _startStabilization,
          userRanOutOfSpaceCallback: userRanOutOfSpaceCallback,
          cancelStabCallback: _cancelStabilizationProcess,
          processPickedFiles: processPickedFiles,
          stabilizingRunningInMain: _stabilizingActive,
          videoCreationActiveInMain: _videoCreationActive,
          showFlashingCircle: _showFlashingCircle,
          hideFlashingCircle: _hideFlashingCircle,
          goToPage: _onItemTapped,
          progressPercent: progressPercent,
          minutesRemaining: minutesRemaining,
          userOnImportTutorial: userOnImportTutorial,
          setUserOnImportTutorialFalse: setUserOnImportTutorialFalse,
          importRunningInMain: _isImporting,
          setProgressInMain: setProgressInMain,
          imageFilesStr: _imageFiles,
          stabilizedImageFilesStr: _stabilizedImageFiles,
          setRawAndStabPhotoStates: setRawAndStabPhotoStates,
          settingsCache: _settingsCache,
          refreshSettings: refreshSettings,
          userRanOutOfSpace: _userRanOutOfSpace,
          stabUpdateStream: _stabUpdateController.stream,
        ),
        CameraPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          takingGuidePhoto: widget.takingGuidePhoto,
          openGallery: openGallery,
          refreshSettings: refreshSettings,
          goToPage: _onItemTapped,
        ),
        CreatePage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          stabilizingRunningInMain: _stabilizingActive,
          videoCreationActiveInMain: _videoCreationActive,
          currentFrame: _currentFrame,
          unstabilizedPhotoCount: _unstabilizedPhotoCount,
          photoIndex: _photoIndex,
          stabCallback: _startStabilization,
          cancelStabCallback: _cancelStabilizationProcess,
          goToPage: _onItemTapped,
          hideNavBar: hideNavBar,
          prevIndex: _prevIndex,
          progressPercent: progressPercent,
          refreshSettings: refreshSettings,
          clearRawAndStabPhotos: clearRawAndStabPhotos,
          settingsCache: _settingsCache,
        ),
        InfoPage(
          projectId: widget.projectId,
          projectName: widget.projectName,
          cancelStabCallback: _cancelStabilizationProcess,
          goToPage: _onItemTapped,
          stabilizingRunningInMain: _stabilizingActive,
        ),
      ];

  void _onItemTapped(int index) {
    int selectedIndex = _selectedIndex;

    setState(() {
      _prevIndex = selectedIndex;
      _selectedIndex = index;
    });

    if (index == 3) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (!_stabilizingActive && !_videoCreationActive && !_isImporting) {
      _startStabilization();
    }
  }

  void openGallery() => _onItemTapped(3);
  // Show header on CreatePage when: navbar not hidden OR actively stabilizing/compiling
  // This ensures header shows during loading even after a settings-triggered reset
  bool onCreatePageDuringLoading() =>
      _selectedIndex == 3 &&
      (!_hideNavBar || _stabilizingActive || _videoCreationActive);

  @override
  Widget build(BuildContext context) {
    final List<IconData> iconList = [
      Icons.home,
      Icons.collections,
      Icons.camera_alt,
      Icons.play_circle,
      Icons.info,
    ];

    Widget? appBar;
    if (_selectedIndex == 0 ||
        _selectedIndex == 1 ||
        _selectedIndex == 4 ||
        onCreatePageDuringLoading()) {
      appBar = CustomAppBar(
        projectId: widget.projectId,
        goToPage: _onItemTapped,
        progressPercent: progressPercent,
        stabilizingRunningInMain: _stabilizingActive,
        videoCreationActiveInMain: _videoCreationActive,
        selectedIndex: _selectedIndex,
        stabCallback: _startStabilization,
        cancelStabCallback: _cancelStabilizationProcess,
        importRunningInMain: _isImporting,
        settingsCache: _settingsCache,
        refreshSettings: refreshSettings,
        clearRawAndStabPhotos: clearRawAndStabPhotos,
        minutesRemaining: minutesRemaining,
        userRanOutOfSpace: _userRanOutOfSpace,
        stabUpdateStream: _stabUpdateController.stream,
      );
    }

    bool navbarShouldBeHidden() {
      return _selectedIndex == 3 &&
          _hideNavBar &&
          !_stabilizingActive &&
          !_videoCreationActive &&
          photoCount > 1;
    }

    return Scaffold(
      body: Column(
        children: [
          if (appBar != null) appBar,
          Expanded(child: _widgetOptions.elementAt(_selectedIndex)),
        ],
      ),
      bottomNavigationBar: navbarShouldBeHidden()
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade800, width: 0.7),
                ),
              ),
              child: AnimatedBottomNavigationBar.builder(
                itemCount: iconList.length,
                tabBuilder: (int index, bool isActive) {
                  final color =
                      isActive ? AppColors.lightBlue : Colors.grey[300];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(iconList[index], size: 24, color: color)],
                  );
                },
                height: 60,
                gapLocation: GapLocation.none,
                notchSmoothness: NotchSmoothness.defaultEdge,
                splashColor: Colors.transparent,
                activeIndex: _selectedIndex,
                onTap: _onItemTapped,
                backgroundColor: const Color(0xff0F0F0F),
              ),
            ),
    );
  }
}
