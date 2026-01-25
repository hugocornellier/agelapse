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
import '../../widgets/confirm_action_dialog.dart';
import '../manual_stab_page.dart';
import '../stab_on_diff_face.dart';
import 'gallery_widgets.dart';
import 'gallery_image_menu.dart';

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
  String _exportDateStampFont = DateStampUtils.fontSameAsGallery;
  String _galleryDateStampFont = DateStampUtils.defaultFont;

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
                  fontSize: AppTypography.md,
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
                    fontSize: AppTypography.sm,
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
          imageWidget =
              _buildImageWithDateOverlay(imageWidget, formattedDate, imagePath);
        }
      }

      return Center(child: imageWidget);
    } else {
      // Show raw image
      return Center(child: _buildResizableImage(File(imagePath)));
    }
  }

  Widget _buildImageWithDateOverlay(
      Widget imageWidget, String dateText, String imagePath) {
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

              // Displayed image height
              final displayedHeight = imageHeight * scale;

              // Font size: same formula as video output
              // Video uses: (videoHeight * sizePercent / 100).clamp(12.0, 200.0)
              // For preview, we use displayed height with same percentage
              previewFontSize = (displayedHeight * _exportDateStampSize / 100)
                  .clamp(10.0, 48.0);
            }

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
                                color:
                                    AppColors.overlay.withValues(alpha: 0.54),
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
      child: Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) =>
            Container(color: AppColors.overlay),
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
        style: TextStyle(
            color: AppColors.settingsTextSecondary, fontSize: AppTypography.md),
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
      activeColor: AppColors.success,
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
            fontFamily: DateStampUtils.resolveExportFont(
              _exportDateStampFont,
              _galleryDateStampFont,
            ),
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

    // Check if this would change the photo order
    final orderChanged = _wouldChangeOrder(timestamp, newTimestamp);

    // Check if the formatted date stamp text would change
    bool dateStampTextChanged = false;
    final projectIdStr = widget.projectId.toString();
    final exportStampsEnabled =
        await SettingsUtil.loadExportDateStampEnabled(projectIdStr);

    if (exportStampsEnabled && !orderChanged) {
      // Only check text if stamps are enabled and order didn't change
      final format = await SettingsUtil.loadExportDateStampFormat(projectIdStr);
      final oldText = DateStampUtils.formatTimestamp(
        int.parse(timestamp),
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

    await _changePhotoDate(timestamp, newTimestamp, needsRecompile);
  }

  /// Checks if changing a photo's timestamp would change its position in the sorted list.
  bool _wouldChangeOrder(String oldTimestamp, String newTimestamp) {
    final currentFiles = widget.rawImageFiles;
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
    String currentTimestamp,
    String newTimestamp,
    bool needsRecompile,
  ) async {
    // Update database
    await DB.instance.updatePhotoTimestamp(
      currentTimestamp,
      newTimestamp,
      widget.projectId,
    );

    // Rename files
    await _renamePhotoFiles(currentTimestamp, newTimestamp);

    // Reload images
    await widget.loadImages();

    // Trigger video recompilation if needed
    if (needsRecompile) {
      await widget.recompileVideoCallback();
    }

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

  void _navigateToManualStabilization(File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManualStabilizationPage(
          imagePath: imageFile.path,
          projectId: widget.projectId,
          onSaveComplete: widget.loadImages,
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(File imageFile) async {
    final int totalPhotos = widget.rawImageFiles.length;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete image')),
        );
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
