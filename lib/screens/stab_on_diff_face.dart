import 'package:flutter/material.dart';
import 'dart:io';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../services/thumbnail_service.dart';
import '../styles/styles.dart';
import '../utils/camera_utils.dart';
import '../utils/dir_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/utils.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/desktop_page_scaffold.dart';
import '../widgets/help_icon_button.dart';
import '../widgets/quick_guide_dialog.dart';

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
  FaceStabilizer? faceStabilizer;
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

  @override
  void dispose() {
    faceStabilizer?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setStateIfMounted(() {
      // Show different message if main stabilization is running (user may need to wait)
      loadingStatus = widget.stabilizationRunningInMain
          ? "Waiting for stabilizer..."
          : "Loading image...";
    });

    rawImagePath = await _getRawPhotoPath();
    if (!mounted) return;

    faceStabilizer = FaceStabilizer(
      widget.projectId,
      widget.userRanOutOfSpaceCallback,
    );
    await faceStabilizer!.init();
    if (!mounted) return;

    final bytes = await CameraUtils.readBytesInIsolate(rawImagePath);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        loadingStatus = "Failed to load image.";
      });
      return;
    }

    final dims = await StabUtils.getImageDimensionsFromBytesAsync(bytes);
    if (!mounted) return;
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

    List<dynamic>? facesRaw = await faceStabilizer!.getFacesFromRawPhotoPath(
      rawImagePath,
      imageWidth,
      filterByFaceSize: false,
    );

    // Retry once if failed - handles rare cache corruption / isolate recovery
    // Our safeguards (cache validation, isolate reset) run on first attempt,
    // so retry should succeed with fresh state
    if (facesRaw == null || facesRaw.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      facesRaw = await faceStabilizer!.getFacesFromRawPhotoPath(
        rawImagePath,
        imageWidth,
        filterByFaceSize: false,
      );
    }

    if (!mounted) return;
    if (facesRaw == null || facesRaw.isEmpty) {
      setState(() {
        loadingStatus = facesRaw == null
            ? "There was an error detecting faces."
            : "No faces detected in this image.";
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
    dynamic tappedFace,
    VoidCallback userRanOutOfSpaceCallback,
  ) async {
    final bool userConfirmed = await ConfirmActionDialog.showSimpleConfirmation(
      context,
      title: 'Confirm Stabilization',
      description: 'Do you want to stabilize on this face?',
      titleIcon: Icons.face_rounded,
      accentColor: AppColors.settingsAccent,
      confirmText: 'Confirm',
    );
    if (userConfirmed) {
      setState(() {
        loadingStatus = "Stabilizing image...";
        isLoading = true;
      });

      final Rect targetBox = (tappedFace as dynamic).boundingBox as Rect;

      final result = await faceStabilizer!.stabilize(
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
            await faceStabilizer!.createStabThumbnailFromRawPath(rawImagePath);

        // 2. Clear caches BEFORE reloading gallery
        Utils.clearFlutterImageCache();
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

  void _showHelpDialog() => showQuickGuideDialog(
        context,
        'This screen lets you choose which face to stabilize on when multiple faces are detected in a photo.\n\n'
        'Detected faces are highlighted with blue outlines. Tap on a face to select it as the stabilization target.\n\n'
        'Use this when the automatic stabilization picked the wrong person, or when you want to create a timelapse focused on someone else in the photo.',
      );

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: stabCompletedSuccessfully == null
          ? !isLoading
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildImageWithContours(
                      constraints,
                      widget.userRanOutOfSpaceCallback,
                    );
                  },
                )
              : _buildStatusDisplay(
                  icon: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.settingsAccent,
                    ),
                  ),
                  message: loadingStatus,
                  messageStyle: TextStyle(
                    color: AppColors.settingsTextSecondary,
                    fontSize: AppTypography.md,
                  ),
                )
          : stabCompletedSuccessfully!
              ? _buildStatusDisplay(
                  icon: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.settingsAccent,
                    size: 48,
                  ),
                  message: loadingStatus,
                )
              : _buildStatusDisplay(
                  icon: Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.warningMuted,
                    size: 48,
                  ),
                  message: loadingStatus,
                ),
    );

    return DesktopPageScaffold(
      title: 'Stabilize on Other Face',
      onBack: () => Navigator.pop(context),
      backgroundColor: AppColors.settingsBackground,
      showBottomDivider: true,
      actions: [
        HelpIconButton(onTap: _showHelpDialog),
      ],
      body: body,
    );
  }

  Widget _buildStatusDisplay({
    required Widget icon,
    required String message,
    TextStyle? messageStyle,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(height: 16),
        Text(
          message,
          style: messageStyle ??
              TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }

  Widget _buildImageWithContours(
    BoxConstraints constraints,
    VoidCallback userRanOutOfSpaceCallback,
  ) {
    final displaySize = _calculateDisplaySize(constraints);
    final contourRects = FaceContourPainter.calculateContours(
      faces,
      originalImageSize,
      displaySize,
    );

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
          ...faceContours.map(
            (entry) => _buildContourRect(
              entry.value,
              entry.key,
              userRanOutOfSpaceCallback,
            ),
          ),
        ],
      ),
    );
  }

  Size _calculateDisplaySize(BoxConstraints constraints) {
    final imageAspectRatio = originalImageSize.width / originalImageSize.height;
    final displayAspectRatio = constraints.maxWidth / constraints.maxHeight;

    if (imageAspectRatio > displayAspectRatio) {
      return Size(
        constraints.maxWidth,
        constraints.maxWidth / imageAspectRatio,
      );
    } else {
      return Size(
        constraints.maxHeight * imageAspectRatio,
        constraints.maxHeight,
      );
    }
  }

  Widget _buildContourRect(
    Rect rect,
    dynamic face,
    VoidCallback userRanOutOfSpaceCallback,
  ) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: () => _handleContourTapped(face, userRanOutOfSpaceCallback),
        child: Container(color: AppColors.info.withAlpha(77)),
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
    List<dynamic> faces,
    Size originalImageSize,
    Size displaySize,
  ) {
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
      ..color = AppColors.accentLight;

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
