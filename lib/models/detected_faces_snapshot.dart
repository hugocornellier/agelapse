import 'face_detection_cache_result.dart';

/// Why detected-face data is or isn't available for a photo. The UI must
/// distinguish these — never collapse every miss to "0 faces".
enum DetectedFacesAvailability {
  /// Exact cache hit with one or more faces.
  available,

  /// Exact `no_faces` sentinel, or a legacy `noFacesFound` flag. Count is 0.
  noFaces,

  /// Photo hasn't been stabilized yet; no detection has run.
  notStabilized,

  /// Photo was stabilized in an older version (or under a different model /
  /// changed source) with no current-key cache rows. Count/boxes unavailable;
  /// re-stabilization (or an opt-in re-detect) would populate them.
  legacyCacheMissing,

  /// Source fingerprint no longer matches the cached rows (file changed).
  staleOrChangedSource,

  /// The raw source file is missing on disk.
  sourceMissing,

  /// Project type that doesn't surface detected faces (e.g. pose-based).
  unsupportedProjectType,

  /// Lookup/decoding error.
  error,
}

/// Immutable description of a photo's detected-face state, resolved from the
/// `FaceDetectionCache` plus the active photo row. Holds metadata only — no
/// cropped bytes (those are produced lazily by the crop service).
class DetectedFacesSnapshot {
  final String timestamp;
  final int projectId;
  final String projectType;

  /// Resolved raw photo path (empty when unresolved, e.g. unsupported type).
  final String rawPath;

  /// Fingerprint used (or that would be used) for the cache key. May be null
  /// for legacy rows whose fingerprint hasn't been computed/backfilled.
  final String? fingerprint;

  /// Detector model version for [projectType], part of the cache key.
  final String? modelVersion;

  /// The exact cache result, when one was found.
  final FaceDetectionCacheResult? cache;

  final DetectedFacesAvailability availability;

  /// Non-authoritative `Photos.faceCount` (post-stabilization summary). May be
  /// shown as a hint while exact data is unavailable, but is never [count].
  final int? legacyFaceCount;

  /// Optional human-readable detail for the current availability.
  final String? message;

  const DetectedFacesSnapshot({
    required this.timestamp,
    required this.projectId,
    required this.projectType,
    required this.rawPath,
    required this.availability,
    this.fingerprint,
    this.modelVersion,
    this.cache,
    this.legacyFaceCount,
    this.message,
  });

  /// Number of detected faces when known, else null. Returns 0 only for
  /// [DetectedFacesAvailability.noFaces]; every other non-available state is
  /// null (unknown) so the UI can avoid rendering a misleading "0".
  int? get count {
    switch (availability) {
      case DetectedFacesAvailability.available:
        return cache?.faces.length;
      case DetectedFacesAvailability.noFaces:
        return 0;
      default:
        return null;
    }
  }

  /// Index of the face that was stabilized on, when known and in range.
  /// Null means "unknown selection" (e.g. legacy multi-face) — show no
  /// checkmark rather than guessing.
  int? get selectedFaceIndex {
    final c = cache;
    if (c == null) return null;
    final idx = c.selectedFaceIndex;
    if (idx == null) return null;
    if (idx < 0 || idx >= c.faces.length) return null;
    return idx;
  }

  /// Detection orientation the cached boxes live in
  /// (`original`/`flipped`/`cw`/`ccw`), needed to crop from the raw image.
  String? get orientation => cache?.orientation;

  /// True when there is at least one face to display.
  bool get hasFaces => (count ?? 0) > 0;

  /// True only on an exact cache hit with faces — the gate for the chip,
  /// info-section crops, and the standalone faces dialog.
  bool get isAvailable => availability == DetectedFacesAvailability.available;

  DetectedFacesSnapshot copyWith({
    FaceDetectionCacheResult? cache,
    DetectedFacesAvailability? availability,
    String? fingerprint,
    String? message,
  }) {
    return DetectedFacesSnapshot(
      timestamp: timestamp,
      projectId: projectId,
      projectType: projectType,
      rawPath: rawPath,
      availability: availability ?? this.availability,
      fingerprint: fingerprint ?? this.fingerprint,
      modelVersion: modelVersion,
      cache: cache ?? this.cache,
      legacyFaceCount: legacyFaceCount,
      message: message ?? this.message,
    );
  }
}
