import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/detected_faces_snapshot.dart';
import 'package:agelapse/models/face_detection_cache_result.dart';

FaceDetectionCacheResult _cache(
  int n, {
  int? selected,
  String orientation = 'original',
}) {
  return FaceDetectionCacheResult(
    orientation: orientation,
    faces: List.generate(
      n,
      (i) => CachedFace(
        boundingBox: Rect.fromLTRB(i * 10.0, 0, i * 10.0 + 10, 10),
      ),
    ),
    selectedFaceIndex: selected,
  );
}

DetectedFacesSnapshot _snap(
  DetectedFacesAvailability a, {
  FaceDetectionCacheResult? cache,
  int? legacy,
}) {
  return DetectedFacesSnapshot(
    timestamp: 't',
    projectId: 1,
    projectType: 'face',
    rawPath: '/x',
    availability: a,
    cache: cache,
    legacyFaceCount: legacy,
  );
}

void main() {
  group('count', () {
    test('available returns cache face count', () {
      expect(
        _snap(DetectedFacesAvailability.available, cache: _cache(3)).count,
        3,
      );
    });

    test('noFaces returns 0', () {
      expect(_snap(DetectedFacesAvailability.noFaces).count, 0);
    });

    test('every other state returns null (never a misleading 0)', () {
      for (final a in [
        DetectedFacesAvailability.notStabilized,
        DetectedFacesAvailability.legacyCacheMissing,
        DetectedFacesAvailability.staleOrChangedSource,
        DetectedFacesAvailability.sourceMissing,
        DetectedFacesAvailability.unsupportedProjectType,
        DetectedFacesAvailability.error,
      ]) {
        expect(_snap(a).count, isNull, reason: '$a');
      }
    });

    test('legacyFaceCount does not leak into count', () {
      final s = _snap(DetectedFacesAvailability.legacyCacheMissing, legacy: 4);
      expect(s.count, isNull);
      expect(s.legacyFaceCount, 4);
    });
  });

  group('selectedFaceIndex', () {
    test('valid in-range index is returned', () {
      final s = _snap(
        DetectedFacesAvailability.available,
        cache: _cache(3, selected: 1),
      );
      expect(s.selectedFaceIndex, 1);
    });

    test('null selection returns null', () {
      final s = _snap(
        DetectedFacesAvailability.available,
        cache: _cache(3, selected: null),
      );
      expect(s.selectedFaceIndex, isNull);
    });

    test('out-of-range index returns null', () {
      expect(
        _snap(DetectedFacesAvailability.available,
                cache: _cache(2, selected: 5))
            .selectedFaceIndex,
        isNull,
      );
      expect(
        _snap(DetectedFacesAvailability.available,
                cache: _cache(2, selected: -1))
            .selectedFaceIndex,
        isNull,
      );
    });

    test('no cache returns null', () {
      expect(_snap(DetectedFacesAvailability.notStabilized).selectedFaceIndex,
          isNull);
    });
  });

  group('orientation / hasFaces / isAvailable', () {
    test('orientation reflects cache, null without cache', () {
      expect(
        _snap(DetectedFacesAvailability.available,
                cache: _cache(1, orientation: 'cw'))
            .orientation,
        'cw',
      );
      expect(
          _snap(DetectedFacesAvailability.notStabilized).orientation, isNull);
    });

    test('hasFaces true only when count > 0', () {
      expect(
        _snap(DetectedFacesAvailability.available, cache: _cache(2)).hasFaces,
        isTrue,
      );
      expect(_snap(DetectedFacesAvailability.noFaces).hasFaces, isFalse);
      expect(_snap(DetectedFacesAvailability.legacyCacheMissing).hasFaces,
          isFalse);
    });

    test('isAvailable true only for available', () {
      expect(
        _snap(DetectedFacesAvailability.available, cache: _cache(1))
            .isAvailable,
        isTrue,
      );
      expect(_snap(DetectedFacesAvailability.noFaces).isAvailable, isFalse);
    });
  });

  group('copyWith', () {
    test('updates given fields, preserves the rest', () {
      final base = _snap(DetectedFacesAvailability.legacyCacheMissing);
      final updated = base.copyWith(
        availability: DetectedFacesAvailability.available,
        cache: _cache(2, selected: 0),
        fingerprint: 'fp',
        message: 'm',
      );
      expect(updated.availability, DetectedFacesAvailability.available);
      expect(updated.count, 2);
      expect(updated.fingerprint, 'fp');
      expect(updated.message, 'm');
      // preserved
      expect(updated.timestamp, base.timestamp);
      expect(updated.projectId, base.projectId);
      expect(updated.projectType, base.projectType);
      expect(updated.rawPath, base.rawPath);
    });
  });
}
