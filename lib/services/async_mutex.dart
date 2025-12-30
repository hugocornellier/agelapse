import 'dart:async';

/// A simple async mutex for serializing access to shared resources.
///
/// Usage:
/// ```dart
/// final mutex = AsyncMutex();
///
/// // Option 1: Manual acquire/release
/// await mutex.acquire();
/// try {
///   // critical section
/// } finally {
///   mutex.release();
/// }
///
/// // Option 2: Use protect() for automatic release
/// final result = await mutex.protect(() async {
///   // critical section
///   return someValue;
/// });
/// ```
class AsyncMutex {
  Completer<void>? _lock;

  /// Whether the mutex is currently held by a caller.
  bool get isLocked => _lock != null && !_lock!.isCompleted;

  /// Acquire the lock. Waits if another caller holds it.
  ///
  /// Always pair with [release] in a finally block, or use [protect] instead.
  Future<void> acquire() async {
    // Wait for any existing lock to be released
    while (_lock != null && !_lock!.isCompleted) {
      await _lock!.future;
    }
    // Create a new lock
    _lock = Completer<void>();
  }

  /// Release the lock, allowing the next waiting caller to proceed.
  void release() {
    if (_lock != null && !_lock!.isCompleted) {
      _lock!.complete();
    }
  }

  /// Execute a function while holding the lock.
  ///
  /// This is the preferred way to use the mutex as it guarantees the lock
  /// is released even if the function throws an exception.
  Future<T> protect<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
