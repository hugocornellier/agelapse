/// Represents the current state of the stabilization process.
///
/// This enum provides a clear state machine for the stabilization flow,
/// replacing the previous implicit boolean flag transitions.
enum StabilizationState {
  /// No stabilization operation is running
  idle,

  /// Initializing - loading photos, setting up face detector
  preparing,

  /// Actively stabilizing photos
  stabilizing,

  /// Cancel has been requested, cleaning up resources
  cancelling,

  /// Video compilation is in progress (FFmpeg running)
  compilingVideo,

  /// Video cancel has been requested, stopping FFmpeg
  cancellingVideo,

  /// All operations completed successfully
  completed,

  /// User cancelled the operation
  cancelled,

  /// An error occurred during processing
  error,
}

/// Extension methods for [StabilizationState] to check state categories.
extension StabilizationStateExtension on StabilizationState {
  /// Returns true if any operation is actively running.
  bool get isActive => switch (this) {
    StabilizationState.preparing ||
    StabilizationState.stabilizing ||
    StabilizationState.compilingVideo => true,
    _ => false,
  };

  /// Returns true if a cancellation is in progress.
  bool get isCancelling => switch (this) {
    StabilizationState.cancelling ||
    StabilizationState.cancellingVideo => true,
    _ => false,
  };

  /// Returns true if the process has finished (success, cancelled, or error).
  bool get isFinished => switch (this) {
    StabilizationState.idle ||
    StabilizationState.completed ||
    StabilizationState.cancelled ||
    StabilizationState.error => true,
    _ => false,
  };

  /// Returns true if video compilation is happening or being cancelled.
  bool get isVideoPhase => switch (this) {
    StabilizationState.compilingVideo ||
    StabilizationState.cancellingVideo => true,
    _ => false,
  };
}
