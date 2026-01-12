import 'stabilization_state.dart';

/// Represents the current progress of stabilization/video compilation.
///
/// This is an immutable snapshot of the current state that can be
/// streamed to UI components for reactive updates.
class StabilizationProgress {
  /// The current state of the stabilization process.
  final StabilizationState state;

  /// Current photo index being processed (1-indexed for display).
  final int currentPhoto;

  /// Total number of photos to stabilize.
  final int totalPhotos;

  /// Overall progress percentage (0-100).
  final int progressPercent;

  /// Estimated time remaining (formatted string, e.g., "2h 30m 15s").
  final String? eta;

  /// Error message if state is [StabilizationState.error].
  final String? errorMessage;

  /// Current frame being encoded (for video compilation).
  final int? currentFrame;

  /// Total frames to encode (for video compilation).
  final int? totalFrames;

  /// The project ID this progress relates to.
  final int? projectId;

  /// Timestamp of the last stabilized photo (for incremental UI updates).
  final String? lastStabilizedTimestamp;

  const StabilizationProgress({
    required this.state,
    this.currentPhoto = 0,
    this.totalPhotos = 0,
    this.progressPercent = 0,
    this.eta,
    this.errorMessage,
    this.currentFrame,
    this.totalFrames,
    this.projectId,
    this.lastStabilizedTimestamp,
  });

  /// Creates an idle state with no active operation.
  factory StabilizationProgress.idle() =>
      const StabilizationProgress(state: StabilizationState.idle);

  /// Creates a preparing state when initializing.
  factory StabilizationProgress.preparing({int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.preparing,
        projectId: projectId,
      );

  /// Creates a stabilizing state with progress info.
  factory StabilizationProgress.stabilizing({
    required int currentPhoto,
    required int totalPhotos,
    required int progressPercent,
    String? eta,
    int? projectId,
    String? lastStabilizedTimestamp,
  }) =>
      StabilizationProgress(
        state: StabilizationState.stabilizing,
        currentPhoto: currentPhoto,
        totalPhotos: totalPhotos,
        progressPercent: progressPercent,
        eta: eta,
        projectId: projectId,
        lastStabilizedTimestamp: lastStabilizedTimestamp,
      );

  /// Creates a cancelling state.
  factory StabilizationProgress.cancelling({int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.cancelling,
        projectId: projectId,
      );

  /// Creates a video compilation state with progress info.
  factory StabilizationProgress.compilingVideo({
    required int currentFrame,
    required int totalFrames,
    required int progressPercent,
    int? projectId,
  }) =>
      StabilizationProgress(
        state: StabilizationState.compilingVideo,
        currentFrame: currentFrame,
        totalFrames: totalFrames,
        progressPercent: progressPercent,
        projectId: projectId,
      );

  /// Creates a video cancelling state.
  factory StabilizationProgress.cancellingVideo({int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.cancellingVideo,
        projectId: projectId,
      );

  /// Creates a completed state.
  factory StabilizationProgress.completed({int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.completed,
        projectId: projectId,
      );

  /// Creates a cancelled state.
  factory StabilizationProgress.cancelled({int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.cancelled,
        projectId: projectId,
      );

  /// Creates an error state with a message.
  factory StabilizationProgress.error(String message, {int? projectId}) =>
      StabilizationProgress(
        state: StabilizationState.error,
        errorMessage: message,
        projectId: projectId,
      );

  /// Creates a copy with modified fields.
  StabilizationProgress copyWith({
    StabilizationState? state,
    int? currentPhoto,
    int? totalPhotos,
    int? progressPercent,
    String? eta,
    String? errorMessage,
    int? currentFrame,
    int? totalFrames,
    int? projectId,
    String? lastStabilizedTimestamp,
  }) =>
      StabilizationProgress(
        state: state ?? this.state,
        currentPhoto: currentPhoto ?? this.currentPhoto,
        totalPhotos: totalPhotos ?? this.totalPhotos,
        progressPercent: progressPercent ?? this.progressPercent,
        eta: eta ?? this.eta,
        errorMessage: errorMessage ?? this.errorMessage,
        currentFrame: currentFrame ?? this.currentFrame,
        totalFrames: totalFrames ?? this.totalFrames,
        projectId: projectId ?? this.projectId,
        lastStabilizedTimestamp:
            lastStabilizedTimestamp ?? this.lastStabilizedTimestamp,
      );

  @override
  String toString() => 'StabilizationProgress('
      'state: $state, '
      'photo: $currentPhoto/$totalPhotos, '
      'progress: $progressPercent%, '
      'eta: $eta, '
      'frame: $currentFrame/$totalFrames'
      ')';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StabilizationProgress &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          currentPhoto == other.currentPhoto &&
          totalPhotos == other.totalPhotos &&
          progressPercent == other.progressPercent &&
          eta == other.eta &&
          errorMessage == other.errorMessage &&
          currentFrame == other.currentFrame &&
          totalFrames == other.totalFrames &&
          projectId == other.projectId &&
          lastStabilizedTimestamp == other.lastStabilizedTimestamp;

  @override
  int get hashCode => Object.hash(
        state,
        currentPhoto,
        totalPhotos,
        progressPercent,
        eta,
        errorMessage,
        currentFrame,
        totalFrames,
        projectId,
        lastStabilizedTimestamp,
      );
}
