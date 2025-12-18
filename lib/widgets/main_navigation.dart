import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/services.dart';
import '../screens/create_page.dart';
import '../screens/gallery_page/gallery_page.dart';
import '../screens/project_page.dart';
import '../screens/info_page.dart';
import '../screens/camera_page/camera_page.dart';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/settings_cache.dart';
import '../utils/gallery_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/video_utils.dart';
import 'package:path/path.dart' as path;
import '../styles/styles.dart';
import '../widgets/custom_app_bar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  bool _stabilizingActive = false;
  bool _videoCreationActive = false;
  bool _cancelStabilization = false;
  bool _isImporting = false;
  bool _inStabCall = false;
  int _photoIndex = 0;
  int _unstabilizedPhotoCount = 0;
  int _successfullyStabilizedPhotos = 0;
  int _currentFrame = 0;
  int photoCount = 0;
  late bool _showFlashingCircle;
  late String projectIdStr;
  bool _hideNavBar = false;
  int progressPercent = 0;
  int _importMaxProgress = 0;
  bool userOnImportTutorial = false;
  List<String> _imageFiles = [];
  List<String> _stabilizedImageFiles = [];
  SettingsCache? _settingsCache;
  bool _photoTakenToday = false;
  String minutesRemaining = "";
  bool _userRanOutOfSpace = false;
  int _totalPhotoCountForProgress = 0;
  int _stabilizedAtStart = 0;

  @override
  void initState() {
    super.initState();
    projectIdStr = widget.projectId.toString();
    _selectedIndex = widget.index ?? 0;
    _showFlashingCircle = widget.showFlashingCircle;

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

  Future<void> _initPhotosThenStabilize() async {
    await loadPhotos();

    _checkPhotoTakenToday();
    _startStabilization();
  }

  Future<void> loadPhotos() async {
    final List<Object> results = await Future.wait([
      GalleryUtils.getAllRawImagePaths(widget.projectId),
      GalleryUtils.getAllStabAndFailedImagePaths(widget.projectId)
    ]);

    setRawAndStabPhotoStates(
      results[0] as List<String>,
      results[1] as List<String>
    );
  }

  void _checkPhotoTakenToday() {
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

  void setRawAndStabPhotoStates(List<String> imageFiles, List<String> stabilizedImageFiles) {
    setState(() {
      _imageFiles = imageFiles;
      _stabilizedImageFiles = stabilizedImageFiles;
    });
  }

  void clearRawAndStabPhotos() {
    setState(() {
      _imageFiles.clear();
      _stabilizedImageFiles.clear();
    });
  }

  void userRanOutOfSpaceCallback() {
    setState(() {
      _userRanOutOfSpace = true;
    });
    _cancelStabilizationProcess();
  }

  Future<void> _refreshSettingsCache() async {
    SettingsCache settingsCache = await SettingsCache.initialize(widget.projectId);
    setState(() => _settingsCache = settingsCache);
  }

  void refreshSettings() async {
    print("Settings are being refreshed...");
    await _refreshSettingsCache();
  }

  Future<void> initPhotoCount() async {
    final List<Map<String, dynamic>> rawPhotos = await DB.instance.getPhotosByProjectID(widget.projectId);
    photoCount = rawPhotos.length;
  }

  Future<void> setUserOnImportTutorialTrue() async {
    setState(() {
      userOnImportTutorial = true;
    });
  }

  void setUserOnImportTutorialFalse() {
    setState(() {
      userOnImportTutorial = false;
    });
  }

  Future<void> hideNavBar() async {
    await initPhotoCount();
    setState(() {
      _hideNavBar = true;
    });
  }

  Future<void> processPickedFiles(
    FilePickerResult? pickedFiles,
    Future<void> Function(dynamic file) processFileCallback
  ) async {
    if (pickedFiles == null) return;

    setState(() {
      _isImporting = true;
    });

    _importMaxProgress = 0;

    final List<String> allPhotosBefore = await DB.instance.getAllPhotoPathsByProjectID(widget.projectId);
    final int photoCountBeforeImport = allPhotosBefore.length;

    final List<File> files = pickedFiles.paths.map((path) => File(path!)).toList();
    for (File file in files) {
      await processFileCallback(file);
    }

    if (photoCountBeforeImport == 0) {
      print("[processPickedFiles] photoCountBeforeImport == 0 is true");

      String? importedPhotosOrientation = await DB.instance.checkPhotoOrientationThreshold(widget.projectId);
      if (importedPhotosOrientation == 'landscape') {
        print("[processPickedFiles] importedPhotosOrientation == 'landscape' is true");

        DB.instance.setSettingByTitle("project_orientation", 'landscape', projectIdStr);
        DB.instance.setSettingByTitle("aspect_ratio", "4:3", projectIdStr);
      } else {
        print("[processPickedFiles] importedPhotosOrientation == 'landscape' NOT true. importedPhotosOrientation = ${importedPhotosOrientation}");
      }
    }

    setState(() {
      _isImporting = false;
      progressPercent = 0;
    });

    _importMaxProgress = 0;
  }

  void setProgressInMain(int progressIn) {
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
      progressPercent = next;
    });
  }

  Future<void> _startStabilization() async {
    if (_inStabCall) return;
    _inStabCall = true;

    FaceStabilizer? faceStabilizer;

    try {
      await WakelockPlus.enable();

      faceStabilizer = FaceStabilizer(widget.projectId, userRanOutOfSpaceCallback);
      final List<Map<String, dynamic>> unstabilizedPhotos = await StabUtils.getUnstabilizedPhotos(widget.projectId);
      _totalPhotoCountForProgress = (await DB.instance.getPhotosByProjectID(widget.projectId)).length;
      _stabilizedAtStart = await getStabilizedPhotoCount();
      _successfullyStabilizedPhotos = 0;

      // Wait for previous stabilization cycle to cancel
      while (_cancelStabilization && _stabilizingActive) {
        await Future.delayed(const Duration(seconds: 1));
      }

      // Lists to collect scores for mean calculation
      List<double> preScores = [];
      List<double> twoPassScores = [];
      List<double> threePassScores = [];
      List<double> fourPassScores = [];

      if (unstabilizedPhotos.isNotEmpty) {
        if (mounted) {
          setState(() {
            _stabilizingActive = true;
            _unstabilizedPhotoCount = unstabilizedPhotos.length;
          });
        }

        while (_isImporting) {
          await Future.delayed(const Duration(seconds: 1));
        }

        int photosDone = 0;
        int length = unstabilizedPhotos.length;
        Stopwatch stopwatch = Stopwatch();
        stopwatch.start();

        for (Map<String, dynamic> photo in unstabilizedPhotos) {
          if (_cancelStabilization) {
            if (mounted) {
              setState(() => _cancelStabilization = false);
            }
            break;
          }

          Stopwatch loopStopwatch = Stopwatch();
          loopStopwatch.start();

          print("\nStabilizing new photo...:");

          final StabilizationResult result = await _stabilizePhoto(faceStabilizer, photo);

          // Collect scores for mean calculation
          if (result.preScore != null) {
            preScores.add(result.preScore!);
          }
          if (result.twoPassScore != null) {
            twoPassScores.add(result.twoPassScore!);
          }
          if (result.threePassScore != null) {
            threePassScores.add(result.threePassScore!);
          }
          if (result.fourPassScore != null) {
            fourPassScores.add(result.fourPassScore!);
          }

          loopStopwatch.stop();

          photosDone++;
          double averageTimePerLoop = stopwatch.elapsedMilliseconds / photosDone;
          int remainingPhotos = length - photosDone;
          double estimatedTimeRemaining = averageTimePerLoop * remainingPhotos;

          int hours = (estimatedTimeRemaining ~/ (1000 * 60 * 60)).toInt();
          int minutes = ((estimatedTimeRemaining % (1000 * 60 * 60)) ~/ (1000 * 60)).toInt();
          int seconds = ((estimatedTimeRemaining % (1000 * 60)) ~/ 1000).toInt();

          String timeDisplay = hours > 0
              ? "${hours}h ${minutes}m ${seconds}s"
              : "${minutes}m ${seconds}s";
          if (mounted) {
            setState(() => minutesRemaining = timeDisplay);
          }
          print("Estimated time remaining: $timeDisplay");
        }

        stopwatch.stop();

        // Print mean scores at end of stabilization
        _printMeanScores(preScores, twoPassScores, threePassScores, fourPassScores);
      }

      await _finalCheck(faceStabilizer);

      if (mounted) {
        setState(() {
          _photoIndex = 0;
          _stabilizingActive = false;
          progressPercent = 0;
        });
      }

      if (!_cancelStabilization) {
        await _createTimelapse(faceStabilizer);
      }

      if (mounted) {
        setState(() => _cancelStabilization = false);
      }
    } finally {
      await faceStabilizer?.dispose();
      await WakelockPlus.disable();
      _inStabCall = false;
    }
  }

  void _printMeanScores(List<double> preScores, List<double> twoPassScores, List<double> threePassScores, List<double> fourPassScores) {
    if (preScores.isEmpty) {
      print("\n========== STABILIZATION SCORE SUMMARY ==========");
      print("No scores collected (no photos stabilized or non-face project)");
      print("==================================================\n");
      return;
    }

    final double preMean = preScores.reduce((a, b) => a + b) / preScores.length;

    print("\n========== STABILIZATION SCORE SUMMARY ==========");
    print("First-pass mean score:  ${preMean.toStringAsFixed(3)} (n=${preScores.length})");

    if (twoPassScores.isNotEmpty) {
      final double twoPassMean = twoPassScores.reduce((a, b) => a + b) / twoPassScores.length;
      print("Two-pass mean score:    ${twoPassMean.toStringAsFixed(3)} (n=${twoPassScores.length})");
      print("  -> Improvement from first: ${(preMean - twoPassMean).toStringAsFixed(3)} (${((preMean - twoPassMean) / preMean * 100).toStringAsFixed(1)}%)");

      if (threePassScores.isNotEmpty) {
        final double threePassMean = threePassScores.reduce((a, b) => a + b) / threePassScores.length;
        print("Three-pass mean score:  ${threePassMean.toStringAsFixed(3)} (n=${threePassScores.length})");
        print("  -> Improvement from two-pass: ${(twoPassMean - threePassMean).toStringAsFixed(3)} (${((twoPassMean - threePassMean) / twoPassMean * 100).toStringAsFixed(1)}%)");

        if (fourPassScores.isNotEmpty) {
          final double fourPassMean = fourPassScores.reduce((a, b) => a + b) / fourPassScores.length;
          print("Four-pass mean score:   ${fourPassMean.toStringAsFixed(3)} (n=${fourPassScores.length})");
          print("  -> Improvement from three-pass: ${(threePassMean - fourPassMean).toStringAsFixed(3)} (${((threePassMean - fourPassMean) / threePassMean * 100).toStringAsFixed(1)}%)");
          print("  -> Total improvement: ${(preMean - fourPassMean).toStringAsFixed(3)} (${((preMean - fourPassMean) / preMean * 100).toStringAsFixed(1)}%)");
        } else {
          print("Four-pass mean score:   N/A (no four-pass corrections needed)");
          print("  -> Total improvement: ${(preMean - threePassMean).toStringAsFixed(3)} (${((preMean - threePassMean) / preMean * 100).toStringAsFixed(1)}%)");
        }
      } else {
        print("Three-pass mean score:  N/A (no three-pass corrections needed)");
        print("Four-pass mean score:   N/A (no four-pass corrections needed)");
      }
    } else {
      print("Two-pass mean score:    N/A (no two-pass corrections needed)");
      print("Three-pass mean score:  N/A (no three-pass corrections needed)");
      print("Four-pass mean score:   N/A (no four-pass corrections needed)");
    }
    print("==================================================\n");
  }

  Future<StabilizationResult> _stabilizePhoto(FaceStabilizer faceStabilizer, Map<String, dynamic> photo) async {
    try {
      final String rawPhotoPath = await _getRawPhotoPathFromTimestamp(photo['timestamp']);
      final StabilizationResult result = await faceStabilizer.stabilize(
          rawPhotoPath,
          _cancelStabilization,
          userRanOutOfSpaceCallback
      );

      if (result.success) setState(() => _successfullyStabilizedPhotos++);

      return result;
    } catch (e) {
      return StabilizationResult(success: false);
    } finally {
      if (mounted) {
        setState(() => _photoIndex++);
      }

      final int total = _totalPhotoCountForProgress;
      final int completed = _stabilizedAtStart + _successfullyStabilizedPhotos;

      if (total > 0) {
        int pct = ((completed * 100) ~/ total);
        if (pct >= 100) pct = 99;
        if (pct < 0) pct = 0;

        if (mounted) {
          setState(() => progressPercent = pct);
        }
      }
    }
  }

  Future<String> _getRawPhotoPathFromTimestamp(String timestamp) async {
    return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, widget.projectId);
  }

  Future<void> _finalCheck(FaceStabilizer faceStabilizer) async {
    final projectOrientation = await SettingsUtil.loadProjectOrientation(projectIdStr);
    final offsetX = await SettingsUtil.loadOffsetXCurrentOrientation(projectIdStr);
    final allPhotos = await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation);

    final columnName = projectOrientation == 'portrait'
        ? "stabilizedPortraitOffsetX"
        : "stabilizedLandscapeOffsetX";

    for (var photo in allPhotos) {
      if (photo[columnName] != offsetX) {
        await _reStabilizePhoto(faceStabilizer, photo);
      }
    }
  }

  Future<void> _reStabilizePhoto(FaceStabilizer faceStabilizer, Map<String, dynamic> photo) async {
    await DB.instance.resetStabilizedColumnByTimestamp(
      await SettingsUtil.loadProjectOrientation(projectIdStr),
      photo['timestamp'],
    );
    try {
      final rawPhotoPath = path.join(
        await DirUtils.getRawPhotoDirPath(widget.projectId),
        "${photo['timestamp']}${photo['fileExtension']}",
      );
      final result = await faceStabilizer.stabilize(rawPhotoPath, _cancelStabilization, userRanOutOfSpaceCallback);
      if (result.success) setState(() => _successfullyStabilizedPhotos++);
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<int> getStabilizedPhotoCount() async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    return (await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation)).length;
  }

  Future<bool> _createTimelapse(FaceStabilizer faceStabilizer) async {
    try {
      final newestVideo = await DB.instance.getNewestVideoByProjectId(widget.projectId);
      final bool videoIsNull = newestVideo == null;
      final bool settingsHaveChanged = await faceStabilizer.videoSettingsChanged();
      final bool newPhotosStabilized = _successfullyStabilizedPhotos > 0;
      final int stabPhotoCount = await getStabilizedPhotoCount();
      final int? newVideoNeededRaw = await DB.instance.getNewVideoNeeded(widget.projectId);
      final bool newVideoNeeded = newVideoNeededRaw == 1;

      if (newVideoNeeded || ((videoIsNull || settingsHaveChanged || newPhotosStabilized) && stabPhotoCount > 1)) {
        setState(() => _videoCreationActive = true);
        final bool videoCreationRes = await VideoUtils.createTimelapseFromProjectId(
          widget.projectId,
          _setCurrentFrame
        );

        if (newVideoNeeded) {
          DB.instance.setNewVideoNotNeeded(widget.projectId);
        }

        // If videoCreatingRes is false here, that means a video was needed but
        // it failed to build. In this case, we need to display an error to the user.

        return videoCreationRes;
      }

      return false;
    } catch (e) {
      return false;
    } finally {
      setState(() {
        _photoIndex = 0;
        _videoCreationActive = false;
        _successfullyStabilizedPhotos = 0;
      });
    }
  }

  void _setCurrentFrame(int currFrame) {
    setState(() => _currentFrame = currFrame);
    updateProgressPercent();
  }

  Future<void> updateProgressPercent() async {
    try {
      final int stabPhotoCount = await getStabilizedPhotoCount();
      final double percentUnrounded = _currentFrame / stabPhotoCount * 100;
      setState(() {
        progressPercent = percentUnrounded.toInt();
      });
    } catch(_) {
      print("Error caught during updateProgressPercent");
    }
  }

  void _hideFlashingCircle() {
    setState(() => _showFlashingCircle = false);
  }

  Future<void> _cancelStabilizationProcess() async {
    print("_cancelStabilizationProcess called");

    if (_stabilizingActive) {
      setState(() {
      _cancelStabilization = true;
      _videoCreationActive = false;
      _photoIndex = 0;
      progressPercent = 0;
      });
    }

    while (_stabilizingActive) {
      await Future.delayed(const Duration(seconds: 1));
    }
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    if (!_stabilizingActive && !_videoCreationActive && !_isImporting) {
      _startStabilization();
    }
  }

  void openGallery() => _onItemTapped(3);
  bool onCreatePageDuringLoading() => _selectedIndex == 3 && !_hideNavBar;

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
    if (_selectedIndex == 0 || _selectedIndex == 4 || onCreatePageDuringLoading()) {
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
      );
    }

    bool navbarShouldBeHidden() {
      return _selectedIndex == 3 && _hideNavBar && !_stabilizingActive && !_videoCreationActive && photoCount > 1;
    }

    return Scaffold(
      body: Column(
        children: [
          if (appBar != null) appBar,
          Expanded(
            child: _widgetOptions.elementAt(_selectedIndex),
          ),
        ],
      ),
      bottomNavigationBar: navbarShouldBeHidden()
          ? null
          : Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade800,
              width: 0.7,
            ),
          ),
        ),
        child: AnimatedBottomNavigationBar.builder(
          itemCount: iconList.length,
          tabBuilder: (int index, bool isActive) {
            final color = isActive ? AppColors.lightBlue : Colors.grey[300];
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconList[index],
                  size: 24,
                  color: color,
                ),
              ],
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