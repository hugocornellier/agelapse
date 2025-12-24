import 'dart:isolate';

/// Manages active isolates and provides instant kill capability.
///
/// This singleton tracks all spawned isolates for stabilization operations,
/// allowing them to be terminated instantly when cancellation is requested.
///
/// Usage:
/// ```dart
/// final isolate = await Isolate.spawn(entryPoint, message);
/// IsolateManager.instance.register(isolate);
///
/// try {
///   final result = await receivePort.first;
///   return result;
/// } finally {
///   IsolateManager.instance.unregister(isolate);
///   isolate.kill(priority: Isolate.immediate);
/// }
/// ```
class IsolateManager {
  IsolateManager._internal();

  static final IsolateManager _instance = IsolateManager._internal();

  /// The singleton instance.
  static IsolateManager get instance => _instance;

  /// Set of currently active isolates.
  final Set<Isolate> _activeIsolates = {};

  /// Number of currently active isolates.
  int get activeCount => _activeIsolates.length;

  /// Whether there are any active isolates.
  bool get hasActiveIsolates => _activeIsolates.isNotEmpty;

  /// Register an isolate for tracking.
  ///
  /// Call this immediately after spawning an isolate.
  void register(Isolate isolate) {
    _activeIsolates.add(isolate);
  }

  /// Unregister an isolate from tracking.
  ///
  /// Call this when an isolate completes normally (before killing it).
  void unregister(Isolate isolate) {
    _activeIsolates.remove(isolate);
  }

  /// Kill ALL active isolates instantly.
  ///
  /// This terminates all tracked isolates immediately with [Isolate.immediate]
  /// priority, which is the fastest way to stop them.
  ///
  /// After calling this, [activeCount] will be 0.
  void killAll() {
    if (_activeIsolates.isEmpty) return;

    for (final isolate in _activeIsolates) {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {
        // Ignore errors when killing isolates
      }
    }

    _activeIsolates.clear();
  }

  /// Clear the tracking set without killing isolates.
  ///
  /// Use this only for cleanup when you're sure isolates are already dead.
  void clear() {
    _activeIsolates.clear();
  }
}
