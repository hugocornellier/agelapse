import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../services/database_helper.dart';
import '../../services/thumbnail_service.dart';
import '../../styles/styles.dart';

/// Result from checking thumbnail status, includes both status and thumbnail existence.
class ThumbnailCheckResult {
  final ThumbnailStatus status;
  final bool thumbnailExists;

  const ThumbnailCheckResult({
    required this.status,
    required this.thumbnailExists,
  });
}

/// Helper class for common thumbnail status checking logic.
/// Eliminates duplicate code across StabilizedThumbnail, StabilizedImagePreview, and RawThumbnail.
class ThumbnailStatusHelper {
  /// Checks the initial status of a thumbnail by:
  /// 1. Checking the ThumbnailService cache
  /// 2. Checking if the thumbnail file exists on disk
  /// 3. Checking if the full stabilized image exists (fallback)
  /// 4. Optionally checking DB for failure flags (noFacesFound, stabFailed)
  ///
  /// Returns:
  /// - [ThumbnailCheckResult] with status and thumbnailExists flag if found
  /// - null if no status found (still loading)
  ///
  /// [thumbnailPath] - Path to the thumbnail file
  /// [projectId] - Project ID for DB lookups
  /// [stabilizedImagePath] - Optional path to full image for fallback check
  /// [verifyFileSize] - If true, verifies file has content for success status
  /// [checkDbFlags] - If true, checks DB for noFacesFound/stabFailed flags
  static Future<ThumbnailCheckResult?> checkInitialStatus({
    required String thumbnailPath,
    required int projectId,
    String? stabilizedImagePath,
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
          return ThumbnailCheckResult(
            status: cachedStatus,
            thumbnailExists: true,
          );
        }
        // Thumbnail doesn't exist, fall through to check full image
      } else {
        // Non-success status or no verification needed - trust the cache
        return ThumbnailCheckResult(
          status: cachedStatus,
          thumbnailExists: false,
        );
      }
    }

    // 2. Check if thumbnail file already exists on disk
    final file = File(thumbnailPath);
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) {
        return ThumbnailCheckResult(
          status: ThumbnailStatus.success,
          thumbnailExists: true,
        );
      }
    }

    // 3. Check if full stabilized image exists as fallback
    if (stabilizedImagePath != null) {
      final stabFile = File(stabilizedImagePath);
      if (await stabFile.exists() && await stabFile.length() > 0) {
        // Thumbnail missing but full image exists - treat as success
        return ThumbnailCheckResult(
          status: ThumbnailStatus.success,
          thumbnailExists: false,
        );
      }
    }

    // 4. Check DB for failure flags (optional)
    if (checkDbFlags) {
      final String timestamp = path.basenameWithoutExtension(thumbnailPath);
      final photo = await DB.instance.getPhotoByTimestamp(timestamp, projectId);
      if (photo != null) {
        if (photo['noFacesFound'] == 1) {
          return ThumbnailCheckResult(
            status: ThumbnailStatus.noFacesFound,
            thumbnailExists: false,
          );
        }
        if (photo['stabFailed'] == 1) {
          return ThumbnailCheckResult(
            status: ThumbnailStatus.stabFailed,
            thumbnailExists: false,
          );
        }
      }
    }

    // 5. No status found - caller should stay in loading state
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
        color: AppColors.textSecondary,
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
      // 1. Cancel old subscription FIRST
      _subscription?.cancel();

      // 2. Create new subscription for new path
      _subscribeToStream();

      // 3. Reset state
      _status = null;
      _fileExists = false;
      _checkedInitial = false;

      // 4. Check initial status for new path
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

    // Capture path at start to detect stale results
    final pathAtStart = widget.thumbnailPath;

    final result = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      stabilizedImagePath: widget.stabilizedImagePath,
      verifyFileSize: true,
      checkDbFlags: true,
    );

    // Guard: ignore result if path changed during async operation
    if (!mounted || widget.thumbnailPath != pathAtStart) return;

    if (result != null) {
      setState(() {
        _status = result.status;
        _fileExists = result.thumbnailExists;
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
        child: Stack(
          children: [
            Positioned(
              top: 8.0,
              right: 8.0,
              child: Icon(Icons.error, color: AppColors.danger, size: 24.0),
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
      errorBuilder: (context, error, stack) =>
          Container(color: AppColors.textSecondary),
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

    // Capture path at start to detect stale results
    final pathAtStart = widget.thumbnailPath;

    final result = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      stabilizedImagePath: widget.imagePath,
      verifyFileSize: false,
      checkDbFlags: true,
    );

    // Guard: ignore result if path changed during async operation
    if (!mounted || widget.thumbnailPath != pathAtStart) return;

    if (result != null) {
      setState(() => _status = result.status);
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Image being stabilized. Please wait...",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            const Text('View raw photo by tapping "RAW"'),
          ],
        ),
      );
    }

    // Failure states
    if (_status == ThumbnailStatus.noFacesFound) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: AppColors.danger, size: 50.0),
            const SizedBox(height: 10),
            Text(
              "Stabilization failed. No faces found. Try the 'manual stabilization' option.",
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
      );
    }

    if (_status == ThumbnailStatus.stabFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: AppColors.danger, size: 50.0),
            const SizedBox(height: 10),
            Text(
              "Stabilization failed. We were unable to stabilize facial landmarks. Try the 'manual stabilization' option.",
              style: TextStyle(color: AppColors.textPrimary),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Unknown error occurred.",
            style: TextStyle(color: AppColors.textPrimary),
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
      // 1. Cancel old subscription FIRST
      _subscription?.cancel();

      // 2. Create new subscription for new path
      _subscribeToStream();

      // 3. Reset state
      _ready = false;
      _checkedInitial = false;

      // 4. Check initial status for new path
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

    // Capture path at start to detect stale results
    final pathAtStart = widget.thumbnailPath;

    // Raw thumbnails don't check DB flags - only cache and file existence
    final result = await ThumbnailStatusHelper.checkInitialStatus(
      thumbnailPath: widget.thumbnailPath,
      projectId: widget.projectId,
      verifyFileSize: true,
      checkDbFlags: false,
    );

    // Guard: ignore result if path changed during async operation
    if (!mounted || widget.thumbnailPath != pathAtStart) return;

    if (result?.status == ThumbnailStatus.success) {
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
      errorBuilder: (context, error, stack) =>
          Container(color: AppColors.overlay),
    );
  }
}
