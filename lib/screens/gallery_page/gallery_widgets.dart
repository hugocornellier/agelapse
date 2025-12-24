import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../services/database_helper.dart';
import '../../services/thumbnail_service.dart';

class FlashingBox extends StatefulWidget {
  const FlashingBox({super.key});

  @override
  FlashingBoxState createState() => FlashingBoxState();
}

class FlashingBoxState extends State<FlashingBox>
    with SingleTickerProviderStateMixin {
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
    super.key,
    required this.thumbnailPath,
    required this.projectId,
  });

  /// Derive the full stabilized image path from thumbnail path
  /// Thumbnail: .../stabilized/portrait/thumbnails/123.jpg
  /// Full image: .../stabilized/portrait/123.png
  String get stabilizedImagePath {
    final dir =
        path.dirname(path.dirname(thumbnailPath)); // Go up from thumbnails/
    final basename = path.basenameWithoutExtension(thumbnailPath);
    return path.join(dir, '$basename.png');
  }

  @override
  StabilizedThumbnailState createState() => StabilizedThumbnailState();
}

class StabilizedThumbnailState extends State<StabilizedThumbnail> {
  StreamSubscription<ThumbnailEvent>? _subscription;
  ThumbnailStatus? _status;
  bool _fileExists = false;
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    _subscribeToStream();
    _checkInitialStatus();
  }

  @override
  void didUpdateWidget(covariant StabilizedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailPath != widget.thumbnailPath) {
      _status = null;
      _fileExists = false;
      _checkedInitial = false;
      _checkInitialStatus();
    }
  }

  void _subscribeToStream() {
    _subscription = ThumbnailService.instance.stream.listen((event) {
      if (!mounted) return;
      if (event.thumbnailPath == widget.thumbnailPath) {
        setState(() {
          _status = event.status;
          if (event.status == ThumbnailStatus.success) {
            _fileExists = true;
          }
        });
      }
    });
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    // 1. Check cache first (for widgets mounting after event fired)
    final cachedStatus =
        ThumbnailService.instance.getStatus(widget.thumbnailPath);
    if (cachedStatus != null) {
      if (cachedStatus == ThumbnailStatus.success) {
        // Verify file actually exists before trusting cache
        final file = File(widget.thumbnailPath);
        if (await file.exists() && await file.length() > 0) {
          if (mounted) {
            setState(() {
              _status = cachedStatus;
              _fileExists = true;
            });
          }
          return;
        }
        // File doesn't exist yet, fall through to other checks
      } else {
        // Failure status - trust the cache
        if (mounted) {
          setState(() => _status = cachedStatus);
        }
        return;
      }
    }

    // 2. Check if file already exists on disk and has content
    final file = File(widget.thumbnailPath);
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0 && mounted) {
        setState(() {
          _status = ThumbnailStatus.success;
          _fileExists = true;
        });
        return;
      }
    }

    // 3. Check DB for failure flags (single query, not polling)
    final String timestamp =
        path.basenameWithoutExtension(widget.thumbnailPath);
    final photo =
        await DB.instance.getPhotoByTimestamp(timestamp, widget.projectId);
    if (photo != null && mounted) {
      if (photo['noFacesFound'] == 1) {
        setState(() => _status = ThumbnailStatus.noFacesFound);
        return;
      }
      if (photo['stabFailed'] == 1) {
        setState(() => _status = ThumbnailStatus.stabFailed);
        return;
      }
    }

    // 4. No status found - stay in loading state, stream will notify when ready
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_status == null) {
      return const FlashingBox();
    }

    // Failure states
    if (_status == ThumbnailStatus.noFacesFound ||
        _status == ThumbnailStatus.stabFailed) {
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

    // Success state - show thumbnail if it exists, otherwise fall back to full image
    if (_status == ThumbnailStatus.success) {
      if (_fileExists) {
        return Image.file(
          File(widget.thumbnailPath),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stack) {
            // Thumbnail failed to load, try full image
            return _buildFallbackImage();
          },
        );
      } else {
        // Thumbnail doesn't exist, try full image as fallback
        return _buildFallbackImage();
      }
    }

    // Still loading or unknown state - show loading indicator
    return const FlashingBox();
  }

  Widget _buildFallbackImage() {
    return Image.file(
      File(widget.stabilizedImagePath),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stack) => Container(color: Colors.grey),
    );
  }
}

/// Widget for preview dialog that shows stabilization status
class StabilizedImagePreview extends StatefulWidget {
  final String thumbnailPath;
  final String imagePath;
  final int projectId;
  final Widget Function(File imageFile) buildImage;

  const StabilizedImagePreview({
    super.key,
    required this.thumbnailPath,
    required this.imagePath,
    required this.projectId,
    required this.buildImage,
  });

  @override
  StabilizedImagePreviewState createState() => StabilizedImagePreviewState();
}

class StabilizedImagePreviewState extends State<StabilizedImagePreview> {
  StreamSubscription<ThumbnailEvent>? _subscription;
  ThumbnailStatus? _status;
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    _subscribeToStream();
    _checkInitialStatus();
  }

  void _subscribeToStream() {
    _subscription = ThumbnailService.instance.stream.listen((event) {
      if (!mounted) return;
      if (event.thumbnailPath == widget.thumbnailPath) {
        setState(() => _status = event.status);
      }
    });
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    // 1. Check cache first
    final cachedStatus =
        ThumbnailService.instance.getStatus(widget.thumbnailPath);
    if (cachedStatus != null) {
      if (mounted) setState(() => _status = cachedStatus);
      return;
    }

    // 2. Check if file already exists on disk
    final file = File(widget.thumbnailPath);
    if (await file.exists()) {
      if (mounted) setState(() => _status = ThumbnailStatus.success);
      return;
    }

    // 3. Check DB for failure flags
    final String timestamp =
        path.basenameWithoutExtension(widget.thumbnailPath);
    final photo =
        await DB.instance.getPhotoByTimestamp(timestamp, widget.projectId);
    if (photo != null && mounted) {
      if (photo['noFacesFound'] == 1) {
        setState(() => _status = ThumbnailStatus.noFacesFound);
        return;
      }
      if (photo['stabFailed'] == 1) {
        setState(() => _status = ThumbnailStatus.stabFailed);
        return;
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_status == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Image being stabilized. Please wait...",
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 10),
            Text('View raw photo by tapping "RAW"')
          ],
        ),
      );
    }

    // Failure states
    if (_status == ThumbnailStatus.noFacesFound) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: Colors.red, size: 50.0),
            SizedBox(height: 10),
            Text(
              "Stabilization failed. No faces found. Try the 'manual stabilization' option.",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_status == ThumbnailStatus.stabFailed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: Colors.red, size: 50.0),
            SizedBox(height: 10),
            Text(
              "Stabilization failed. We were unable to stabilize facial landmarks. Try the 'manual stabilization' option.",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    // Success state
    if (_status == ThumbnailStatus.success) {
      return widget.buildImage(File(widget.imagePath));
    }

    // Unknown state
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Unknown error occurred.",
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class RawThumbnail extends StatefulWidget {
  final String thumbnailPath;
  final int projectId;

  const RawThumbnail({
    super.key,
    required this.thumbnailPath,
    required this.projectId,
  });

  @override
  RawThumbnailState createState() => RawThumbnailState();
}

class RawThumbnailState extends State<RawThumbnail> {
  StreamSubscription<ThumbnailEvent>? _subscription;
  bool _ready = false;
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    _subscribeToStream();
    _checkInitialStatus();
  }

  @override
  void didUpdateWidget(covariant RawThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailPath != widget.thumbnailPath) {
      _ready = false;
      _checkedInitial = false;
      _checkInitialStatus();
    }
  }

  void _subscribeToStream() {
    _subscription = ThumbnailService.instance.stream.listen((event) {
      if (!mounted) return;
      if (event.thumbnailPath == widget.thumbnailPath &&
          event.status == ThumbnailStatus.success) {
        setState(() => _ready = true);
      }
    });
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    // 1. Check cache first
    final cachedStatus =
        ThumbnailService.instance.getStatus(widget.thumbnailPath);
    if (cachedStatus == ThumbnailStatus.success) {
      if (mounted) setState(() => _ready = true);
      return;
    }

    // 2. Check if file already exists on disk
    final file = File(widget.thumbnailPath);
    if (await file.exists() && await file.length() > 0) {
      if (mounted) setState(() => _ready = true);
      return;
    }

    // 3. No file yet - stay in loading state, stream will notify when ready
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const FlashingBox();
    }

    return Image.file(
      File(widget.thumbnailPath),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stack) => Container(color: Colors.black),
    );
  }
}
