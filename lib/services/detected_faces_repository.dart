import 'dart:io';

import '../models/detected_faces_snapshot.dart';
import '../models/face_detection_cache_result.dart';
import '../utils/dir_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// Resolves a photo's [DetectedFacesSnapshot] from the `FaceDetectionCache`
/// plus the active photo row. This is the single authoritative source the
/// header chip, info-dialog section, and standalone faces dialog all read from.
///
/// The branching that turns raw lookups into an explicit availability lives in
/// the pure [classifyCacheHit]/[classifyMiss] helpers so it can be unit-tested
/// without a database.
class DetectedFacesRepository {
  /// Project types that surface detected faces in v1. Cat/dog also cache
  /// subject boxes but need product wording + selected-index work; pose-based
  /// types don't write face boxes. Face only for now.
  static const Set<String> supportedProjectTypes = {'face'};

  static bool supportsProjectType(String projectType) =>
      supportedProjectTypes.contains(projectType.toLowerCase());

  // ---------------------------------------------------------------------------
  // Pure classification (no IO; unit-tested directly).
  // ---------------------------------------------------------------------------

  /// Classifies an exact cache hit. A non-sentinel row set with no faces is
  /// malformed and reported as [DetectedFacesAvailability.error].
  static DetectedFacesAvailability classifyCacheHit(
    FaceDetectionCacheResult cache,
  ) {
    if (cache.isNoFaces) return DetectedFacesAvailability.noFaces;
    if (cache.faces.isEmpty) return DetectedFacesAvailability.error;
    return DetectedFacesAvailability.available;
  }

  /// Classifies the absence of a current-key cache row. Ordering favors the
  /// most informative/actionable state.
  static DetectedFacesAvailability classifyMiss({
    required bool rawFileExists,
    required bool photoStabilized,
    required bool noFacesFlag,
  }) {
    if (noFacesFlag) return DetectedFacesAvailability.noFaces;
    if (!rawFileExists) return DetectedFacesAvailability.sourceMissing;
    if (!photoStabilized) return DetectedFacesAvailability.notStabilized;
    return DetectedFacesAvailability.legacyCacheMissing;
  }

  static String? messageFor(DetectedFacesAvailability a) {
    switch (a) {
      case DetectedFacesAvailability.available:
        return null;
      case DetectedFacesAvailability.noFaces:
        return 'No faces detected.';
      case DetectedFacesAvailability.notStabilized:
        return 'Not detected yet.';
      case DetectedFacesAvailability.legacyCacheMissing:
        return 'Face details weren\'t recorded for photos stabilized in an '
            'older version. Re-stabilize to generate them.';
      case DetectedFacesAvailability.staleOrChangedSource:
        return 'The source image changed. Re-stabilize to refresh face data.';
      case DetectedFacesAvailability.sourceMissing:
        return 'The source image is missing.';
      case DetectedFacesAvailability.unsupportedProjectType:
        return null;
      case DetectedFacesAvailability.error:
        return 'Face data is unavailable.';
    }
  }

  // ---------------------------------------------------------------------------
  // IO load.
  // ---------------------------------------------------------------------------

  /// Loads the snapshot for ([timestamp], [projectId]).
  ///
  /// [projectType] may be supplied to skip a DB lookup. By default a missing
  /// stored fingerprint is NOT recomputed (keeps the per-swipe header path
  /// cheap) — set [computeFingerprintIfMissing] for the detailed dialogs.
  Future<DetectedFacesSnapshot> load(
    String timestamp,
    int projectId, {
    String? projectType,
    bool computeFingerprintIfMissing = false,
  }) async {
    final String type = (projectType ??
            await DB.instance.getProjectTypeByProjectId(projectId) ??
            'face')
        .toLowerCase();

    if (!supportsProjectType(type)) {
      return DetectedFacesSnapshot(
        timestamp: timestamp,
        projectId: projectId,
        projectType: type,
        rawPath: '',
        availability: DetectedFacesAvailability.unsupportedProjectType,
      );
    }

    final photo =
        await DB.instance.getActivePhotoByTimestamp(timestamp, projectId);
    if (photo == null) {
      return DetectedFacesSnapshot(
        timestamp: timestamp,
        projectId: projectId,
        projectType: type,
        rawPath: '',
        availability: DetectedFacesAvailability.error,
        message: 'Photo not found.',
      );
    }

    final String? fileExtension = photo['fileExtension'] as String?;
    final String rawPath =
        await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      timestamp,
      projectId,
      fileExtension: fileExtension,
    );
    final bool rawExists = await File(rawPath).exists();

    final bool photoStabilized =
        photo['stabilizedPortrait'] == 1 || photo['stabilizedLandscape'] == 1;
    final bool noFacesFlag = photo['noFacesFound'] == 1;
    final int? legacyFaceCount = photo['faceCount'] as int?;

    final String modelVersion =
        StabUtils.detectorModelVersionForProjectType(type);

    String? fingerprint = photo['fingerprint'] as String?;
    if (fingerprint != null && fingerprint.isEmpty) fingerprint = null;

    if (fingerprint == null && computeFingerprintIfMissing && rawExists) {
      try {
        fingerprint = await StabUtils.computeRawPhotoFingerprint(rawPath);
        await DB.instance
            .backfillPhotoFingerprint(timestamp, projectId, fingerprint);
      } catch (e) {
        LogService.instance
            .log('[detected-faces] fingerprint compute failed: $e');
        fingerprint = null;
      }
    }

    FaceDetectionCacheResult? cache;
    if (fingerprint != null) {
      try {
        cache = await DB.instance.getFaceDetectionCache(
          timestamp,
          projectId,
          modelVersion,
          fingerprint,
        );
      } catch (e) {
        LogService.instance.log('[detected-faces] cache read failed: $e');
      }
    }

    final DetectedFacesAvailability availability = cache != null
        ? classifyCacheHit(cache)
        : classifyMiss(
            rawFileExists: rawExists,
            photoStabilized: photoStabilized,
            noFacesFlag: noFacesFlag,
          );

    return DetectedFacesSnapshot(
      timestamp: timestamp,
      projectId: projectId,
      projectType: type,
      rawPath: rawPath,
      fingerprint: fingerprint,
      modelVersion: modelVersion,
      cache: cache,
      availability: availability,
      legacyFaceCount: legacyFaceCount,
      message: messageFor(availability),
    );
  }
}
