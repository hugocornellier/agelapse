import 'dart:ui';

/// Exception thrown when an operation is cancelled via [CancellationToken].
class CancelledException implements Exception {
  final String? message;

  const CancelledException([this.message]);

  @override
  String toString() => message ?? 'Operation was cancelled';
}

/// A token that can be used to cooperatively cancel async operations.
///
/// Pass this token to long-running operations and periodically call
/// [throwIfCancelled] to check if cancellation has been requested.
///
/// Example:
/// ```dart
/// Future<void> longRunningTask(CancellationToken token) async {
///   for (final item in items) {
///     token.throwIfCancelled(); // Check before each iteration
///     await processItem(item);
///   }
/// }
/// ```
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Request cancellation of operations using this token.
  ///
  /// This sets [isCancelled] to true and notifies all registered listeners.
  /// Calling cancel multiple times has no additional effect.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    // Notify all listeners
    for (final listener in _listeners) {
      try {
        listener();
      } catch (_) {
        // Ignore errors in listeners
      }
    }
  }

  /// Register a callback to be notified when cancellation is requested.
  ///
  /// If the token is already cancelled, the callback is invoked immediately.
  void addListener(VoidCallback callback) {
    _listeners.add(callback);
    if (_isCancelled) {
      callback();
    }
  }

  /// Remove a previously registered callback.
  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  /// Throws [CancelledException] if cancellation has been requested.
  ///
  /// Call this periodically in long-running operations to enable
  /// cooperative cancellation.
  void throwIfCancelled([String? message]) {
    if (_isCancelled) {
      throw CancelledException(message);
    }
  }

  /// Resets the token to a non-cancelled state.
  ///
  /// Use with caution - typically you should create a new token instead.
  void reset() {
    _isCancelled = false;
  }
}
