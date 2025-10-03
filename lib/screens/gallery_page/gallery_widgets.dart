import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import '../../utils/gallery_utils.dart';

class FlashingBox extends StatefulWidget {
  const FlashingBox({super.key});

  @override
  FlashingBoxState createState() => FlashingBoxState();
}

class FlashingBoxState extends State<FlashingBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: Curves.easeInOut)),
      child: Container(
        color: Colors.grey,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

class StabilizedThumbnail extends StatefulWidget {
  final String thumbnailPath;
  final int projectId;

  const StabilizedThumbnail({
    Key? key,
    required this.thumbnailPath,
    required this.projectId,
  }) : super(key: key);

  @override
  StabilizedThumbnailState createState() => StabilizedThumbnailState();
}

class StabilizedThumbnailState extends State<StabilizedThumbnail> {
  late Future<String> _thumbnailFuture;
  String? _cachedResult;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant StabilizedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailPath != widget.thumbnailPath) {
      _cachedResult = null;
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<String> _loadThumbnail() async {
    if (_cachedResult != null) return _cachedResult!;
    final result = await GalleryUtils.waitForThumbnail(widget.thumbnailPath, widget.projectId);
    _cachedResult = result;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _thumbnailFuture,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return const FlashingBox();
        }

        if (snapshot.data == "no_faces_found" || snapshot.data == "stab_failed") {
          return Container(
            color: Colors.transparent,
            child: const Stack(
              children: [
                Positioned(
                  top: 8.0,
                  right: 8.0,
                  child: Icon(Icons.error, color: Colors.red, size: 24.0),
                ),
              ],
            ),
          );
        }

        if (snapshot.data == "success") {
          final f = File(widget.thumbnailPath);
          final provider = FileImage(f);
          painting.imageCache.evict(provider);
          return Image(
            image: provider,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stack) => Container(color: Colors.black),
          );
        }

        return Container(color: Colors.black);
      },
    );
  }
}