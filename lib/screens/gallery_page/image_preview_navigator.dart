import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
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
import '../../utils/gallery_photo_operations.dart';
import '../../utils/gallery_permission_handler.dart';
import '../../utils/platform_utils.dart';
import '../../utils/test_mode.dart' as test_config;
import '../../widgets/format_aware_image.dart';
import '../manual_stab_page.dart';
import '../stab_on_diff_face.dart';
import 'gallery_widgets.dart';
import 'gallery_image_menu.dart';
import '../../widgets/grid_painter_se.dart';

/// Top-level function for compute() - extracts image dimensions from file header.
/// Runs in isolate to avoid blocking UI thread with image decoding.
/// Supports: PNG, JPEG, WebP (VP8/VP8L/VP8X), BMP, GIF.
/// Returns [width, height] as a list, or [0, 0] on failure.
List<int> _extractImageDimensions(String imagePath) {
  try {
    final file = File(imagePath);
    if (!file.existsSync()) return [0, 0];

    // Read first 32KB - enough for any image header
    final raf = file.openSync();
    final headerSize = 32768;
    final actualSize = raf.lengthSync();
    final bytesToRead = actualSize < headerSize ? actualSize : headerSize;
    final bytes = raf.readSync(bytesToRead);
    raf.closeSync();

    if (bytes.length < 30) return [0, 0];

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      // Width at bytes 16-19, height at bytes 20-23 (big-endian)
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return [width, height];
    }

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      for (int i = 2; i < bytes.length - 9; i++) {
        if (bytes[i] == 0xFF) {
          final marker = bytes[i + 1];
          // SOF markers contain dimensions
          if ((marker >= 0xC0 && marker <= 0xC3) ||
              (marker >= 0xC5 && marker <= 0xC7) ||
              (marker >= 0xC9 && marker <= 0xCB) ||
              (marker >= 0xCD && marker <= 0xCF)) {
            final height = (bytes[i + 5] << 8) | bytes[i + 6];
            final width = (bytes[i + 7] << 8) | bytes[i + 8];
            if (width > 0 && height > 0) {
              return [width, height];
            }
          }
          // Skip to next marker
          if (i + 3 < bytes.length &&
              marker != 0x00 &&
              marker != 0xFF &&
              marker != 0xD8 &&
              marker != 0xD9) {
            final segmentLength = (bytes[i + 2] << 8) | bytes[i + 3];
            i += segmentLength + 1;
          }
        }
      }
    }

    // WebP: RIFF....WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      // VP8X (extended format) - most common for modern WebP
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x58) {
        // Canvas dimensions at bytes 24-26 (width-1) and 27-29 (height-1)
        final width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
        final height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
        return [width, height];
      }
      // VP8L (lossless)
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x4C) {
        // Signature byte 0x2F at offset 20, then 28 bits of width/height
        if (bytes.length > 24 && bytes[20] == 0x2F) {
          // Width: bits 0-13, Height: bits 14-27 (little-endian, packed)
          final b1 = bytes[21];
          final b2 = bytes[22];
          final b3 = bytes[23];
          final b4 = bytes[24];
          final width = ((b1 | (b2 << 8)) & 0x3FFF) + 1;
          final height =
              (((b2 >> 6) | (b3 << 2) | ((b4 & 0xF) << 10)) & 0x3FFF) + 1;
          return [width, height];
        }
      }
      // VP8 (lossy) - "VP8 " with space
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x20) {
        // Find keyframe start code: 9D 01 2A
        for (int i = 20; i < bytes.length - 7; i++) {
          if (bytes[i] == 0x9D &&
              bytes[i + 1] == 0x01 &&
              bytes[i + 2] == 0x2A) {
            // Width at i+3 (14 bits), height at i+5 (14 bits), little-endian
            final width = (bytes[i + 3] | (bytes[i + 4] << 8)) & 0x3FFF;
            final height = (bytes[i + 5] | (bytes[i + 6] << 8)) & 0x3FFF;
            if (width > 0 && height > 0) {
              return [width, height];
            }
          }
        }
      }
    }

    // BMP: 42 4D ("BM")
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      // DIB header size at offset 14 determines version
      final dibHeaderSize =
          bytes[14] | (bytes[15] << 8) | (bytes[16] << 16) | (bytes[17] << 24);
      if (dibHeaderSize == 12) {
        // BITMAPCOREHEADER (Windows 2.x / OS/2 1.x) - 16-bit dimensions
        final width = bytes[18] | (bytes[19] << 8);
        final height = bytes[20] | (bytes[21] << 8);
        return [width, height];
      } else if (dibHeaderSize >= 40) {
        // BITMAPINFOHEADER+ (Windows 3.x+) - 32-bit signed dimensions
        int width = bytes[18] |
            (bytes[19] << 8) |
            (bytes[20] << 16) |
            (bytes[21] << 24);
        int height = bytes[22] |
            (bytes[23] << 8) |
            (bytes[24] << 16) |
            (bytes[25] << 24);
        // Handle signed int32 (negative height = top-down DIB)
        if (height & 0x80000000 != 0) {
          height = -((~height + 1) & 0xFFFFFFFF);
        }
        if (width & 0x80000000 != 0) {
          width = -((~width + 1) & 0xFFFFFFFF);
        }
        return [width.abs(), height.abs()];
      }
    }

    // GIF: 47 49 46 38 ("GIF8")
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      // Width at bytes 6-7, height at bytes 8-9 (little-endian)
      final width = bytes[6] | (bytes[7] << 8);
      final height = bytes[8] | (bytes[9] << 8);
      return [width, height];
    }

    // Unsupported format (HEIC, AVIF, TIFF, etc.) - return 0,0 for fallback
    return [0, 0];
  } catch (e) {
    return [0, 0];
  }
}

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
  final Future<void> Function() recompileVideoCallback;
  final ValueNotifier<int>? settingsVersion;
  final bool isEyeBasedProject;
  final bool initialInspectionMode;
  final double eyeOffsetX;
  final double eyeOffsetY;
  final String aspectRatio;

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
    required this.recompileVideoCallback,
    this.settingsVersion,
    this.isEyeBasedProject = false,
    this.initialInspectionMode = false,
    this.eyeOffsetX = 0.065,
    this.eyeOffsetY = 0.421875,
    this.aspectRatio = '9:16',
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

  // Bumped after manual stabilization to force Image widget recreation
  int _imageRefreshKey = 0;

  bool _isInspectionMode = false;

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
  String _exportDateStampFont = DateStampUtils.fontSameAsGallery;
  String _galleryDateStampFont = DateStampUtils.defaultFont;
  int _galleryDateStampSize = DateStampUtils.defaultGallerySizeLevel;
  double _exportDateStampMarginH = 2.0;
  double _exportDateStampMarginV = 2.0;

  // Cache for capture timezone offsets (timestamp -> offset minutes)
  Map<String, int?> _captureOffsetMap = {};

  @override
  void initState() {
    super.initState();
    _isRaw = widget.initialIsRaw;
    _isInspectionMode = widget.initialInspectionMode;
    _activeButton = _isRaw ? 'raw' : widget.projectOrientation.toLowerCase();
    _currentIndex = widget.initialIndex.clamp(0, _currentList.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadPhotoMetadata();
    _loadDateStampSettings();
    _loadCaptureOffsets();
    widget.settingsVersion?.addListener(_loadDateStampSettings);
  }

  Future<void> _loadDateStampSettings() async {
    final settings = await SettingsUtil.loadAllDateStampSettings(
      widget.projectId.toString(),
    );
    if (mounted) {
      setState(() {
        _exportDateStampEnabled = settings.exportEnabled;
        _exportDateStampPosition = settings.exportPosition;
        _exportDateStampFormat = settings.exportFormat;
        _exportDateStampSize = settings.exportSizePercent;
        _exportDateStampOpacity = settings.exportOpacity;
        _exportDateStampFont = settings.exportFont;
        _galleryDateStampFont = settings.galleryFont;
        _galleryDateStampSize = settings.gallerySizeLevel;
        final resolvedMargin = settings.resolvedMargin;
        _exportDateStampMarginH = resolvedMargin.$1;
        _exportDateStampMarginV = resolvedMargin.$2;
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
    widget.settingsVersion?.removeListener(_loadDateStampSettings);
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

  Future<void> _switchView({required bool toRaw}) async {
    final currentTimestamp = _currentTimestamp;
    final targetList =
        toRaw ? widget.rawImageFiles : widget.stabilizedImageFiles;
    final newIndex = _findIndexForTimestamp(targetList, currentTimestamp);

    if (newIndex >= 0) {
      setState(() {
        _isRaw = toRaw;
        _activeButton = toRaw ? 'raw' : widget.projectOrientation.toLowerCase();
        _currentIndex = newIndex;
      });
      _pageController.jumpToPage(newIndex);
    } else if (!toRaw && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stabilized image not available')),
      );
    }
  }

  Future<void> _switchToRaw() => _switchView(toRaw: true);

  Future<void> _switchToStabilized() => _switchView(toRaw: false);

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
      // Fast path: extract dimensions in isolate via header parsing
      // Supports PNG, JPEG, WebP, BMP, GIF
      final dimensions = await compute(_extractImageDimensions, imagePath);
      if (dimensions[0] > 0 && dimensions[1] > 0) {
        final size = Size(dimensions[0].toDouble(), dimensions[1].toDouble());
        _dimensionsCache[imagePath] = size;
        return size;
      }

      // Slow path: main-thread full decode for unsupported formats
      // (HEIC, AVIF, TIFF, etc. that require complex parsing)
      final file = File(imagePath);
      if (!await file.exists()) {
        return const Size(0, 0);
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      _dimensionsCache[imagePath] = size;
      return size;
    } catch (e) {
      return const Size(0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
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
    );

    // On macOS/Linux inside the nested navigator, the persistent title bar is above us
    final usesSafeArea = !hasCustomTitleBar;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.settingsBackground,
        body: usesSafeArea ? SafeArea(child: content) : content,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      color: AppColors.settingsBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.access_time_outlined,
            size: 18,
            color: AppColors.settingsTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: FutureBuilder<Map<String, dynamic>?>(
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
                          fontSize: AppTypography.md,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 12),
                  _buildResolutionBadge(),
                  if (_isInspectionMode && !_isRaw) _buildInspectionModeBadge(),
                ],
              ],
            ),
          ),
          _buildInfoButton(),
          const SizedBox(width: 8),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildResolutionBadge() {
    return Container(
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
              fontSize: AppTypography.sm,
            ),
          );
        },
      ),
    );
  }

  Widget _buildInspectionModeBadge() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          'Inspection Mode',
          style: TextStyle(
            color: const Color(0xFF4CAF50),
            fontSize: AppTypography.sm,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoButton() {
    return _buildIconButton(
      icon: Icons.info_outline,
      size: 40,
      radius: 12,
      bgColor: AppColors.settingsCardBorder,
      iconColor: AppColors.settingsTextPrimary,
      iconSize: 20,
      onTap: _showImageInfoDialog,
    );
  }

  void _showImageInfoDialog() {
    final rawPath =
        _currentIndex >= 0 && _currentIndex < widget.rawImageFiles.length
            ? widget.rawImageFiles[_currentIndex]
            : '';
    final stabPath =
        _currentIndex >= 0 && _currentIndex < widget.stabilizedImageFiles.length
            ? widget.stabilizedImageFiles[_currentIndex]
            : '';

    GalleryImageMenu.showImageInfo(
      context: context,
      timestamp: _currentTimestamp,
      projectId: widget.projectId,
      rawPath: rawPath,
      stabPath: stabPath,
      isInspectionMode: _isInspectionMode,
      isRaw: _isRaw,
      getDimensions: _getImageDimensions,
    );
  }

  Widget _buildCloseButton() {
    return _buildIconButton(
      icon: Icons.close,
      size: 40,
      radius: 12,
      bgColor: AppColors.settingsCardBorder,
      iconColor: AppColors.settingsTextPrimary,
      iconSize: 20,
      onTap: () => Navigator.of(context).pop(),
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
      final timestamp = path.basenameWithoutExtension(imagePath);
      Widget imageWidget = StabilizedImagePreview(
        key: ValueKey('stab_preview_${timestamp}_$_imageRefreshKey'),
        thumbnailPath: FaceStabilizer.getStabThumbnailPath(imagePath),
        imagePath: imagePath,
        projectId: widget.projectId,
        buildImage: _buildResizableImage,
      );

      // Add date stamp overlay preview if enabled
      if (_exportDateStampEnabled) {
        final timestampMs = int.tryParse(timestamp);
        if (timestampMs != null) {
          final formattedDate = DateStampUtils.formatTimestamp(
            timestampMs,
            _exportDateStampFormat,
            captureOffsetMinutes: _captureOffsetMap[timestamp],
          );
          imageWidget = _buildImageWithDateOverlay(
            imageWidget,
            formattedDate,
            imagePath,
          );
        }
      }

      // Always wrap in Stack to keep widget tree stable across inspection toggle
      imageWidget = Stack(
        children: [
          imageWidget,
          if (_isInspectionMode)
            Positioned.fill(
              child: CustomPaint(
                painter: GridPainterSE(
                  widget.eyeOffsetX,
                  widget.eyeOffsetY,
                  null,
                  null,
                  null,
                  widget.aspectRatio,
                  widget.projectOrientation,
                  hideToolTip: true,
                  hideCorners: true,
                ),
              ),
            ),
        ],
      );

      return Center(child: imageWidget);
    } else {
      // Show raw image
      return Center(child: _buildResizableImage(File(imagePath)));
    }
  }

  Widget _buildImageWithDateOverlay(
    Widget imageWidget,
    String dateText,
    String imagePath,
  ) {
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
        // Calculate font size based on ACTUAL image dimensions, matching video output exactly
        // We need to compute what the displayed image height will be
        return FutureBuilder<Size>(
          future: _getImageDimensions(imagePath),
          builder: (context, snapshot) {
            double previewFontSize = 14.0; // Default fallback
            double displayedWidth = 0.0;
            double displayedHeight = 0.0;

            if (snapshot.hasData && snapshot.data != Size.zero) {
              final imageWidth = snapshot.data!.width;
              final imageHeight = snapshot.data!.height;

              // Calculate how image scales to fit container (matching _buildResizableImage constraints)
              final containerMaxWidth = MediaQuery.of(context).size.width * 0.9;
              final containerMaxHeight =
                  MediaQuery.of(context).size.height * 0.65;

              // Compute scale factor (same as BoxFit.contain)
              final scaleX = containerMaxWidth / imageWidth;
              final scaleY = containerMaxHeight / imageHeight;
              final scale = scaleX < scaleY ? scaleX : scaleY;

              displayedWidth = imageWidth * scale;
              displayedHeight = imageHeight * scale;

              // Font size: same formula as video output
              // Video uses: (videoHeight * sizePercent / 100).clamp(12.0, 200.0)
              // For preview, we use displayed height with same percentage
              final resolvedSize = DateStampUtils.resolveExportSize(
                _exportDateStampSize,
                _galleryDateStampSize,
              );
              previewFontSize = (displayedHeight * resolvedSize / 100).clamp(
                10.0,
                48.0,
              );
            }

            // Don't show overlay until dimensions are known (avoids jump)
            if (displayedHeight == 0.0) {
              return imageWidget;
            }

            // Margin matching video/photo export: width-based for H, height-based for V
            final marginH = displayedWidth * _exportDateStampMarginH / 100;
            final marginV = displayedHeight * _exportDateStampMarginV / 100;

            return Stack(
              children: [
                imageWidget,
                Positioned.fill(
                  child: Align(
                    alignment: alignment,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: marginH,
                        right: marginH,
                        top: marginV,
                        bottom: marginV,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.overlay.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dateText,
                          style: TextStyle(
                            fontFamily: DateStampUtils.resolveExportFont(
                              _exportDateStampFont,
                              _galleryDateStampFont,
                            ),
                            color: AppColors.textPrimary,
                            fontSize: previewFontSize,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                offset: const Offset(1, 1),
                                blurRadius: 2,
                                color: AppColors.overlay.withValues(
                                  alpha: 0.54,
                                ),
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
      },
    );
  }

  Widget _buildResizableImage(File imageFile) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: FormatAwareImage(
        key: ValueKey('${imageFile.path}_$_imageRefreshKey'),
        imageFile: imageFile,
        fit: BoxFit.contain,
        errorWidget: Container(color: AppColors.overlay),
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
    return _buildIconButton(
      icon: icon,
      size: 48,
      radius: 24,
      bgColor: AppColors.settingsCardBackground.withValues(alpha: 0.8),
      iconColor: AppColors.settingsTextPrimary,
      iconSize: 28,
      useCircle: true,
      onTap: onPressed,
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
        style: TextStyle(
          color: AppColors.settingsTextSecondary,
          fontSize: AppTypography.md,
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.settingsBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.settingsDivider.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildDownloadButton(),
          _buildStabilizeToggleButton(),
          _buildRawToggleButton(),
          if (widget.isEyeBasedProject) _buildInspectToggleButton(),
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
      activeColor: AppColors.success,
      onPressed: _gallerySaveIsLoading ? null : _saveImage,
      tooltip: 'Save to device',
    );
  }

  Widget _buildStabilizeToggleButton() {
    final bool isStabilizedActive =
        _activeButton == widget.projectOrientation.toLowerCase();
    return _buildActionButton(
      icon: Icons.video_stable,
      active: isStabilizedActive,
      onPressed: isStabilizedActive ? null : _switchToStabilized,
      tooltip: 'View Stabilized',
    );
  }

  Widget _buildRawToggleButton() {
    return _buildActionButton(
      icon: Icons.raw_on,
      active: _activeButton == 'raw',
      iconSize: 25,
      onPressed: _activeButton == 'raw' ? null : _switchToRaw,
      tooltip: 'View Raw',
    );
  }

  Widget _buildMoreOptionsButton() {
    return _buildActionButton(
      icon: Icons.more_vert,
      onPressed: _showOptionsMenu,
      tooltip: 'More options',
    );
  }

  Widget _buildInspectToggleButton() {
    final bool isStabilizedView = !_isRaw;
    final bool isActive = _isInspectionMode && isStabilizedView;
    return Opacity(
      opacity: isStabilizedView ? 1.0 : 0.3,
      child: _buildActionButton(
        icon: Icons.grid_on,
        active: isActive,
        activeColor: const Color(0xFF4CAF50),
        onPressed: isStabilizedView
            ? () => setState(() => _isInspectionMode = !_isInspectionMode)
            : null,
        tooltip: isStabilizedView
            ? 'Inspection Mode'
            : 'Inspection Mode — Available on Stabilized view only',
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    VoidCallback? onPressed,
    bool active = false,
    Color? activeColor,
    double iconSize = 22,
    String? tooltip,
  }) {
    activeColor ??= AppColors.settingsAccent;
    Widget button = _buildIconButton(
      icon: icon,
      size: 40,
      radius: 12,
      containerRadius: 10,
      bgColor: active
          ? activeColor.withValues(alpha: 0.15)
          : AppColors.settingsCardBorder,
      iconColor: active ? activeColor : AppColors.settingsTextPrimary,
      iconSize: iconSize,
      onTap: onPressed,
    );
    if (tooltip != null && isDesktop) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildIconButton({
    required IconData icon,
    required double size,
    required double radius,
    double? containerRadius,
    required Color bgColor,
    required Color iconColor,
    double iconSize = 22,
    bool useCircle = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bgColor,
            shape: useCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: useCircle
                ? null
                : BorderRadius.circular(containerRadius ?? radius),
          ),
          child: Icon(icon, color: iconColor, size: iconSize),
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
      String saveFilename = path.basename(_currentImagePath);
      Map<String, dynamic>? photoData;

      // For raw images, resolve through the unified original resolver and use
      // the stored source filename when available.
      if (_isRaw) {
        final timestamp = path.basenameWithoutExtension(_currentImagePath);
        photoData = await DB.instance.getPhotoByTimestamp(
          timestamp,
          widget.projectId,
        );
        if (photoData != null) {
          saveFilename =
              (photoData['sourceFilename'] as String?)?.trim().isNotEmpty ==
                      true
                  ? (photoData['sourceFilename'] as String).trim()
                  : (photoData['originalFilename'] as String? ??
                      path.basename(_currentImagePath));

          imagePathToSave = _currentImagePath;
        }
      }

      // Apply date stamp if enabled (only for stabilized images)
      if (_exportDateStampEnabled && !_isRaw) {
        final timestamp = path.basenameWithoutExtension(_currentImagePath);
        final timestampMs = int.tryParse(timestamp);
        if (timestampMs != null) {
          // Get captureOffsetMinutes from photo metadata for accurate timezone
          photoData ??= await _previewPhotoFuture;
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
            final imageBytes = await File(_currentImagePath).readAsBytes();
            final codec = await ui.instantiateImageCodec(imageBytes);
            final frame = await codec.getNextFrame();
            final imageHeight = frame.image.height.toDouble();
            frame.image.dispose();
            watermarkOffset =
                isLowerCorner ? -(imageHeight * 0.05) : (imageHeight * 0.05);
          }

          // Create temp file for date-stamped image (use original filename)
          final tempDir = await getTemporaryDirectory();
          tempFile = '${tempDir.path}/$saveFilename';

          final success = await DateStampUtils.compositeDate(
            inputPath: _currentImagePath,
            outputPath: tempFile,
            dateText: formattedDate,
            position: _exportDateStampPosition,
            sizePercent: DateStampUtils.resolveExportSize(
              _exportDateStampSize,
              _galleryDateStampSize,
            ),
            opacity: _exportDateStampOpacity,
            watermarkVerticalOffset: watermarkOffset,
            fontFamily: DateStampUtils.resolveExportFont(
              _exportDateStampFont,
              _galleryDateStampFont,
            ),
            marginPercentH: _exportDateStampMarginH,
            marginPercentV: _exportDateStampMarginV,
          );

          if (success) {
            imagePathToSave = tempFile;
          }
        }
      }

      if (_isRaw && path.basename(imagePathToSave) != saveFilename) {
        final tempDir = await getTemporaryDirectory();
        tempFile = path.join(tempDir.path, saveFilename);
        await File(imagePathToSave).copy(tempFile);
        imagePathToSave = tempFile;
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
    if (isDesktop) {
      final bytes = await image.readAsBytes();
      if (test_config.isTestMode) {
        final tempPath = await DirUtils.getTemporaryDirPath();
        await _ensureDirExists(tempPath);
        final targetPath = await _uniquePath(
          tempPath,
          path.basename(image.path),
        );
        await File(targetPath).writeAsBytes(bytes, flush: true);
        return;
      }
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
    var i = 2;
    while (await File(candidate).exists()) {
      candidate = path.join(dir, '$name ($i)$ext');
      i++;
    }
    return candidate;
  }

  Future<void> _checkAndRequestPermissions() async {
    await GalleryPermissionHandler.requestGalleryPermissions();
  }

  Future<void> _showOptionsMenu() async {
    if (_currentImagePath.isEmpty) return;

    final imageFile = File(_currentImagePath);

    await GalleryImageMenu.show(
      context: context,
      imageFile: imageFile,
      useAppColors: true,
      onChangeDate: _showChangeDateDialog,
      onStabDiffFace: () => _navigateToStabDiffFace(imageFile),
      onRetryStab: _retryStabilization,
      onSetGuidePhoto: _setAsGuidePhoto,
      onManualStab: () => _navigateToManualStabilization(imageFile),
      onDelete: () => _showDeleteDialog(imageFile),
      onImageInfo: _showImageInfoDialog,
    );
  }

  Future<void> _showChangeDateDialog() async {
    final timestamp = _currentTimestamp;
    if (timestamp.isEmpty) return;

    final allFilenames = widget.rawImageFiles
        .map((f) => path.basenameWithoutExtension(f))
        .toList();

    final result = await GalleryPhotoOperations.showChangeDateFlow(
      context: context,
      currentTimestamp: timestamp,
      projectIdStr: widget.projectId.toString(),
      allImageFilenames: allFilenames,
    );
    if (result == null || !mounted) return;

    final (newTimestamp, orderChanged, dateStampTextChanged) = result;
    final needsRecompile = orderChanged || dateStampTextChanged;
    await _changePhotoDate(timestamp, newTimestamp, needsRecompile);
  }

  Future<void> _changePhotoDate(
    String currentTimestamp,
    String newTimestamp,
    bool needsRecompile,
  ) async {
    await GalleryPhotoOperations.changeDateAndReload(
      oldTimestamp: currentTimestamp,
      newTimestamp: newTimestamp,
      projectId: widget.projectId,
      loadImages: widget.loadImages,
      recompileCallback: widget.recompileVideoCallback,
      needsRecompile: needsRecompile,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo date updated')));
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
    Utils.navigateToScreen(context, screen);
  }

  Future<void> _retryStabilization() async {
    final timestamp = _currentTimestamp;
    if (timestamp.isEmpty) return;

    final rawPhotoPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      widget.projectId,
    );

    await GalleryPhotoOperations.retryStabilization(
      imagePath: rawPhotoPath,
      projectId: widget.projectId,
      projectOrientation: widget.projectOrientation,
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

    final success = await GalleryPhotoOperations.setAsGuidePhoto(
      timestamp: timestamp,
      projectId: widget.projectId,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Guide photo updated')));
    }
  }

  Future<void> _navigateToManualStabilization(File imageFile) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualStabilizationPage(
          imagePath: imageFile.path,
          projectId: widget.projectId,
          onSaveComplete: widget.loadImages,
        ),
      ),
    );
    if (mounted) {
      setState(() => _imageRefreshKey++);
    }
  }

  Future<void> _showDeleteDialog(File imageFile) async {
    final int totalPhotos = widget.rawImageFiles.length;
    final bool shouldRecompile = totalPhotos - 1 >= 2;

    final confirmed = await GalleryPhotoOperations.confirmDeletePhoto(
      context: context,
      totalPhotos: totalPhotos,
    );
    if (confirmed && mounted) {
      await _deleteImage(imageFile, triggerRecompile: shouldRecompile);
    }
  }

  Future<void> _deleteImage(
    File imageFile, {
    required bool triggerRecompile,
  }) async {
    final success = await GalleryPhotoOperations.deletePhoto(
      imageFile: imageFile,
      projectId: widget.projectId,
    );

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete image')));
      }
      return;
    }

    // Reload images
    await widget.loadImages();

    // Trigger video recompilation if enough photos remain
    if (triggerRecompile) {
      await widget.recompileVideoCallback();
    }

    // Navigate to adjacent or close if no images left
    if (_currentList.isEmpty) {
      if (mounted) Navigator.of(context).pop();
    } else {
      final newIndex = _currentIndex.clamp(0, _currentList.length - 1);
      setState(() => _currentIndex = newIndex);
      _pageController.jumpToPage(newIndex);
    }
  }
}
