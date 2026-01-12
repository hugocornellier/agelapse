import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/database_helper.dart';
import '../../services/face_stabilizer.dart';
import '../../styles/styles.dart';
import '../../utils/dir_utils.dart';
import '../../utils/utils.dart';
import '../../utils/camera_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/date_stamp_utils.dart';
import '../../utils/capture_timezone.dart';
import '../manual_stab_page.dart';
import '../stab_on_diff_face.dart';
import 'gallery_widgets.dart';

class ImagePreviewNavigator extends StatefulWidget {
  final List<String> rawImageFiles;
  final List<String> stabilizedImageFiles;
  final int initialIndex;
  final bool initialIsRaw;
  final int projectId;
  final String projectOrientation;
  final VoidCallback stabCallback;
  final VoidCallback userRanOutOfSpaceCallback;
  final bool stabilizingRunningInMain;
  final Future<void> Function() loadImages;

  const ImagePreviewNavigator({
    super.key,
    required this.rawImageFiles,
    required this.stabilizedImageFiles,
    required this.initialIndex,
    required this.initialIsRaw,
    required this.projectId,
    required this.projectOrientation,
    required this.stabCallback,
    required this.userRanOutOfSpaceCallback,
    required this.stabilizingRunningInMain,
    required this.loadImages,
  });

  @override
  State<ImagePreviewNavigator> createState() => _ImagePreviewNavigatorState();
}

class _ImagePreviewNavigatorState extends State<ImagePreviewNavigator> {
  late PageController _pageController;
  late int _currentIndex;
  late bool _isRaw;
  final FocusNode _focusNode = FocusNode();

  // Download button states
  bool _gallerySaveIsLoading = false;
  bool _gallerySaveSuccessful = false;

  // Active button state for raw/stabilized toggle
  String _activeButton = 'raw';

  // Cache for image dimensions
  final Map<String, Size> _dimensionsCache = {};

  // Cache for photo metadata
  Future<Map<String, dynamic>?>? _previewPhotoFuture;

  // Export date stamp preview settings
  bool _exportDateStampEnabled = false;
  String _exportDateStampPosition = DateStampUtils.positionLowerRight;
  String _exportDateStampFormat = DateStampUtils.exportFormatLong;
  int _exportDateStampSize = DateStampUtils.defaultSizePercent;
  double _exportDateStampOpacity = DateStampUtils.defaultOpacity;

  // Cache for capture timezone offsets (timestamp -> offset minutes)
  Map<String, int?> _captureOffsetMap = {};

  @override
  void initState() {
    super.initState();
    _isRaw = widget.initialIsRaw;
    _activeButton = _isRaw ? 'raw' : widget.projectOrientation.toLowerCase();
    _currentIndex = widget.initialIndex.clamp(0, _currentList.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadPhotoMetadata();
    _loadDateStampSettings();
    _loadCaptureOffsets();
  }

  Future<void> _loadDateStampSettings() async {
    final projectIdStr = widget.projectId.toString();
    final enabled = await SettingsUtil.loadExportDateStampEnabled(projectIdStr);
    final position = await SettingsUtil.loadExportDateStampPosition(
      projectIdStr,
    );
    final format = await SettingsUtil.loadExportDateStampFormat(projectIdStr);
    final size = await SettingsUtil.loadExportDateStampSize(projectIdStr);
    final opacity = await SettingsUtil.loadExportDateStampOpacity(projectIdStr);
    if (mounted) {
      setState(() {
        _exportDateStampEnabled = enabled;
        _exportDateStampPosition = position;
        _exportDateStampFormat = format;
        _exportDateStampSize = size;
        _exportDateStampOpacity = opacity;
      });
    }
  }

  /// Load capture timezone offsets for all images in both lists.
  Future<void> _loadCaptureOffsets() async {
    try {
      final offsets = await CaptureTimezone.loadOffsetsForMultipleLists([
        widget.rawImageFiles,
        widget.stabilizedImageFiles,
      ], widget.projectId);

      if (mounted) {
        setState(() => _captureOffsetMap = offsets);
      }
    } catch (e) {
      // Graceful degradation: continue with empty map (falls back to local time)
    }
  }

  @override
  void didUpdateWidget(covariant ImagePreviewNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload offsets if image lists changed
    if (widget.rawImageFiles != oldWidget.rawImageFiles ||
        widget.stabilizedImageFiles != oldWidget.stabilizedImageFiles) {
      _loadCaptureOffsets();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> get _currentList =>
      _isRaw ? widget.rawImageFiles : widget.stabilizedImageFiles;

  bool get _canGoNext => _currentIndex < _currentList.length - 1;
  bool get _canGoPrevious => _currentIndex > 0;

  String get _currentTimestamp {
    if (_currentIndex >= 0 && _currentIndex < _currentList.length) {
      return path.basenameWithoutExtension(_currentList[_currentIndex]);
    }
    return '';
  }

  String get _currentImagePath {
    if (_currentIndex >= 0 && _currentIndex < _currentList.length) {
      return _currentList[_currentIndex];
    }
    return '';
  }

  void _loadPhotoMetadata() {
    if (_currentTimestamp.isNotEmpty) {
      _previewPhotoFuture = DB.instance.getPhotoByTimestamp(
        _currentTimestamp,
        widget.projectId,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _gallerySaveSuccessful = false;
    });
    _loadPhotoMetadata();
  }

  void _goToNext() {
    if (_canGoNext) {
      _pageController.animateToPage(
        _currentIndex + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPrevious() {
    if (_canGoPrevious) {
      _pageController.animateToPage(
        _currentIndex - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  int _findIndexForTimestamp(List<String> targetList, String timestamp) {
    return targetList.indexWhere(
      (p) => path.basenameWithoutExtension(p) == timestamp,
    );
  }

  Future<void> _switchToRaw() async {
    final currentTimestamp = _currentTimestamp;
    final newIndex = _findIndexForTimestamp(
      widget.rawImageFiles,
      currentTimestamp,
    );

    if (newIndex >= 0) {
      setState(() {
        _isRaw = true;
        _activeButton = 'raw';
        _currentIndex = newIndex;
      });
      _pageController.jumpToPage(newIndex);
    }
  }

  Future<void> _switchToStabilized() async {
    final currentTimestamp = _currentTimestamp;
    final newIndex = _findIndexForTimestamp(
      widget.stabilizedImageFiles,
      currentTimestamp,
    );

    if (newIndex >= 0) {
      setState(() {
        _isRaw = false;
        _activeButton = widget.projectOrientation.toLowerCase();
        _currentIndex = newIndex;
      });
      _pageController.jumpToPage(newIndex);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stabilized image not available')),
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _goToPrevious();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _goToNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<Size> _getImageDimensions(String imagePath) async {
    if (_dimensionsCache.containsKey(imagePath)) {
      return _dimensionsCache[imagePath]!;
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return const Size(0, 0);
      }
      final Uint8List bytes = await file.readAsBytes();
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(bytes, completer.complete);
      final image = await completer.future;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      _dimensionsCache[imagePath] = size;
      return size;
    } catch (e) {
      return const Size(0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.settingsBackground,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    _buildPageView(),
                    if (isDesktop) ...[
                      if (_canGoPrevious) _buildLeftArrow(),
                      if (_canGoNext) _buildRightArrow(),
                    ],
                  ],
                ),
              ),
              _buildPageCounter(),
              _buildActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      color: AppColors.settingsCardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.access_time_outlined,
            size: 18,
            color: AppColors.settingsTextSecondary,
          ),
          const SizedBox(width: 8),
          FutureBuilder<Map<String, dynamic>?>(
            future: _previewPhotoFuture,
            builder: (context, snap) {
              final int? off = CaptureTimezone.extractOffset(snap.data);
              final timestamp = _currentTimestamp;
              if (timestamp.isEmpty) {
                return const SizedBox.shrink();
              }
              return Text(
                Utils.formatUnixTimestampPlatformAware(
                  int.parse(timestamp),
                  captureOffsetMinutes: off,
                ),
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 14,
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBorder,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FutureBuilder<Size>(
              future: _getImageDimensions(_currentImagePath),
              builder: (context, snap) {
                if (!snap.hasData || snap.data == const Size(0, 0)) {
                  return const SizedBox.shrink();
                }
                return Text(
                  '${snap.data!.width.toInt()}x${snap.data!.height.toInt()}',
                  style: TextStyle(
                    color: AppColors.settingsTextSecondary,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          const Spacer(),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBorder,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.close,
            color: AppColors.settingsTextPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildPageView() {
    if (_currentList.isEmpty) {
      return Center(
        child: Text(
          'No images available',
          style: TextStyle(color: AppColors.settingsTextSecondary),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _currentList.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => _buildImagePage(index),
    );
  }

  Widget _buildImagePage(int index) {
    final imagePath = _currentList[index];

    if (!_isRaw && _activeButton != 'raw') {
      // Show stabilized image with status handling
      Widget imageWidget = StabilizedImagePreview(
        thumbnailPath: FaceStabilizer.getStabThumbnailPath(imagePath),
        imagePath: imagePath,
        projectId: widget.projectId,
        buildImage: _buildResizableImage,
      );

      // Add date stamp overlay preview if enabled
      if (_exportDateStampEnabled) {
        final timestamp = path.basenameWithoutExtension(imagePath);
        final timestampMs = int.tryParse(timestamp);
        if (timestampMs != null) {
          final formattedDate = DateStampUtils.formatTimestamp(
            timestampMs,
            _exportDateStampFormat,
            captureOffsetMinutes: _captureOffsetMap[timestamp],
          );
          imageWidget = _buildImageWithDateOverlay(imageWidget, formattedDate);
        }
      }

      return Center(child: imageWidget);
    } else {
      // Show raw image
      return Center(child: _buildResizableImage(File(imagePath)));
    }
  }

  Widget _buildImageWithDateOverlay(Widget imageWidget, String dateText) {
    // Calculate position based on setting
    Alignment alignment;
    switch (_exportDateStampPosition.toLowerCase()) {
      case DateStampUtils.positionLowerRight:
        alignment = Alignment.bottomRight;
        break;
      case DateStampUtils.positionLowerLeft:
        alignment = Alignment.bottomLeft;
        break;
      case DateStampUtils.positionUpperRight:
        alignment = Alignment.topRight;
        break;
      case DateStampUtils.positionUpperLeft:
        alignment = Alignment.topLeft;
        break;
      default:
        alignment = Alignment.bottomRight;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate proportional font size to match export appearance
        // Export uses sizePercent of image height; preview uses constraints
        final previewFontSize =
            (constraints.maxHeight * _exportDateStampSize / 100).clamp(
          10.0,
          24.0,
        );

        return Stack(
          children: [
            imageWidget,
            Positioned.fill(
              child: Align(
                alignment: alignment,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dateText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: previewFontSize,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 2,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResizableImage(File imageFile) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(color: Colors.black),
      ),
    );
  }

  Widget _buildLeftArrow() {
    return Positioned(
      left: 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: _buildArrowButton(
          icon: Icons.chevron_left,
          onPressed: _goToPrevious,
        ),
      ),
    );
  }

  Widget _buildRightArrow() {
    return Positioned(
      right: 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: _buildArrowButton(
          icon: Icons.chevron_right,
          onPressed: _goToNext,
        ),
      ),
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.settingsTextPrimary, size: 28),
        ),
      ),
    );
  }

  Widget _buildPageCounter() {
    if (_currentList.length <= 1) {
      return const SizedBox(height: 8);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${_currentIndex + 1} of ${_currentList.length}',
        style: TextStyle(color: AppColors.settingsTextSecondary, fontSize: 14),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        border: Border(
          top: BorderSide(color: AppColors.settingsDivider, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildDownloadButton(),
          _buildStabilizeToggleButton(),
          _buildRawToggleButton(),
          _buildMoreOptionsButton(),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return _buildActionButton(
      icon: _gallerySaveIsLoading
          ? Icons.hourglass_top
          : (_gallerySaveSuccessful ? Icons.check : Icons.download),
      active: _gallerySaveSuccessful,
      activeColor: Colors.greenAccent,
      onPressed: _gallerySaveIsLoading ? null : _saveImage,
    );
  }

  Widget _buildStabilizeToggleButton() {
    final bool isStabilizedActive =
        _activeButton == widget.projectOrientation.toLowerCase();
    return _buildActionButton(
      icon: Icons.video_stable,
      active: isStabilizedActive,
      onPressed: isStabilizedActive ? null : _switchToStabilized,
    );
  }

  Widget _buildRawToggleButton() {
    return _buildActionButton(
      icon: Icons.raw_on,
      active: _activeButton == 'raw',
      iconSize: 25,
      onPressed: _activeButton == 'raw' ? null : _switchToRaw,
    );
  }

  Widget _buildMoreOptionsButton() {
    return _buildActionButton(
      icon: Icons.more_vert,
      onPressed: _showOptionsMenu,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    VoidCallback? onPressed,
    bool active = false,
    Color activeColor = AppColors.settingsAccent,
    double iconSize = 22,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.15)
                : AppColors.settingsCardBorder,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: active ? activeColor : AppColors.settingsTextPrimary,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage() async {
    if (_currentImagePath.isEmpty) return;

    setState(() => _gallerySaveIsLoading = true);

    String? tempFile;
    try {
      String imagePathToSave = _currentImagePath;
      final originalFilename = path.basename(_currentImagePath);

      // Apply date stamp if enabled (only for stabilized images)
      if (_exportDateStampEnabled && !_isRaw) {
        final timestamp = path.basenameWithoutExtension(_currentImagePath);
        final timestampMs = int.tryParse(timestamp);
        if (timestampMs != null) {
          // Get captureOffsetMinutes from photo metadata for accurate timezone
          final photoData = await _previewPhotoFuture;
          final int? captureOffsetMinutes = CaptureTimezone.extractOffset(
            photoData,
          );

          final formattedDate = DateStampUtils.formatTimestamp(
            timestampMs,
            _exportDateStampFormat,
            captureOffsetMinutes: captureOffsetMinutes,
          );

          // Load watermark settings for overlap prevention
          final projectIdStr = widget.projectId.toString();
          final watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
            projectIdStr,
          );
          final String? watermarkPos = watermarkEnabled
              ? (await DB.instance.getSettingValueByTitle(
                  'watermark_position',
                ))
                  .toLowerCase()
              : null;

          // Calculate watermark offset if both are in same position
          double watermarkOffset = 0.0;
          if (watermarkPos != null &&
              _exportDateStampPosition.toLowerCase() ==
                  watermarkPos.toLowerCase()) {
            final isLowerCorner =
                _exportDateStampPosition.toLowerCase().contains('lower');
            watermarkOffset = isLowerCorner ? -60.0 : 60.0;
          }

          // Create temp file for date-stamped image (use original filename)
          final tempDir = await getTemporaryDirectory();
          tempFile = '${tempDir.path}/$originalFilename';

          final success = await DateStampUtils.compositeDate(
            inputPath: _currentImagePath,
            outputPath: tempFile,
            dateText: formattedDate,
            position: _exportDateStampPosition,
            sizePercent: _exportDateStampSize,
            opacity: _exportDateStampOpacity,
            watermarkVerticalOffset: watermarkOffset,
          );

          if (success) {
            imagePathToSave = tempFile;
          }
        }
      }

      final XFile image = XFile(imagePathToSave);
      await _saveImageToDownloadsOrGallery(image);
      if (mounted) {
        setState(() {
          _gallerySaveIsLoading = false;
          _gallerySaveSuccessful = true;
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _gallerySaveSuccessful = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gallerySaveIsLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save image: $e')));
      }
    } finally {
      // Clean up temp file
      if (tempFile != null) {
        try {
          await File(tempFile).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _saveImageToDownloadsOrGallery(XFile image) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final bytes = await image.readAsBytes();
      final downloadsPath = await _preferredUserDownloads();
      await _ensureDirExists(downloadsPath);
      final targetPath = await _uniquePath(
        downloadsPath,
        path.basename(image.path),
      );
      try {
        await File(targetPath).writeAsBytes(bytes, flush: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to ${path.normalize(targetPath)}')),
          );
        }
      } on FileSystemException {
        final location = await getSaveLocation(
          suggestedName: path.basename(image.path),
        );
        if (location != null && location.path.isNotEmpty) {
          await File(location.path).writeAsBytes(bytes, flush: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to ${path.normalize(location.path)}'),
              ),
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
      await _checkAndRequestPermissions();
      await CameraUtils.saveToGallery(image);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to Photos')));
      }
    }
  }

  Future<String> _preferredUserDownloads() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final xdgDownload = Platform.environment['XDG_DOWNLOAD_DIR'];
      if (xdgDownload != null && xdgDownload.isNotEmpty) {
        final expanded = xdgDownload.replaceAll(
          '\$HOME',
          Platform.environment['HOME'] ?? '',
        );
        if (expanded.isNotEmpty && await Directory(expanded).exists()) {
          return expanded;
        }
      }
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
    if (d != null) return d.path;
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
    if (!await File(candidate).exists()) return candidate;
    var i = 1;
    while (await File(candidate).exists()) {
      candidate = path.join(dir, '$name($i)$ext');
      i++;
    }
    return candidate;
  }

  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final int sdkInt = androidInfo.version.sdkInt;
      try {
        if (sdkInt >= 33) {
          await Permission.photos.request();
          await Permission.videos.request();
          await Permission.audio.request();
        } else {
          await Permission.storage.request();
        }
      } catch (e) {
        // Ignore permission errors
      }
    }
  }

  Future<void> _showOptionsMenu() async {
    if (_currentImagePath.isEmpty) return;

    final imageFile = File(_currentImagePath);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMenuItem(
                icon: Icons.calendar_today,
                title: 'Change Date',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _showChangeDateDialog();
                },
              ),
              const Divider(height: 1, color: AppColors.settingsDivider),
              _buildMenuItem(
                icon: Icons.video_stable,
                title: 'Stabilize on Other Faces',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _navigateToStabDiffFace(imageFile);
                },
              ),
              const Divider(height: 1, color: AppColors.settingsDivider),
              _buildMenuItem(
                icon: Icons.refresh,
                title: 'Retry Stabilization',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _retryStabilization();
                },
              ),
              const Divider(height: 1, color: AppColors.settingsDivider),
              _buildMenuItem(
                icon: Icons.photo,
                title: 'Set as Guide Photo',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _setAsGuidePhoto();
                },
              ),
              const Divider(height: 1, color: AppColors.settingsDivider),
              _buildMenuItem(
                icon: Icons.handyman,
                title: 'Manual Stabilization',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _navigateToManualStabilization(imageFile);
                },
              ),
              const Divider(height: 1, color: AppColors.settingsDivider),
              _buildMenuItem(
                icon: Icons.delete,
                title: 'Delete Image',
                iconColor: Colors.red,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _showDeleteDialog(imageFile);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? AppColors.settingsTextSecondary,
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 14, color: AppColors.settingsTextPrimary),
      ),
      onTap: onTap,
    );
  }

  Future<void> _showChangeDateDialog() async {
    final timestamp = _currentTimestamp;
    if (timestamp.isEmpty) return;

    DateTime initialDate = DateTime.fromMillisecondsSinceEpoch(
      int.parse(timestamp),
    );
    DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (newDate == null || !mounted) return;

    TimeOfDay initialTime = TimeOfDay.fromDateTime(initialDate);
    TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (newTime == null || !mounted) return;

    DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );
    String newTimestamp = newDateTime.millisecondsSinceEpoch.toString();
    await _changePhotoDate(timestamp, newTimestamp);
  }

  Future<void> _changePhotoDate(
    String currentTimestamp,
    String newTimestamp,
  ) async {
    // Update database
    await DB.instance.updatePhotoTimestamp(
      currentTimestamp,
      newTimestamp,
      widget.projectId,
    );

    // Rename files
    await _renamePhotoFiles(currentTimestamp, newTimestamp);

    // Reload images and close navigator
    await widget.loadImages();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo date updated')));
    }
  }

  Future<void> _renamePhotoFiles(
    String currentTimestamp,
    String newTimestamp,
  ) async {
    // Get all paths for the current photo
    final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      currentTimestamp,
      widget.projectId,
    );

    if (await File(rawPath).exists()) {
      final newRawPath = rawPath.replaceAll(currentTimestamp, newTimestamp);
      await File(rawPath).rename(newRawPath);
    }

    // Rename stabilized and thumbnail files if they exist
    final stabPath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      widget.projectId,
      rawPath,
      widget.projectOrientation,
    );
    if (await File(stabPath).exists()) {
      final newStabPath = stabPath.replaceAll(currentTimestamp, newTimestamp);
      await File(stabPath).rename(newStabPath);
    }

    final thumbPath = FaceStabilizer.getStabThumbnailPath(stabPath);
    if (await File(thumbPath).exists()) {
      final newThumbPath = thumbPath.replaceAll(currentTimestamp, newTimestamp);
      await File(thumbPath).rename(newThumbPath);
    }
  }

  void _navigateToStabDiffFace(File imageFile) {
    final screen = StabDiffFacePage(
      projectId: widget.projectId,
      imageTimestamp: path.basenameWithoutExtension(imageFile.path),
      reloadImagesInGallery: widget.loadImages,
      stabCallback: widget.stabCallback,
      userRanOutOfSpaceCallback: widget.userRanOutOfSpaceCallback,
      stabilizationRunningInMain: widget.stabilizingRunningInMain,
    );
    Utils.navigateToScreenReplace(context, screen);
  }

  Future<void> _retryStabilization() async {
    final timestamp = _currentTimestamp;
    if (timestamp.isEmpty) return;

    final rawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      widget.projectId,
    );
    final stabilizedImagePath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      widget.projectId,
      rawPhotoPath,
      widget.projectOrientation,
    );
    final stabThumbPath = FaceStabilizer.getStabThumbnailPath(
      stabilizedImagePath,
    );

    final stabImageFile = File(stabilizedImagePath);
    final stabThumbFile = File(stabThumbPath);
    if (await stabImageFile.exists()) {
      await stabImageFile.delete();
    }
    if (await stabThumbFile.exists()) {
      await stabThumbFile.delete();
    }

    await DB.instance.resetStabilizedColumnByTimestamp(
      widget.projectOrientation,
      timestamp,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retrying stabilization...')),
      );
    }

    widget.stabCallback();
  }

  Future<void> _setAsGuidePhoto() async {
    final timestamp = _currentTimestamp;
    if (timestamp.isEmpty) return;

    final photoRecord = await DB.instance.getPhotoByTimestamp(
      timestamp,
      widget.projectId,
    );
    if (photoRecord != null) {
      await DB.instance.setSettingByTitle(
        "selected_guide_photo",
        photoRecord['id'].toString(),
        widget.projectId.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Guide photo updated')));
      }
    }
  }

  void _navigateToManualStabilization(File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManualStabilizationPage(
          imagePath: imageFile.path,
          projectId: widget.projectId,
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(File imageFile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          title: Text(
            'Delete Image?',
            style: TextStyle(color: AppColors.settingsTextPrimary),
          ),
          content: Text(
            'Do you want to delete this image?',
            style: TextStyle(color: AppColors.settingsTextSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _deleteImage(imageFile);
    }
  }

  Future<void> _deleteImage(File imageFile) async {
    final isStabilizedImage = imageFile.path.toLowerCase().contains(
          "stabilized",
        );
    File toDelete = imageFile;

    if (isStabilizedImage) {
      final timestamp = path.basenameWithoutExtension(imageFile.path);
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        widget.projectId,
      );
      toDelete = File(rawPhotoPath);
    }

    final timestamp = path.basenameWithoutExtension(toDelete.path);

    // Delete all related files
    await _deleteAllRelatedFiles(toDelete);

    // Remove from database
    await DB.instance.deletePhoto(int.parse(timestamp));

    // Reload images
    await widget.loadImages();

    // Navigate to adjacent or close if no images left
    if (_currentList.isEmpty) {
      if (mounted) Navigator.of(context).pop();
    } else {
      final newIndex = _currentIndex.clamp(0, _currentList.length - 1);
      setState(() => _currentIndex = newIndex);
      _pageController.jumpToPage(newIndex);
    }
  }

  Future<void> _deleteAllRelatedFiles(File rawFile) async {
    // Delete raw file
    if (await rawFile.exists()) {
      await rawFile.delete();
    }

    // Delete raw thumbnail
    final rawThumbPath = rawFile.path
        .replaceAll(DirUtils.photosRawDirname, DirUtils.thumbnailDirname)
        .replaceAll(path.extension(rawFile.path), '.jpg');
    if (await File(rawThumbPath).exists()) {
      await File(rawThumbPath).delete();
    }

    // Delete stabilized image and thumbnail
    final stabPath =
        await DirUtils.getStabilizedImagePathFromRawPathAndProjectOrientation(
      widget.projectId,
      rawFile.path,
      widget.projectOrientation,
    );
    if (await File(stabPath).exists()) {
      await File(stabPath).delete();
    }

    final stabThumbPath = FaceStabilizer.getStabThumbnailPath(stabPath);
    if (await File(stabThumbPath).exists()) {
      await File(stabThumbPath).delete();
    }
  }
}
