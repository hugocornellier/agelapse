import 'dart:math' as math;

import 'package:agelapse/utils/manual_transform_reprojection.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stabilizer's transform, as StabUtils builds it for warpAffine and as
/// FaceStabilizer.transformPointByCanvasSize derives the translation: rotate
/// about the image centre, scale, land the image centre at the canvas centre
/// plus the translation. Used here to check the re-projection against the
/// geometry rather than against itself.
({double x, double y}) _map(
  ({double x, double y}) raw,
  ManualTransform t, {
  required int canvasWidth,
  required int canvasHeight,
  required int rawWidth,
  required int rawHeight,
}) {
  final a = t.rotationDegrees * math.pi / 180;
  final dx = raw.x - rawWidth / 2;
  final dy = raw.y - rawHeight / 2;
  return (
    x:
        t.scaleFactor * (dx * math.cos(a) - dy * math.sin(a)) +
        canvasWidth / 2 +
        t.translateX,
    y:
        t.scaleFactor * (dx * math.sin(a) + dy * math.cos(a)) +
        canvasHeight / 2 +
        t.translateY,
  );
}

/// What the automatic pass computes from two eye points: level the eyes,
/// scale their spacing to the goal, land the left eye on its goal.
ManualTransform _auto(
  ({double x, double y}) left,
  ({double x, double y}) right, {
  required int canvasWidth,
  required int canvasHeight,
  required double eyeOffsetX,
  required double eyeOffsetY,
  required int rawWidth,
  required int rawHeight,
}) {
  final dx = (right.x - left.x).abs();
  final dy = (right.y - left.y).abs();
  final rot = math.atan2(dy, dx) * 180 / math.pi * (right.y > left.y ? -1 : 1);
  final scale = 2 * eyeOffsetX * canvasWidth / math.sqrt(dx * dx + dy * dy);
  final landed = _map(
    left,
    (rotationDegrees: rot, scaleFactor: scale, translateX: 0, translateY: 0),
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    rawWidth: rawWidth,
    rawHeight: rawHeight,
  );
  return (
    rotationDegrees: rot,
    scaleFactor: scale,
    translateX: canvasWidth / 2 - eyeOffsetX * canvasWidth - landed.x,
    translateY: eyeOffsetY * canvasHeight - landed.y,
  );
}

void _expectTransform(
  ManualTransform? actual,
  ManualTransform expected, {
  double tolerance = 1e-9,
}) {
  expect(actual, isNotNull);
  expect(actual!.rotationDegrees, closeTo(expected.rotationDegrees, tolerance));
  expect(actual.scaleFactor, closeTo(expected.scaleFactor, tolerance));
  expect(actual.translateX, closeTo(expected.translateX, tolerance));
  expect(actual.translateY, closeTo(expected.translateY, tolerance));
}

void main() {
  const rawWidth = 3024;
  const rawHeight = 4032;
  // Detected eyes in the raw photo; the right one sits 30 px lower.
  const left = (x: 1400.0, y: 1500.0);
  const right = (x: 1700.0, y: 1530.0);

  // Portrait 1080x1920 at the settings the edit is saved under.
  const savedWidth = 1080;
  const savedHeight = 1920;
  const savedOffsetX = 0.10;
  const savedOffsetY = 0.40;

  final auto = _auto(
    left,
    right,
    canvasWidth: savedWidth,
    canvasHeight: savedHeight,
    eyeOffsetX: savedOffsetX,
    eyeOffsetY: savedOffsetY,
    rawWidth: rawWidth,
    rawHeight: rawHeight,
  );
  // The user's edit on top of the automatic result: 10 px down, 2 degrees
  // more tilt, 5% larger.
  final edit = (
    rotationDegrees: auto.rotationDegrees + 2.0,
    scaleFactor: auto.scaleFactor * 1.05,
    translateX: auto.translateX,
    translateY: auto.translateY + 10.0,
  );

  ManualTransform? reproject(
    ManualTransform saved, {
    required int canvasWidth,
    required int canvasHeight,
    required double eyeOffsetX,
    required double eyeOffsetY,
  }) {
    return ManualTransformReprojection.reproject(
      rotationDegrees: saved.rotationDegrees,
      scaleFactor: saved.scaleFactor,
      translateX: saved.translateX,
      translateY: saved.translateY,
      savedCanvasWidth: savedWidth,
      savedCanvasHeight: savedHeight,
      savedEyeOffsetX: savedOffsetX,
      savedEyeOffsetY: savedOffsetY,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      eyeOffsetX: eyeOffsetX,
      eyeOffsetY: eyeOffsetY,
    );
  }

  group('ManualTransformReprojection', () {
    test('unchanged settings return the saved values untouched', () {
      final result = reproject(
        edit,
        canvasWidth: savedWidth,
        canvasHeight: savedHeight,
        eyeOffsetX: savedOffsetX,
        eyeOffsetY: savedOffsetY,
      );
      expect(result, equals(edit));
    });

    test('a pure resolution change is a proportional rescale', () {
      // What the cache did for manual rows before re-projection existed.
      final result = reproject(
        edit,
        canvasWidth: savedWidth * 2,
        canvasHeight: savedHeight * 2,
        eyeOffsetX: savedOffsetX,
        eyeOffsetY: savedOffsetY,
      );
      _expectTransform(result, (
        rotationDegrees: edit.rotationDegrees,
        scaleFactor: edit.scaleFactor * 2,
        translateX: edit.translateX * 2,
        translateY: edit.translateY * 2,
      ));
    });

    test('an eye position change keeps the tilt, the size ratio to the '
        'automatic result, and the offset measured in raw pixels', () {
      const width = 2160;
      const height = 3840;
      const offsetX = 0.125;
      const offsetY = 0.40;
      final result = reproject(
        edit,
        canvasWidth: width,
        canvasHeight: height,
        eyeOffsetX: offsetX,
        eyeOffsetY: offsetY,
      )!;
      final autoNow = _auto(
        left,
        right,
        canvasWidth: width,
        canvasHeight: height,
        eyeOffsetX: offsetX,
        eyeOffsetY: offsetY,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
      );
      // Goal eye spacing went from 0.10 * 1080 to 0.125 * 2160: 2.5x.
      const f = 2.5;
      expect(
        result.rotationDegrees,
        closeTo(autoNow.rotationDegrees + 2.0, 1e-9),
      );
      expect(result.scaleFactor / autoNow.scaleFactor, closeTo(1.05, 1e-9));

      // Where the real left eye lands relative to its goal, before and
      // after: the same vector in raw pixels, so f times larger on canvas.
      final before = _map(
        left,
        edit,
        canvasWidth: savedWidth,
        canvasHeight: savedHeight,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
      );
      final after = _map(
        left,
        result,
        canvasWidth: width,
        canvasHeight: height,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
      );
      final beforeDx = before.x - (savedWidth / 2 - savedOffsetX * savedWidth);
      final beforeDy = before.y - savedOffsetY * savedHeight;
      final afterDx = after.x - (width / 2 - offsetX * width);
      final afterDy = after.y - offsetY * height;
      expect(afterDx, closeTo(beforeDx * f, 1e-6));
      expect(afterDy, closeTo(beforeDy * f, 1e-6));
    });

    test(
      'a 10 px nudge becomes 25 px when the goal eye spacing grows 2.5x',
      () {
        final nudge = (
          rotationDegrees: auto.rotationDegrees,
          scaleFactor: auto.scaleFactor,
          translateX: auto.translateX,
          translateY: auto.translateY + 10.0,
        );
        final result = reproject(
          nudge,
          canvasWidth: 2160,
          canvasHeight: 3840,
          eyeOffsetX: 0.125,
          eyeOffsetY: 0.40,
        )!;
        final landed = _map(
          left,
          result,
          canvasWidth: 2160,
          canvasHeight: 3840,
          rawWidth: rawWidth,
          rawHeight: rawHeight,
        );
        expect(landed.y - 0.40 * 3840, closeTo(25.0, 1e-6));
        expect(landed.x - (2160 / 2 - 0.125 * 2160), closeTo(0.0, 1e-6));
      },
    );

    test('aspect ratio, orientation and non-proportional canvas changes land '
        'the virtual eyes on the new goals', () {
      final cases = <({int w, int h, double ox, double oy})>[
        (w: 1080, h: 1080, ox: 0.10, oy: 0.45), // 9:16 -> 1:1, eyes lower
        (w: 1920, h: 1080, ox: 0.035, oy: 0.421875), // portrait -> landscape
        (w: 1500, h: 2000, ox: 0.10, oy: 0.40), // custom, width != height ratio
      ];
      for (final c in cases) {
        final result = reproject(
          edit,
          canvasWidth: c.w,
          canvasHeight: c.h,
          eyeOffsetX: c.ox,
          eyeOffsetY: c.oy,
        )!;
        final autoNow = _auto(
          left,
          right,
          canvasWidth: c.w,
          canvasHeight: c.h,
          eyeOffsetX: c.ox,
          eyeOffsetY: c.oy,
          rawWidth: rawWidth,
          rawHeight: rawHeight,
        );
        expect(
          result.rotationDegrees,
          closeTo(autoNow.rotationDegrees + 2.0, 1e-9),
          reason: 'tilt for $c',
        );
        expect(
          result.scaleFactor / autoNow.scaleFactor,
          closeTo(1.05, 1e-9),
          reason: 'size ratio for $c',
        );
        // The virtual eyes are where the eyes would have to be for the
        // automatic pass to produce the saved edit. Re-projected, they
        // must sit exactly on the new goals.
        final virtualLeft = _invert(
          (
            x: savedWidth / 2 - savedOffsetX * savedWidth,
            y: savedOffsetY * savedHeight,
          ),
          edit,
          canvasWidth: savedWidth,
          canvasHeight: savedHeight,
          rawWidth: rawWidth,
          rawHeight: rawHeight,
        );
        final landed = _map(
          virtualLeft,
          result,
          canvasWidth: c.w,
          canvasHeight: c.h,
          rawWidth: rawWidth,
          rawHeight: rawHeight,
        );
        expect(
          landed.x,
          closeTo(c.w / 2 - c.ox * c.w, 1e-6),
          reason: 'x for $c',
        );
        expect(landed.y, closeTo(c.oy * c.h, 1e-6), reason: 'y for $c');
      }
    });

    test('works without any detected eyes', () {
      // A photo the automatic pass failed on, placed entirely by hand.
      const hand = (
        rotationDegrees: -3.0,
        scaleFactor: 0.5,
        translateX: 40.0,
        translateY: -120.0,
      );
      final there = reproject(
        hand,
        canvasWidth: 2160,
        canvasHeight: 3840,
        eyeOffsetX: 0.125,
        eyeOffsetY: 0.40,
      )!;
      // Re-projecting back is the identity.
      final back = ManualTransformReprojection.reproject(
        rotationDegrees: there.rotationDegrees,
        scaleFactor: there.scaleFactor,
        translateX: there.translateX,
        translateY: there.translateY,
        savedCanvasWidth: 2160,
        savedCanvasHeight: 3840,
        savedEyeOffsetX: 0.125,
        savedEyeOffsetY: 0.40,
        canvasWidth: savedWidth,
        canvasHeight: savedHeight,
        eyeOffsetX: savedOffsetX,
        eyeOffsetY: savedOffsetY,
      );
      _expectTransform(back, hand);
    });

    test('refuses a zero eye offset X on either side', () {
      expect(
        reproject(
          edit,
          canvasWidth: savedWidth,
          canvasHeight: savedHeight,
          eyeOffsetX: 0.0,
          eyeOffsetY: savedOffsetY,
        ),
        isNull,
      );
      expect(
        ManualTransformReprojection.reproject(
          rotationDegrees: 0,
          scaleFactor: 1,
          translateX: 0,
          translateY: 0,
          savedCanvasWidth: savedWidth,
          savedCanvasHeight: savedHeight,
          savedEyeOffsetX: 0.0,
          savedEyeOffsetY: savedOffsetY,
          canvasWidth: savedWidth,
          canvasHeight: savedHeight,
          eyeOffsetX: 0.1,
          eyeOffsetY: savedOffsetY,
        ),
        isNull,
      );
    });

    test('refuses a missing canvas size', () {
      expect(
        ManualTransformReprojection.reproject(
          rotationDegrees: 0,
          scaleFactor: 1,
          translateX: 0,
          translateY: 0,
          savedCanvasWidth: 0,
          savedCanvasHeight: 0,
          savedEyeOffsetX: 0.1,
          savedEyeOffsetY: 0.4,
          canvasWidth: savedWidth,
          canvasHeight: savedHeight,
          eyeOffsetX: 0.1,
          eyeOffsetY: 0.4,
        ),
        isNull,
      );
    });
  });
}

/// Inverse of [_map]: the raw point that lands on [canvas].
({double x, double y}) _invert(
  ({double x, double y}) canvas,
  ManualTransform t, {
  required int canvasWidth,
  required int canvasHeight,
  required int rawWidth,
  required int rawHeight,
}) {
  final a = -t.rotationDegrees * math.pi / 180;
  final vx = (canvas.x - canvasWidth / 2 - t.translateX) / t.scaleFactor;
  final vy = (canvas.y - canvasHeight / 2 - t.translateY) / t.scaleFactor;
  return (
    x: rawWidth / 2 + vx * math.cos(a) - vy * math.sin(a),
    y: rawHeight / 2 + vx * math.sin(a) + vy * math.cos(a),
  );
}
