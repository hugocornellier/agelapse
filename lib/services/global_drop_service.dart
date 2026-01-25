import 'dart:async';

/// Item queued for import with project context.
class QueuedDropItem {
  final String path;
  final int projectId;
  final DateTime queuedAt;

  QueuedDropItem({required this.path, required this.projectId})
      : queuedAt = DateTime.now();
}

/// Central service for managing global drag-and-drop operations.
///
/// This service provides:
/// - Stream-based state updates for reactive UI (dragging, dropped files)
/// - File queuing when import is already in progress
/// - Coordination between global drop zone and GalleryPage import flow
/// - Project-scoped queue to prevent cross-project imports
///
/// Usage:
/// ```dart
/// // Subscribe to drag state changes
/// GlobalDropService.instance.dragStateStream.listen((isDragging) {
///   // Show/hide overlay
/// });
///
/// // Queue files when importing
/// GlobalDropService.instance.queueFiles(paths, projectId);
///
/// // Consume queued files for a project
/// final files = GlobalDropService.instance.consumeQueuedFiles(projectId);
/// ```
class GlobalDropService {
  GlobalDropService._internal();

  static final GlobalDropService _instance = GlobalDropService._internal();

  /// The singleton instance.
  static GlobalDropService get instance => _instance;

  // Streams for reactive UI
  final _dragStateController = StreamController<bool>.broadcast();
  final _queueUpdateController = StreamController<int>.broadcast();

  /// Stream of drag state changes (true = dragging over app).
  Stream<bool> get dragStateStream => _dragStateController.stream;

  /// Stream of queue count updates.
  Stream<int> get queueUpdateStream => _queueUpdateController.stream;

  // State - THIS IS THE SINGLE SOURCE OF TRUTH
  bool _isDragging = false;
  bool _importSheetOpen = false;

  // Queue with project context and limits
  static const int _maxQueueSize = 1000;
  final List<QueuedDropItem> _queuedItems = [];

  /// Whether files are currently being dragged over the app.
  bool get isDragging => _isDragging;

  /// Whether the import sheet is currently open.
  bool get importSheetOpen => _importSheetOpen;

  /// Number of files currently queued.
  int get queuedCount => _queuedItems.length;

  /// Whether there are any queued files.
  bool get hasQueuedFiles => _queuedItems.isNotEmpty;

  /// Set whether the import sheet is open (disables global overlay).
  void setImportSheetOpen(bool isOpen) {
    _importSheetOpen = isOpen;
  }

  /// Called when drag enters app window.
  void onDragEnter() {
    if (_isDragging) return; // Already dragging
    _isDragging = true;
    _dragStateController.add(true);
  }

  /// Called when drag exits app window.
  void onDragExit() {
    if (!_isDragging) return;
    _isDragging = false;
    _dragStateController.add(false);
  }

  /// Queue files with project context.
  ///
  /// Returns true if files were queued successfully, false if queue is full.
  /// Files are deduplicated by path.
  bool queueFiles(List<String> filePaths, int projectId) {
    // Dedupe by path
    final existingPaths = _queuedItems.map((i) => i.path).toSet();
    final newPaths =
        filePaths.where((p) => !existingPaths.contains(p)).toList();

    // Check queue limit
    if (_queuedItems.length + newPaths.length > _maxQueueSize) {
      return false; // Queue full
    }

    for (final path in newPaths) {
      _queuedItems.add(QueuedDropItem(path: path, projectId: projectId));
    }
    _queueUpdateController.add(_queuedItems.length);
    return true;
  }

  /// Consume queued files for a specific project only.
  ///
  /// Returns the file paths and removes them from the queue.
  /// Only returns files that match the given projectId.
  List<String> consumeQueuedFiles(int projectId) {
    final matching =
        _queuedItems.where((i) => i.projectId == projectId).toList();
    _queuedItems.removeWhere((i) => i.projectId == projectId);
    _queueUpdateController.add(_queuedItems.length);
    return matching.map((i) => i.path).toList();
  }

  /// Clear all queued files.
  void clearQueue() {
    _queuedItems.clear();
    _queueUpdateController.add(0);
  }

  /// Dispose of stream controllers.
  void dispose() {
    _dragStateController.close();
    _queueUpdateController.close();
  }
}
