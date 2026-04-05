import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../services/database_helper.dart';
import '../../services/log_service.dart';
import '../../styles/app_colors_data.dart';
import '../../styles/styles.dart';
import '../../utils/dir_utils.dart';
import '../../utils/settings_utils.dart';
import '../../utils/utils.dart';
import 'dart:ui' as ui;
import 'grid_mode.dart';

class CameraGridOverlay extends StatefulWidget {
  final int projectId;
  final GridMode gridMode;
  final double offsetX;
  final double offsetY;
  final String? orientation;
  final bool useSelectedGuidePhoto;

  const CameraGridOverlay(
    this.projectId,
    this.gridMode,
    this.offsetX,
    this.offsetY, {
    super.key,
    this.orientation,
    this.useSelectedGuidePhoto = false,
  });

  @override
  CameraGridOverlayState createState() => CameraGridOverlayState();
}

class CameraGridOverlayState extends State<CameraGridOverlay> {
  double? ghostImageOffsetX;
  double? ghostImageOffsetY;
  String? stabPhotoPath;
  ui.Image? guideImage;

  @override
  void initState() {
    super.initState();
    _initGuidePhoto();
  }

  Future<void> _initGuidePhoto() async {
    final projectOrientation = await SettingsUtil.loadProjectOrientation(
      widget.projectId.toString(),
    );
    final stabPhotos = await DB.instance.getStabilizedPhotosByProjectID(
      widget.projectId,
      projectOrientation,
    );

    if (stabPhotos.isNotEmpty) {
      Map<String, dynamic> guidePhoto;
      String timestamp;

      if (widget.useSelectedGuidePhoto) {
        final String selectedGuidePhoto =
            await SettingsUtil.loadSelectedGuidePhoto(
          widget.projectId.toString(),
        );
        if (selectedGuidePhoto == "not set") {
          guidePhoto = stabPhotos.first;
          timestamp = guidePhoto['timestamp'].toString();
        } else {
          final guidePhotoRecord = await DB.instance.getPhotoById(
            selectedGuidePhoto,
            widget.projectId,
          );
          if (guidePhotoRecord != null) {
            guidePhoto = guidePhotoRecord;
            timestamp = guidePhotoRecord['timestamp'].toString();
          } else {
            guidePhoto = stabPhotos.first;
            timestamp = guidePhoto['timestamp'].toString();
          }
        }
      } else {
        guidePhoto = stabPhotos.first;
        timestamp = guidePhoto['timestamp'].toString();
      }

      final rawPhotoPath = await getRawPhotoPathFromTimestamp(timestamp);
      final stabilizedPath = await DirUtils.getStabilizedImagePath(
        rawPhotoPath,
        widget.projectId,
      );

      final stabOrientation = await SettingsUtil.loadProjectOrientation(
        widget.projectId.toString(),
      );
      final stabilizedColumn = DB.instance.getStabilizedColumn(stabOrientation);
      final stabColOffsetX = "${stabilizedColumn}OffsetX";
      final stabColOffsetY = "${stabilizedColumn}OffsetY";
      final offsetXDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(
        timestamp,
        stabColOffsetX,
        widget.projectId,
      );
      final offsetYDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(
        timestamp,
        stabColOffsetY,
        widget.projectId,
      );
      final offsetXData = double.tryParse(offsetXDataRaw);
      final offsetYData = double.tryParse(offsetYDataRaw);
      setStateIfMounted(() {
        ghostImageOffsetX = offsetXData;
        ghostImageOffsetY = offsetYData;
        stabPhotoPath = stabilizedPath;
      });

      _loadImage(stabilizedPath, timestamp);
    }
  }

  Future<void> _loadImage(String imagePath, String timestamp) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        LogService.instance.log('Guide image file does not exist: $imagePath');
        return;
      }
      final bytes = await file.readAsBytes();
      // Image codec instantiation is async but decoding happens on main thread
      // Use a smaller target width for the guide overlay to reduce decode time
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
      final frameInfo = await codec.getNextFrame();
      codec.dispose();
      if (mounted) {
        final oldImage = guideImage;
        setState(() {
          guideImage = frameInfo.image;
        });
        oldImage?.dispose();
      } else {
        frameInfo.image.dispose();
      }
    } catch (e) {
      LogService.instance.log('Error loading guide image: $e');
    }
  }

  @override
  void dispose() {
    guideImage?.dispose();
    super.dispose();
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        widget.projectId,
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _GridPainter(
          widget.offsetX,
          widget.offsetY,
          ghostImageOffsetX,
          ghostImageOffsetY,
          guideImage,
          widget.projectId,
          widget.gridMode,
          widget.orientation,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double? ghostImageOffsetX;
  final double? ghostImageOffsetY;
  final ui.Image? guideImage;
  final int projectId;
  final GridMode gridMode;
  final String? orientation;

  _GridPainter(
    this.offsetX,
    this.offsetY,
    this.ghostImageOffsetX,
    this.ghostImageOffsetY,
    this.guideImage,
    this.projectId,
    this.gridMode,
    this.orientation,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (gridMode == GridMode.none) return;

    final bool isLandscape =
        (orientation == "Landscape Left" || orientation == "Landscape Right");

    if (gridMode == GridMode.gridOnly || gridMode == GridMode.doubleGhostGrid) {
      // When orientation is provided (camera_view usage), use theme-aware color;
      // otherwise fall back to the fixed overlay color (camera_grid standalone usage).
      final Color gridColor = orientation != null
          ? AppColors.textPrimary.withAlpha(153)
          : PhotoOverlayColors.cameraGuide;
      final paint = Paint()
        ..color = gridColor
        ..strokeWidth = 1;

      if (!isLandscape) {
        final offsetXInPixels = size.width * offsetX;
        final centerX = size.width / 2;
        final leftX = centerX - offsetXInPixels;
        final rightX = centerX + offsetXInPixels;
        canvas.drawLine(Offset(leftX, 0), Offset(leftX, size.height), paint);
        canvas.drawLine(Offset(rightX, 0), Offset(rightX, size.height), paint);

        final y = size.height * offsetY;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      } else {
        double verticalLineX = orientation == "Landscape Left"
            ? size.width * (1 - offsetY)
            : size.width * offsetY;
        canvas.drawLine(
          Offset(verticalLineX, 0),
          Offset(verticalLineX, size.height),
          paint,
        );

        final offsetYInPixels = size.height * offsetX;
        final centerY = size.height / 2;
        final topY = centerY - offsetYInPixels;
        final bottomY = centerY + offsetYInPixels;
        canvas.drawLine(Offset(0, topY), Offset(size.width, topY), paint);
        canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
      }
    }

    if (gridMode == GridMode.ghostOnly ||
        gridMode == GridMode.doubleGhostGrid) {
      _drawGuideImage(canvas, size, isLandscape);
    }
  }

  void _drawGuideImage(Canvas canvas, Size size, bool isLandscape) {
    if (guideImage != null &&
        ghostImageOffsetX != null &&
        ghostImageOffsetY != null) {
      // When orientation is provided (camera_view usage), use theme-aware color;
      // otherwise fall back to the fixed overlay color (camera_grid standalone usage).
      final Color ghostColor = orientation != null
          ? AppColors.textPrimary.withAlpha(77)
          : PhotoOverlayColors.ghostImage;
      final imagePaint = Paint()..color = ghostColor;
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();

      final double baseDimension = isLandscape ? size.height : size.width;
      final scale = _calculateImageScale(
        baseDimension,
        imageWidth,
        imageHeight,
      );
      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;
      final eyeOffsetFromCenterInGhostPhoto =
          (0.5 - ghostImageOffsetY!) * scaledHeight;

      if (!isLandscape) {
        final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
        final difference =
            eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

        final rect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2 - difference),
          width: scaledWidth,
          height: scaledHeight,
        );
        canvas.drawImageRect(
          guideImage!,
          Offset.zero & Size(imageWidth, imageHeight),
          rect,
          imagePaint,
        );
      } else {
        final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.width;
        final difference =
            eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

        final center = Offset(size.width / 2, size.height / 2);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        final angle =
            orientation == "Landscape Left" ? math.pi / 2 : -math.pi / 2;
        canvas.rotate(angle);
        final rect = Rect.fromCenter(
          center: Offset(0, -difference),
          width: scaledWidth,
          height: scaledHeight,
        );
        canvas.drawImageRect(
          guideImage!,
          Offset.zero & Size(imageWidth, imageHeight),
          rect,
          imagePaint,
        );
        canvas.restore();
      }
    }
  }

  double _calculateImageScale(
    double baseDimension,
    double imageWidth,
    double imageHeight,
  ) {
    return (baseDimension * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return offsetX != oldDelegate.offsetX ||
        offsetY != oldDelegate.offsetY ||
        ghostImageOffsetX != oldDelegate.ghostImageOffsetX ||
        ghostImageOffsetY != oldDelegate.ghostImageOffsetY ||
        guideImage != oldDelegate.guideImage ||
        gridMode != oldDelegate.gridMode ||
        orientation != oldDelegate.orientation;
  }
}
