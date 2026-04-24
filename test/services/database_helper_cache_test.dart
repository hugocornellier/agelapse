import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/face_detection_cache_result.dart';
import 'package:agelapse/models/transform_cache_entry.dart';
import 'package:agelapse/services/database_helper.dart';

void main() {
  group('CachedFace', () {
    test('stores boundingBox', () {
      const face = CachedFace(boundingBox: Rect.fromLTRB(1, 2, 3, 4));
      expect(face.boundingBox, const Rect.fromLTRB(1, 2, 3, 4));
    });

    test('leftEye and rightEye default to null', () {
      const face = CachedFace(boundingBox: Rect.fromLTRB(0, 0, 10, 10));
      expect(face.leftEye, isNull);
      expect(face.rightEye, isNull);
    });

    test('stores eye landmarks when provided', () {
      final face = CachedFace(
        boundingBox: const Rect.fromLTRB(0, 0, 100, 100),
        leftEye: const Point<double>(25.0, 40.0),
        rightEye: const Point<double>(75.0, 40.0),
      );
      expect(face.leftEye, const Point<double>(25.0, 40.0));
      expect(face.rightEye, const Point<double>(75.0, 40.0));
    });

    test('is const-constructible', () {
      const face = CachedFace(
        boundingBox: Rect.fromLTRB(0, 0, 1, 1),
        leftEye: Point<double>(0.1, 0.2),
        rightEye: Point<double>(0.8, 0.2),
      );
      expect(face, isA<CachedFace>());
    });
  });

  group('FaceDetectionCacheResult', () {
    test('isNoFaces returns true when orientation is no_faces', () {
      const result = FaceDetectionCacheResult(
        orientation: 'no_faces',
        faces: [],
      );
      expect(result.isNoFaces, isTrue);
    });

    test('isNoFaces returns false for original orientation', () {
      const result = FaceDetectionCacheResult(
        orientation: 'original',
        faces: [],
      );
      expect(result.isNoFaces, isFalse);
    });

    test('isNoFaces returns false for flipped orientation', () {
      const result = FaceDetectionCacheResult(
        orientation: 'flipped',
        faces: [],
      );
      expect(result.isNoFaces, isFalse);
    });

    test('isNoFaces returns false for ccw orientation', () {
      const result = FaceDetectionCacheResult(orientation: 'ccw', faces: []);
      expect(result.isNoFaces, isFalse);
    });

    test('isNoFaces returns false for cw orientation', () {
      const result = FaceDetectionCacheResult(orientation: 'cw', faces: []);
      expect(result.isNoFaces, isFalse);
    });

    test('stores orientation and faces', () {
      final face = CachedFace(
        boundingBox: const Rect.fromLTRB(10, 20, 30, 40),
        leftEye: const Point<double>(15.0, 28.0),
        rightEye: const Point<double>(25.0, 28.0),
      );
      final result = FaceDetectionCacheResult(
        orientation: 'original',
        faces: [face],
        selectedFaceIndex: 0,
      );
      expect(result.orientation, 'original');
      expect(result.faces.length, 1);
      expect(
        result.faces.first.boundingBox,
        const Rect.fromLTRB(10, 20, 30, 40),
      );
      expect(result.selectedFaceIndex, 0);
    });

    test('no_faces result has empty faces list', () {
      const result = FaceDetectionCacheResult(
        orientation: 'no_faces',
        faces: [],
      );
      expect(result.faces, isEmpty);
    });

    test('is const-constructible', () {
      const result = FaceDetectionCacheResult(
        orientation: 'no_faces',
        faces: [],
      );
      expect(result, isA<FaceDetectionCacheResult>());
    });
  });

  group('DB faceDetectionCacheTable constant', () {
    test('table name is FaceDetectionCache', () {
      expect(DB.faceDetectionCacheTable, 'FaceDetectionCache');
    });
  });

  group('TransformCacheEntry', () {
    test('round-trips through map conversion', () {
      const entry = TransformCacheEntry(
        id: 10,
        cacheKey: 'cache-key',
        projectId: 2,
        fingerprint: '123:abc',
        projectType: 'face',
        modelVersion: 'face-model-v1',
        transformAlgorithmVersion: 'transform-v1',
        settingsHash: 'settings-hash',
        scope: 'auto',
        sourceOrientation: 'flipped',
        selectedFaceIndex: 1,
        faceCount: 2,
        sourceWidth: 4000,
        sourceHeight: 3000,
        canvasWidth: 1920,
        canvasHeight: 1080,
        translateX: 12.5,
        translateY: -4.25,
        rotationDegrees: 1.5,
        scaleFactor: 1.2,
        finalScore: 0.98,
        finalEyeDeltaY: 0.1,
        finalEyeDistance: 300.0,
        goalEyeDistance: 320.0,
        preScore: 0.5,
        rotationPassScore: 0.7,
        scalePassScore: 0.8,
        translationPassScore: 0.9,
        isEstimated: false,
        exampleTimestamp: '1700000000000',
        createdAt: 100,
        updatedAt: 200,
      );

      final map = entry.toMap(includeId: true);
      final roundTrip = TransformCacheEntry.fromMap(map);

      expect(roundTrip.id, 10);
      expect(roundTrip.cacheKey, 'cache-key');
      expect(roundTrip.projectId, 2);
      expect(roundTrip.sourceOrientation, 'flipped');
      expect(roundTrip.selectedFaceIndex, 1);
      expect(roundTrip.translateX, 12.5);
      expect(roundTrip.scaleFactor, 1.2);
      expect(roundTrip.finalScore, 0.98);
      expect(roundTrip.isEstimated, isFalse);
    });

    test('table name is TransformCache', () {
      expect(DB.transformCacheTable, 'TransformCache');
    });
  });
}
