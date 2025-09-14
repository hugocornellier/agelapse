import 'package:flutter/material.dart';
import 'dart:io';
import '../services/database_helper.dart';
import '../services/face_stabilizer.dart';
import '../utils/dir_utils.dart';

class StabDiffFacePage extends StatefulWidget {
  final int projectId;
  final String imageTimestamp;
  final Future<void> Function() reloadImagesInGallery;
  final VoidCallback stabCallback;
  final VoidCallback userRanOutOfSpaceCallback;

  const StabDiffFacePage({
    super.key,
    required this.projectId,
    required this.imageTimestamp,
    required this.reloadImagesInGallery,
    required this.stabCallback,
    required this.userRanOutOfSpaceCallback,
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
      loadingStatus = "Loading image...";
    });

    rawImagePath = await _getRawPhotoPath();
    faceStabilizer = FaceStabilizer(widget.projectId, widget.userRanOutOfSpaceCallback);
    await faceStabilizer.init();

    final image = await decodeImageFromList(File(rawImagePath).readAsBytesSync());
    setState(() {
      originalImageSize = Size(image.width.toDouble(), image.height.toDouble());
      loadingStatus = "Detecting faces...";
    });

    List<dynamic>? facesRaw = await faceStabilizer.getFacesFromRawPhotoPath(
        rawImagePath,
        image.width,
        filterByFaceSize: false
    );

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

  void _handleContourTapped(dynamic tappedFace, VoidCallback userRanOutOfSpaceCallback) async {
    final bool? userConfirmed = await _showConfirmationDialog();
    if (userConfirmed!) {
      setState(() {
        loadingStatus = "Stabilizing image...";
        isLoading = true;
      });

      final Rect targetBox = (tappedFace as dynamic).boundingBox as Rect;

      final bool successful = await faceStabilizer.stabilize(
        rawImagePath,
        false,
        userRanOutOfSpaceCallback,
        targetFace: (Platform.isAndroid || Platform.isIOS) ? tappedFace : null,
        targetBoundingBox: targetBox,
      );

      final String loadStatus = successful ? "Stabilization successful" : "Stabilization failed";

      await DB.instance.setNewVideoNeeded(widget.projectId);
      widget.reloadImagesInGallery();
      widget.stabCallback();

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

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
          title: const Text('Confirm Stabilization'),
          content: const Text('Do you want to stabilize on this face?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stabilize'),
      ),
      body: Center(
        child: stabCompletedSuccessfully == null
            ? !isLoading
            ? LayoutBuilder(
          builder: (context, constraints) {
            return _buildImageWithContours(constraints, widget.userRanOutOfSpaceCallback);
          },
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(loadingStatus),
          ],
        )
            : stabCompletedSuccessfully!
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check, color: Colors.green),
            const SizedBox(height: 20),
            Text(loadingStatus),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 20),
            Text(loadingStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWithContours(BoxConstraints constraints, VoidCallback userRanOutOfSpaceCallback) {
    final displaySize = _calculateDisplaySize(constraints);
    final contourRects = FaceContourPainter.calculateContours(faces, originalImageSize, displaySize);

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
          ...faceContours.map((entry) => _buildContourRect(entry.value, entry.key, userRanOutOfSpaceCallback)),
        ],
      ),
    );
  }

  Size _calculateDisplaySize(BoxConstraints constraints) {
    final imageAspectRatio = originalImageSize.width / originalImageSize.height;
    final displayAspectRatio = constraints.maxWidth / constraints.maxHeight;

    if (imageAspectRatio > displayAspectRatio) {
      return Size(constraints.maxWidth, constraints.maxWidth / imageAspectRatio);
    } else {
      return Size(constraints.maxHeight * imageAspectRatio, constraints.maxHeight);
    }
  }

  Widget _buildContourRect(Rect rect, dynamic face, VoidCallback userRanOutOfSpaceCallback) {
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

  static List<Rect> calculateContours(List<dynamic> faces, Size originalImageSize, Size displaySize) {
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}