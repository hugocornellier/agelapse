/// Types of stabilization update events.
enum StabUpdateType {
  /// A single photo was stabilized (normal progress update)
  photoStabilized,

  /// All photos have been stabilized (stabilization phase complete)
  stabilizationComplete,

  /// Video compilation has finished
  videoComplete,

  /// Stabilization or video was cancelled
  cancelled,

  /// An error occurred
  error,
}

/// Event emitted during stabilization to notify UI components of updates.
///
/// This replaces the raw `int` stream to provide context about what happened,
/// allowing consumers to react differently to progress updates vs completion.
class StabUpdateEvent {
  /// The type of event that occurred.
  final StabUpdateType type;

  /// Current photo index (only relevant for [StabUpdateType.photoStabilized]).
  final int? photoIndex;

  const StabUpdateEvent._({
    required this.type,
    this.photoIndex,
  });

  /// A photo was stabilized during normal progress.
  factory StabUpdateEvent.photoStabilized(int photoIndex) => StabUpdateEvent._(
        type: StabUpdateType.photoStabilized,
        photoIndex: photoIndex,
      );

  /// All photos have been stabilized.
  factory StabUpdateEvent.stabilizationComplete() => const StabUpdateEvent._(
        type: StabUpdateType.stabilizationComplete,
      );

  /// Video compilation finished.
  factory StabUpdateEvent.videoComplete() => const StabUpdateEvent._(
        type: StabUpdateType.videoComplete,
      );

  /// Operation was cancelled.
  factory StabUpdateEvent.cancelled() => const StabUpdateEvent._(
        type: StabUpdateType.cancelled,
      );

  /// An error occurred.
  factory StabUpdateEvent.error() => const StabUpdateEvent._(
        type: StabUpdateType.error,
      );

  /// Whether this is a "completion" type event that should force UI refresh.
  bool get isCompletionEvent =>
      type == StabUpdateType.stabilizationComplete ||
      type == StabUpdateType.videoComplete ||
      type == StabUpdateType.cancelled ||
      type == StabUpdateType.error;

  @override
  String toString() => 'StabUpdateEvent($type, photoIndex: $photoIndex)';
}
