import 'package:flutter/material.dart';
import 'dart:io';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/camera_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';

class StabDiffFacePage extends StatefulWidget {
  final int projectId;
  final String imageTimestamp;
  final Future<void> Function() reloadImagesInGallery;
  final VoidCallback stabCallback;
  final VoidCallback userRanOutOfSpaceCallback;

  /// Whether the main stabilization process is currently running.
  /// Used to show appropriate loading messages and prevent unnecessary restarts.
  final bool stabilizationRunningInMain;

  const StabDiffFacePage({
    super.key,
    required this.projectId,
    required this.imageTimestamp,
    required this.reloadImagesInGallery,
    required this.stabCallback,
    required this.userRanOutOfSpaceCallback,
    this.stabilizationRunningInMain = false,
  });

  @override
  StabDiffFacePageState createState() => StabDiffFacePageState();
}

class StabDiffFacePageState extends State<StabDiffFacePage> {
  late String rawImagePath;
  late FaceStabilizer faceStabilizer;
  late Size originalImageSize;
  List<dynamic> faces = [];
  List<MapEntry<dynamic, Rect>> faceContours = [];
  bool isLoading = true;
  bool? stabCompletedSuccessfully;
  String loadingStatus = "Loading image...";

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      // Show different message if main stabilization is running (user may need to wait)
      loadingStatus = widget.stabilizationRunningInMain
          ? "Waiting for stabilizer..."
          : "Loading image...";
    });

    rawImagePath = await _getRawPhotoPath();
    faceStabilizer =
        FaceStabilizer(widget.projectId, widget.userRanOutOfSpaceCallback);
    await faceStabilizer.init();

    final bytes = await CameraUtils.readBytesInIsolate(rawImagePath);
    if (bytes == null) {
      setState(() {
        loadingStatus = "Failed to load image.";
      });
      return;
    }

    final dims = await StabUtils.getImageDimensionsFromBytesAsync(bytes);
    if (dims == null) {
      setState(() {
        loadingStatus = "Failed to decode image.";
      });
      return;
    }

    final imageWidth = dims.$1;
    setState(() {
      originalImageSize = Size(imageWidth.toDouble(), dims.$2.toDouble());
      loadingStatus = "Detecting faces...";
    });

    List<dynamic>? facesRaw = await faceStabilizer.getFacesFromRawPhotoPath(
        rawImagePath, imageWidth,
        filterByFaceSize: false);

    if (facesRaw == null) {
      setState(() {
        loadingStatus = "There was an error detecting faces.";
      });
      return;
    }

    faces = facesRaw;

    setState(() {
      isLoading = false;
    });
  }

  Future<String> _getRawPhotoPath() async {
    return DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      widget.imageTimestamp,
      widget.projectId,
    );
  }

  void _handleContourTapped(
      dynamic tappedFace, VoidCallback userRanOutOfSpaceCallback) async {
    final bool? userConfirmed = await _showConfirmationDialog();
    if (userConfirmed!) {
      setState(() {
        loadingStatus = "Stabilizing image...";
        isLoading = true;
      });

      final Rect targetBox = (tappedFace as dynamic).boundingBox as Rect;

      final result = await faceStabilizer.stabilize(
        rawImagePath,
        null, // No cancellation token for one-off operations
        userRanOutOfSpaceCallback,
        targetBoundingBox: targetBox,
      );
      final bool successful = result.success;

      final String loadStatus =
          successful ? "Stabilization successful" : "Stabilization failed";

      if (successful) {
        // 1. Wait for thumbnail to be created before updating UI
        final thumbnailPath =
            await faceStabilizer.createStabThumbnailFromRawPath(rawImagePath);

        // 2. Clear caches BEFORE reloading gallery
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        ThumbnailService.instance.clearCache(thumbnailPath);
      }

      await DB.instance.setNewVideoNeeded(widget.projectId);
      await widget.reloadImagesInGallery();

      if (!widget.stabilizationRunningInMain) {
        widget.stabCallback();
      }

      setState(() {
        loadingStatus = loadStatus;
        stabCompletedSuccessfully = successful;
        isLoading = false;
      });
    }
  }

  Future<bool?> _showConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.face_rounded,
                color: AppColors.settingsAccent,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Confirm Stabilization',
                style: TextStyle(
                  color: AppColors.settingsTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Text(
            'Do you want to stabilize on this face?',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.settingsTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text(
                'Confirm',
                style: TextStyle(
                  color: AppColors.settingsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: AppColors.settingsBackground,
      title: const Text(
        'Stabilize on Other Face',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.settingsTextPrimary,
        ),
      ),
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.arrow_back,
            color: AppColors.settingsTextPrimary,
            size: 20,
          ),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: _showHelpDialog,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.settingsCardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.settingsCardBorder,
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.settingsTextSecondary,
              size: 20,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: AppColors.settingsDivider,
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.settingsCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.settingsAccent,
              size: 24,
            ),
            SizedBox(width: 12),
            Text(
              'Quick Guide',
              style: TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'This screen lets you choose which face to stabilize on when multiple faces are detected in a photo.\n\n'
            'Detected faces are highlighted with red outlines. Tap on a face to select it as the stabilization target.\n\n'
            'Use this when the automatic stabilization picked the wrong person, or when you want to create a timelapse focused on someone else in the photo.',
            style: TextStyle(
              color: AppColors.settingsTextSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: AppColors.settingsAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.settingsBackground,
      appBar: _buildAppBar(),
      body: Center(
        child: stabCompletedSuccessfully == null
            ? !isLoading
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return _buildImageWithContours(
                          constraints, widget.userRanOutOfSpaceCallback);
                    },
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.settingsAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loadingStatus,
                        style: const TextStyle(
                          color: AppColors.settingsTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
            : stabCompletedSuccessfully!
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.settingsAccent,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loadingStatus,
                        style: const TextStyle(
                          color: AppColors.settingsTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.orange,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loadingStatus,
                        style: const TextStyle(
                          color: AppColors.settingsTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildImageWithContours(
      BoxConstraints constraints, VoidCallback userRanOutOfSpaceCallback) {
    final displaySize = _calculateDisplaySize(constraints);
    final contourRects = FaceContourPainter.calculateContours(
        faces, originalImageSize, displaySize);

    faceContours = faces
        .asMap()
        .entries
        .map((entry) => MapEntry(entry.value, contourRects[entry.key]))
        .toList();

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.file(
            File(rawImagePath),
            width: displaySize.width,
            height: displaySize.height,
            fit: BoxFit.contain,
          ),
          CustomPaint(
            painter: FaceContourPainter(faces, originalImageSize, displaySize),
            size: displaySize,
          ),
          ...faceContours.map((entry) => _buildContourRect(
              entry.value, entry.key, userRanOutOfSpaceCallback)),
        ],
      ),
    );
  }

  Size _calculateDisplaySize(BoxConstraints constraints) {
    final imageAspectRatio = originalImageSize.width / originalImageSize.height;
    final displayAspectRatio = constraints.maxWidth / constraints.maxHeight;

    if (imageAspectRatio > displayAspectRatio) {
      return Size(
          constraints.maxWidth, constraints.maxWidth / imageAspectRatio);
    } else {
      return Size(
          constraints.maxHeight * imageAspectRatio, constraints.maxHeight);
    }
  }

  Widget _buildContourRect(
      Rect rect, dynamic face, VoidCallback userRanOutOfSpaceCallback) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: () => _handleContourTapped(face, userRanOutOfSpaceCallback),
        child: Container(
          color: Colors.blue.withAlpha(77),
        ),
      ),
    );
  }
}

class FaceContourPainter extends CustomPainter {
  final List<dynamic> faces;
  final Size originalImageSize;
  final Size displaySize;

  FaceContourPainter(this.faces, this.originalImageSize, this.displaySize);

  static List<Rect> calculateContours(
      List<dynamic> faces, Size originalImageSize, Size displaySize) {
    final double scaleX = displaySize.width / originalImageSize.width;
    final double scaleY = displaySize.height / originalImageSize.height;
    return faces.map((face) {
      final Rect bb = face.boundingBox as Rect;
      return Rect.fromLTRB(
        bb.left * scaleX,
        bb.top * scaleY,
        bb.right * scaleX,
        bb.bottom * scaleY,
      );
    }).toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final contours = calculateContours(faces, originalImageSize, displaySize);

    for (final contour in contours) {
      canvas.drawRect(contour, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceContourPainter oldDelegate) {
    return faces != oldDelegate.faces ||
        originalImageSize != oldDelegate.originalImageSize ||
        displaySize != oldDelegate.displaySize;
  }
}
