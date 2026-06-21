import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/face_box_transform.dart';

/// Independent forward maps (original -> oriented space), derived separately
/// from the production inverse so a swapped cw/ccw can't pass. Edge convention,
/// original image is W x H.
Rect _forwardFlipped(Rect box, int w, int h) =>
    Rect.fromLTRB(w - box.right, box.top, w - box.left, box.bottom);

Rect _forwardCw(Rect box, int w, int h) =>
    // x' = H - y, y' = x  => oriented (H-b, l, H-t, r)
    Rect.fromLTRB(h - box.bottom, box.left, h - box.top, box.right);

Rect _forwardCcw(Rect box, int w, int h) =>
    // x' = y, y' = W - x  => oriented (t, W-r, b, W-l)
    Rect.fromLTRB(box.top, w - box.right, box.bottom, w - box.left);

void _expectRect(Rect actual, Rect expected, {double tol = 1e-9}) {
  expect(actual.left, closeTo(expected.left, tol), reason: 'left');
  expect(actual.top, closeTo(expected.top, tol), reason: 'top');
  expect(actual.right, closeTo(expected.right, tol), reason: 'right');
  expect(actual.bottom, closeTo(expected.bottom, tol), reason: 'bottom');
}

void main() {
  // Deliberately non-square + off-center so cw and ccw give different results.
  const int w = 1000;
  const int h = 600;
  const Rect box = Rect.fromLTRB(100, 50, 300, 250);

  group('toOriginalSpace — explicit hand-computed values', () {
    test('original is identity', () {
      _expectRect(
        FaceBoxTransform.toOriginalSpace(box, 'original', w, h),
        box,
      );
    });

    test('flipped: (W-r, t, W-l, b)', () {
      _expectRect(
        FaceBoxTransform.toOriginalSpace(box, 'flipped', w, h),
        const Rect.fromLTRB(700, 50, 900, 250),
      );
    });

    test('cw: (t, H-r, b, H-l)', () {
      _expectRect(
        FaceBoxTransform.toOriginalSpace(box, 'cw', w, h),
        const Rect.fromLTRB(50, 300, 250, 500),
      );
    });

    test('ccw: (W-b, l, W-t, r)', () {
      _expectRect(
        FaceBoxTransform.toOriginalSpace(box, 'ccw', w, h),
        const Rect.fromLTRB(750, 100, 950, 300),
      );
    });

    test('cw and ccw differ (guards against swapped formulas)', () {
      final cw = FaceBoxTransform.toOriginalSpace(box, 'cw', w, h);
      final ccw = FaceBoxTransform.toOriginalSpace(box, 'ccw', w, h);
      expect(cw == ccw, isFalse);
    });
  });

  group('round-trip: forward(original) -> toOriginalSpace == original', () {
    final cases = <Rect>[
      const Rect.fromLTRB(100, 50, 300, 250),
      const Rect.fromLTRB(0, 0, 10, 20),
      const Rect.fromLTRB(880, 540, 1000, 600), // touches far corner
      const Rect.fromLTRB(123.5, 7.25, 456.75, 599.5), // fractional
    ];

    for (final original in cases) {
      test('flipped round-trips $original', () {
        final oriented = _forwardFlipped(original, w, h);
        _expectRect(
          FaceBoxTransform.toOriginalSpace(oriented, 'flipped', w, h),
          original,
        );
      });

      test('cw round-trips $original', () {
        final oriented = _forwardCw(original, w, h);
        _expectRect(
          FaceBoxTransform.toOriginalSpace(oriented, 'cw', w, h),
          original,
        );
      });

      test('ccw round-trips $original', () {
        final oriented = _forwardCcw(original, w, h);
        _expectRect(
          FaceBoxTransform.toOriginalSpace(oriented, 'ccw', w, h),
          original,
        );
      });
    }
  });

  group('toOriginalSpace — output is well-formed (left<right, top<bottom)', () {
    for (final o in FaceBoxTransform.supportedOrientations) {
      test('$o yields ordered edges', () {
        final out = FaceBoxTransform.toOriginalSpace(box, o, w, h);
        expect(out.right, greaterThan(out.left));
        expect(out.bottom, greaterThan(out.top));
      });
    }
  });

  group('toOriginalSpace — argument validation', () {
    test('unsupported orientation throws', () {
      expect(
        () => FaceBoxTransform.toOriginalSpace(box, 'no_faces', w, h),
        throwsArgumentError,
      );
      expect(
        () => FaceBoxTransform.toOriginalSpace(box, 'sideways', w, h),
        throwsArgumentError,
      );
    });

    test('non-positive dimensions throw', () {
      expect(
        () => FaceBoxTransform.toOriginalSpace(box, 'original', 0, h),
        throwsArgumentError,
      );
      expect(
        () => FaceBoxTransform.toOriginalSpace(box, 'original', w, -1),
        throwsArgumentError,
      );
    });
  });

  group('padClampToInt', () {
    test('pads by fraction and snaps to integers', () {
      // 200x200 box, 10% padding -> 20px each side -> (80,30,320,270).
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(100, 50, 300, 250),
        1000,
        600,
        paddingFraction: 0.10,
      );
      _expectRect(out!, const Rect.fromLTRB(80, 30, 320, 270));
    });

    test('clamps to image bounds at edges', () {
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(10, 10, 90, 90),
        100,
        100,
        paddingFraction: 0.5, // would overflow both sides
      );
      // left/top clamp to 0, right/bottom clamp to 100.
      _expectRect(out!, const Rect.fromLTRB(0, 0, 100, 100));
    });

    test('floors left/top and ceils right/bottom', () {
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(10.6, 10.6, 20.1, 20.1),
        1000,
        1000,
        paddingFraction: 0.0,
      );
      _expectRect(out!, const Rect.fromLTRB(10, 10, 21, 21));
    });

    test('normalizes unordered edges', () {
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(300, 250, 100, 50), // reversed
        1000,
        600,
        paddingFraction: 0.0,
      );
      _expectRect(out!, const Rect.fromLTRB(100, 50, 300, 250));
    });

    test('rejects sub-minSize result', () {
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(50, 50, 51, 51),
        1000,
        1000,
        paddingFraction: 0.0,
        minSize: 2,
      );
      expect(out, isNull);
    });

    test('rejects off-image box (clamps to zero area)', () {
      final out = FaceBoxTransform.padClampToInt(
        const Rect.fromLTRB(1200, 700, 1300, 800),
        1000,
        600,
        paddingFraction: 0.0,
      );
      expect(out, isNull);
    });

    test('rejects non-finite edges', () {
      expect(
        FaceBoxTransform.padClampToInt(
          Rect.fromLTRB(0, 0, double.infinity, 10),
          100,
          100,
        ),
        isNull,
      );
      expect(
        FaceBoxTransform.padClampToInt(
          Rect.fromLTRB(0, 0, double.nan, 10),
          100,
          100,
        ),
        isNull,
      );
    });

    test('rejects non-positive dimensions', () {
      expect(
        FaceBoxTransform.padClampToInt(box, 0, 100),
        isNull,
      );
    });
  });

  group('originalSpaceCrop (compose inverse + pad/clamp)', () {
    test('maps cw box back and pads/clamps to integer crop', () {
      // cw oriented (50,50,250,250) in a 600x1000 oriented image.
      // inverse cw -> (t, H-r, b, H-l) = (50, 600-250, 250, 600-50)
      //            = (50, 350, 250, 550); +0 padding -> same.
      final out = FaceBoxTransform.originalSpaceCrop(
        const Rect.fromLTRB(50, 50, 250, 250),
        'cw',
        1000,
        600,
        paddingFraction: 0.0,
      );
      _expectRect(out!, const Rect.fromLTRB(50, 350, 250, 550));
    });

    test('unsupported orientation returns null', () {
      expect(
        FaceBoxTransform.originalSpaceCrop(box, 'no_faces', w, h),
        isNull,
      );
    });

    test('non-positive dimensions return null', () {
      expect(
        FaceBoxTransform.originalSpaceCrop(box, 'original', 0, h),
        isNull,
      );
    });
  });

  group('originalSpaceCropBounds (int x,y,w,h for native crop)', () {
    test('cw box -> integer bounds in original space', () {
      // Same as the originalSpaceCrop cw case: oriented (50,50,250,250) in a
      // 1000x600 original -> (50,350,250,550) -> (x50,y350,w200,h200).
      final bounds = FaceBoxTransform.originalSpaceCropBounds(
        50,
        50,
        250,
        250,
        'cw',
        1000,
        600,
        paddingFraction: 0.0,
      );
      expect(bounds, isNotNull);
      expect(bounds!.$1, 50); // x
      expect(bounds.$2, 350); // y
      expect(bounds.$3, 200); // w
      expect(bounds.$4, 200); // h
    });

    test('degenerate / off-image returns null', () {
      expect(
        FaceBoxTransform.originalSpaceCropBounds(
          1200,
          700,
          1300,
          800,
          'original',
          1000,
          600,
        ),
        isNull,
      );
    });

    test('bounds stay within the image (in-bounds invariant for region())', () {
      final bounds = FaceBoxTransform.originalSpaceCropBounds(
        10,
        10,
        990,
        590,
        'original',
        1000,
        600,
        paddingFraction: 0.5, // would overflow, must clamp
      );
      expect(bounds, isNotNull);
      final (x, y, w, h) = bounds!;
      expect(x, greaterThanOrEqualTo(0));
      expect(y, greaterThanOrEqualTo(0));
      expect(x + w, lessThanOrEqualTo(1000));
      expect(y + h, lessThanOrEqualTo(600));
    });
  });

  group('isValidBox', () {
    test('accepts well-formed', () {
      expect(FaceBoxTransform.isValidBox(box), isTrue);
    });
    test('rejects zero/negative area', () {
      expect(
        FaceBoxTransform.isValidBox(const Rect.fromLTRB(10, 10, 10, 20)),
        isFalse,
      );
      expect(
        FaceBoxTransform.isValidBox(const Rect.fromLTRB(30, 10, 10, 20)),
        isFalse,
      );
    });
    test('rejects non-finite', () {
      expect(
        FaceBoxTransform.isValidBox(Rect.fromLTRB(0, 0, double.infinity, 5)),
        isFalse,
      );
    });
  });
}
