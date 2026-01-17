import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../services/database_helper.dart';
import '../../services/thumbnail_service.dart';

/// Helper class for common thumbnail status checking logic.
/// Eliminates duplicate code across StabilizedThumbnail, StabilizedImagePreview, and RawThumbnail.
class ThumbnailStatusHelper {
  /// Checks the initial status of a thumbnail by:
  /// 1. Checking the ThumbnailService cache
  /// 2. Checking if the file exists on disk
  /// 3. Optionally checking DB for failure flags (noFacesFound, stabFailed)
  ///
  /// Returns:
  /// - [ThumbnailStatus] if a definitive status is found
  /// - null if no status found (still loading)
  ///
  /// [thumbnailPath] - Path to the thumbnail file
  /// [projectId] - Project ID for DB lookups
  /// [verifyFileSize] - If true, verifies file has content for success status
  /// [checkDbFlags] - If true, checks DB for noFacesFound/stabFailed flags
  static Future<ThumbnailStatus?> checkInitialStatus({
    required String thumbnailPath,
    required int projectId,
    bool verifyFileSize = false,
    bool checkDbFlags = true,
  }) async {
    // 1. Check cache first (for widgets mounting after event fired)
    final cachedStatus = ThumbnailService.instance.getStatus(thumbnailPath);
    if (cachedStatus != null) {
      if (cachedStatus == ThumbnailStatus.success && verifyFileSize) {
        // Verify file actually exists before trusting cache
        final file = File(thumbnailPath);
        if (await file.exists() && await file.length() > 0) {
          return cachedStatus;
        }
        // File doesn't exist yet, fall through to other checks
      } else {
        // Non-success status or no verification needed - trust the cache
        return cachedStatus;
      }
    }

    // 2. Check if file already exists on disk
    final file = File(thumbnailPath);
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) {
        return ThumbnailStatus.success;
      }
    }

    // 3. Check DB for failure flags (optional)
    if (checkDbFlags) {
      final String timestamp = path.basenameWithoutExtension(thumbnailPath);
      final photo = await DB.instance.getPhotoByTimestamp(timestamp, projectId);
      if (photo != null) {
        if (photo['noFacesFound'] == 1) return ThumbnailStatus.noFacesFound;
        if (photo['stabFailed'] == 1) return ThumbnailStatus.stabFailed;
      }
    }

    // 4. No status found - caller should stay in loading state
    return null;
  }

  /// Creates a stream subscription for thumbnail events.
  /// Returns the subscription so the caller can cancel it in dispose().
  ///
  /// [thumbnailPath] - Path to listen for
  /// [onEvent] - Callback when an event for this path is received
  static StreamSubscription<ThumbnailEvent> subscribeToStream({
    required String thumbnailPath,
    required void Function(ThumbnailEvent event) onEvent,
  }) {
    return ThumbnailService.instance.stream.listen((event) {
      if (event.thumbnailPath == thumbnailPath) {
        onEvent(event);
      }
    });
  }
}

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
    final dir = path.dirname(
      path.dirname(thumbnailPath),
    ); // Go up from thumbnails/
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
    _subscription = ThumbnailStatusHelper.subscribeToStream(
      thumbnailPath: widget.thumbnailPath,
      onEvent: (event) {
        if (!mounted) return;
        setState(() {
          _status = event.status;
          if (event.status == ThumbnailStatus.success) {
            _fileExists = true;
          }
        });
      },
    );
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    final status = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      verifyFileSize: true,
      checkDbFlags: true,
    );

    if (status != null && mounted) {
      setState(() {
        _status = status;
        if (status == ThumbnailStatus.success) {
          _fileExists = true;
        }
      });
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
    _subscription = ThumbnailStatusHelper.subscribeToStream(
      thumbnailPath: widget.thumbnailPath,
      onEvent: (event) {
        if (!mounted) return;
        setState(() => _status = event.status);
      },
    );
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    final status = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      verifyFileSize: false,
      checkDbFlags: true,
    );

    if (status != null && mounted) {
      setState(() => _status = status);
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
            Text('View raw photo by tapping "RAW"'),
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
    _subscription = ThumbnailStatusHelper.subscribeToStream(
      thumbnailPath: widget.thumbnailPath,
      onEvent: (event) {
        if (!mounted) return;
        if (event.status == ThumbnailStatus.success) {
          setState(() => _ready = true);
        }
      },
    );
  }

  Future<void> _checkInitialStatus() async {
    if (_checkedInitial) return;
    _checkedInitial = true;

    // Raw thumbnails don't check DB flags - only cache and file existence
    final status = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      verifyFileSize: true,
      checkDbFlags: false,
    );

    if (status == ThumbnailStatus.success && mounted) {
      setState(() => _ready = true);
    }
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
