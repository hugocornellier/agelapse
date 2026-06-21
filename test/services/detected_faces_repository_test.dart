import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/detected_faces_snapshot.dart';
import 'package:agelapse/models/face_detection_cache_result.dart';
import 'package:agelapse/services/detected_faces_repository.dart';

void main() {
  group('supportsProjectType', () {
    test('face is supported, case-insensitive', () {
      expect(DetectedFacesRepository.supportsProjectType('face'), isTrue);
      expect(DetectedFacesRepository.supportsProjectType('FACE'), isTrue);
    });

    test('non-face types are not supported in v1', () {
      for (final t in ['cat', 'dog', 'musc', 'pregnancy', 'pose', 'hand']) {
        expect(DetectedFacesRepository.supportsProjectType(t), isFalse,
            reason: t);
      }
    });
  });

  group('classifyCacheHit', () {
    test('no_faces sentinel -> noFaces', () {
      const sentinel =
          FaceDetectionCacheResult(orientation: 'no_faces', faces: []);
      expect(
        DetectedFacesRepository.classifyCacheHit(sentinel),
        DetectedFacesAvailability.noFaces,
      );
    });

    test('non-sentinel empty list -> error (malformed)', () {
      const malformed =
          FaceDetectionCacheResult(orientation: 'original', faces: []);
      expect(
        DetectedFacesRepository.classifyCacheHit(malformed),
        DetectedFacesAvailability.error,
      );
    });

    test('one or more faces -> available', () {
      final hit = FaceDetectionCacheResult(
        orientation: 'original',
        faces: const [CachedFace(boundingBox: Rect.fromLTRB(0, 0, 10, 10))],
        selectedFaceIndex: 0,
      );
      expect(
        DetectedFacesRepository.classifyCacheHit(hit),
        DetectedFacesAvailability.available,
      );
    });
  });

  group('classifyMiss', () {
    test('noFacesFlag wins regardless of other inputs', () {
      expect(
        DetectedFacesRepository.classifyMiss(
          rawFileExists: false,
          photoStabilized: false,
          noFacesFlag: true,
        ),
        DetectedFacesAvailability.noFaces,
      );
    });

    test('missing source (no flag) -> sourceMissing', () {
      expect(
        DetectedFacesRepository.classifyMiss(
          rawFileExists: false,
          photoStabilized: true,
          noFacesFlag: false,
        ),
        DetectedFacesAvailability.sourceMissing,
      );
    });

    test('not stabilized, source present -> notStabilized', () {
      expect(
        DetectedFacesRepository.classifyMiss(
          rawFileExists: true,
          photoStabilized: false,
          noFacesFlag: false,
        ),
        DetectedFacesAvailability.notStabilized,
      );
    });

    test('stabilized, source present, no rows -> legacyCacheMissing', () {
      expect(
        DetectedFacesRepository.classifyMiss(
          rawFileExists: true,
          photoStabilized: true,
          noFacesFlag: false,
        ),
        DetectedFacesAvailability.legacyCacheMissing,
      );
    });
  });

  group('messageFor', () {
    test('available has no message', () {
      expect(
          DetectedFacesRepository.messageFor(
              DetectedFacesAvailability.available),
          isNull);
    });

    test('legacy explains older-version + re-stabilize', () {
      final m = DetectedFacesRepository.messageFor(
          DetectedFacesAvailability.legacyCacheMissing)!;
      expect(m.toLowerCase(), contains('older version'));
      expect(m.toLowerCase(), contains('re-stabilize'));
    });

    test('every non-null state has a non-empty message', () {
      for (final a in [
        DetectedFacesAvailability.noFaces,
        DetectedFacesAvailability.notStabilized,
        DetectedFacesAvailability.legacyCacheMissing,
        DetectedFacesAvailability.staleOrChangedSource,
        DetectedFacesAvailability.sourceMissing,
        DetectedFacesAvailability.error,
      ]) {
        expect(DetectedFacesRepository.messageFor(a), isNotEmpty, reason: '$a');
      }
    });
  });
}
