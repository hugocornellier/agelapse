import 'dart:async';

enum ThumbnailStatus { success, noFacesFound, stabFailed }

class ThumbnailEvent {
  final String thumbnailPath;
  final ThumbnailStatus status;
  final int projectId;
  final String timestamp;

  ThumbnailEvent({
    required this.thumbnailPath,
    required this.status,
    required this.projectId,
    required this.timestamp,
  });
}

class ThumbnailService {
  static final ThumbnailService _instance = ThumbnailService._internal();
  static ThumbnailService get instance => _instance;
  ThumbnailService._internal();

  final StreamController<ThumbnailEvent> _controller =
      StreamController<ThumbnailEvent>.broadcast();

  Stream<ThumbnailEvent> get stream => _controller.stream;

  // Cache for widgets that mount after event fires
  final Map<String, ThumbnailStatus> _statusCache = {};

  ThumbnailStatus? getStatus(String thumbnailPath) =>
      _statusCache[thumbnailPath];

  void emit(ThumbnailEvent event) {
    _statusCache[event.thumbnailPath] = event.status;
    _controller.add(event);
  }

  void clearCache(String thumbnailPath) {
    _statusCache.remove(thumbnailPath);
  }

  /// Clear all cached statuses. Call this when switching projects
  /// to prevent stale data and reduce memory usage.
  void clearAllCache() {
    _statusCache.clear();
  }

  void dispose() {
    _controller.close();
  }
}
