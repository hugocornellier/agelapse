import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/database_helper.dart';
import '../../utils/dir_utils.dart';
import '../../utils/settings_utils.dart';
import 'dart:ui' as ui;
import 'grid_mode.dart';

class CameraGridOverlay extends StatefulWidget {
  final int projectId;
  final GridMode gridMode;
  final double offsetX;
  final double offsetY;

  const CameraGridOverlay(this.projectId, this.gridMode, this.offsetX, this.offsetY, {super.key});

  @override
  _CameraGridOverlayState createState() => _CameraGridOverlayState();
}

class _CameraGridOverlayState extends State<CameraGridOverlay> {
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
    final projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
    final stabPhotos = await DB.instance.getStabilizedPhotosByProjectID(widget.projectId, projectOrientation);

    if (stabPhotos.isNotEmpty) {
      final guidePhoto = stabPhotos.first;
      final timestamp = guidePhoto['timestamp'].toString();
      final rawPhotoPath = await getRawPhotoPathFromTimestamp(timestamp);
      final stabilizedPath = await DirUtils.getStabilizedImagePath(rawPhotoPath, widget.projectId);

      final projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
      final stabilizedColumn = DB.instance.getStabilizedColumn(projectOrientation);
      final stabColOffsetX = "${stabilizedColumn}OffsetX";
      final stabColOffsetY = "${stabilizedColumn}OffsetY";
      final offsetXDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(timestamp, stabColOffsetX);
      final offsetYDataRaw = await DB.instance.getPhotoColumnValueByTimestamp(timestamp, stabColOffsetY);
      final offsetXData = double.tryParse(offsetXDataRaw);
      final offsetYData = double.tryParse(offsetYDataRaw);

      setState(() {
        ghostImageOffsetX = offsetXData;
        ghostImageOffsetY = offsetYData;
        stabPhotoPath = stabilizedPath;
      });

      _loadImage(stabilizedPath, timestamp);
    }
  }

  Future<void> _loadImage(String path, String timestamp) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    setState(() {
      guideImage = frameInfo.image;
    });
  }

  Future<String> getRawPhotoPathFromTimestamp(String timestamp) async =>
      await DirUtils.getRawPhotoPathFromTimestampAndProjectId(timestamp, widget.projectId);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _GridPainter(widget.offsetX, widget.offsetY, ghostImageOffsetX, ghostImageOffsetY, guideImage, widget.projectId, widget.gridMode),
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

  _GridPainter(this.offsetX, this.offsetY, this.ghostImageOffsetX, this.ghostImageOffsetY, this.guideImage, this.projectId, this.gridMode);

  @override
  void paint(Canvas canvas, Size size) {
    if (gridMode == GridMode.none) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1;

    if (gridMode == GridMode.gridOnly || gridMode == GridMode.doubleGhostGrid) {
      _drawVerticalLines(canvas, size, paint);
      _drawHorizontalLine(canvas, size, paint);
    }

    if (gridMode == GridMode.ghostOnly || gridMode == GridMode.doubleGhostGrid) {
      _drawGuideImage(canvas, size);
    }
  }

  void _drawVerticalLines(Canvas canvas, Size size, Paint paint) {
    final offsetXInPixels = size.width * offsetX;
    final centerX = size.width / 2;
    final leftX = centerX - offsetXInPixels;
    final rightX = centerX + offsetXInPixels;

    canvas.drawLine(Offset(leftX, 0), Offset(leftX, size.height), paint);
    canvas.drawLine(Offset(rightX, 0), Offset(rightX, size.height), paint);
  }

  void _drawHorizontalLine(Canvas canvas, Size size, Paint paint) {
    final y = size.height * offsetY;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  void _drawGuideImage(Canvas canvas, Size size) {
    if (guideImage != null && ghostImageOffsetX != null && ghostImageOffsetY != null) {
      final imagePaint = Paint()..color = Colors.white.withOpacity(0.5);
      final imageWidth = guideImage!.width.toDouble();
      final imageHeight = guideImage!.height.toDouble();
      final scale = _calculateImageScale(size.width, imageWidth, imageHeight);

      final scaledWidth = imageWidth * scale;
      final scaledHeight = imageHeight * scale;

      final eyeOffsetFromCenterInGhostPhoto = (0.5 - ghostImageOffsetY!) * scaledHeight;
      final eyeOffsetFromCenterGuideLines = (0.5 - offsetY) * size.height;
      final difference = eyeOffsetFromCenterGuideLines - eyeOffsetFromCenterInGhostPhoto;

      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, (size.height / 2) - difference),
        width: scaledWidth,
        height: scaledHeight,
      );
      canvas.drawImageRect(guideImage!, Offset.zero & Size(imageWidth, imageHeight), rect, imagePaint);
    }
  }

  double _calculateImageScale(double canvasWidth, double imageWidth, double imageHeight) {
    return (canvasWidth * offsetX) / (imageWidth * ghostImageOffsetX!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
