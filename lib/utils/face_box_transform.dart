import 'dart:math' as math;
import 'dart:ui';

/// Pure geometry for mapping face bounding boxes between the detector's
/// successful-orientation space and the original (raw) image space.
///
/// The face-detection cache (`FaceDetectionCache`) stores each box in the
/// coordinate space of whichever orientation succeeded during detection:
///
///   * `original` — no transform.
///   * `flipped`  — `cv.flip(mat, 1)`, a horizontal mirror; dimensions unchanged.
///   * `cw`       — `cv.rotate(mat, ROTATE_90_CLOCKWISE)`; oriented image is H×W.
///   * `ccw`      — `cv.rotate(mat, ROTATE_90_COUNTERCLOCKWISE)`; oriented image is H×W.
///
/// To crop a face out of the *raw* image we must invert that transform.
///
/// Inverse mapping for an original image of width `W`, height `H`, and a cached
/// box `(l, t, r, b)` in oriented space (verified from cv.flip/cv.rotate
/// semantics — `ROTATE_90_CLOCKWISE` = transpose + horizontal flip):
///
///   original : (l,      t,     r,      b)
///   flipped  : (W - r,  t,     W - l,  b)
///   cw       : (t,      H - r, b,      H - l)
///   ccw      : (W - b,  l,     W - t,  r)
///
/// The `no_faces` sentinel is not a geometric orientation; callers must handle
/// it before reaching here.
class FaceBoxTransform {
  const FaceBoxTransform._();

  /// Geometric orientations this transformer understands. Excludes the
  /// `no_faces` sentinel, which is not a coordinate space.
  static const Set<String> supportedOrientations = {
    'original',
    'flipped',
    'cw',
    'ccw',
  };

  static bool isSupportedOrientation(String orientation) =>
      supportedOrientations.contains(orientation);

  /// True if every edge of [box] is finite and it has positive area.
  static bool isValidBox(Rect box) {
    return box.left.isFinite &&
        box.top.isFinite &&
        box.right.isFinite &&
        box.bottom.isFinite &&
        box.right > box.left &&
        box.bottom > box.top;
  }

  /// Maps [orientedBox] (expressed in the coordinate space named by
  /// [orientation]) back to the original raw image of size
  /// [originalWidth] × [originalHeight].
  ///
  /// Throws [ArgumentError] for an unsupported orientation or non-positive
  /// dimensions. The returned rect is always well-formed (left < right,
  /// top < bottom) for a well-formed input box.
  static Rect toOriginalSpace(
    Rect orientedBox,
    String orientation,
    int originalWidth,
    int originalHeight,
  ) {
    if (originalWidth <= 0 || originalHeight <= 0) {
      throw ArgumentError(
        'originalWidth/Height must be positive '
        '($originalWidth x $originalHeight)',
      );
    }
    final double w = originalWidth.toDouble();
    final double h = originalHeight.toDouble();
    final double l = orientedBox.left;
    final double t = orientedBox.top;
    final double r = orientedBox.right;
    final double b = orientedBox.bottom;

    switch (orientation) {
      case 'original':
        return orientedBox;
      case 'flipped':
        return Rect.fromLTRB(w - r, t, w - l, b);
      case 'cw':
        return Rect.fromLTRB(t, h - r, b, h - l);
      case 'ccw':
        return Rect.fromLTRB(w - b, l, w - t, r);
      default:
        throw ArgumentError('Unsupported orientation: $orientation');
    }
  }

  /// Expands [box] by [paddingFraction] of its width/height on each side, then
  /// clamps to `[0, width] × [0, height]` and snaps to integer pixel edges
  /// (left/top floored, right/bottom ceiled for a safe inclusive crop).
  ///
  /// Returns `null` when the box is non-finite, the image dimensions are
  /// non-positive, or the clamped result is smaller than [minSize] on either
  /// axis (degenerate or off-image). Input edges may be unordered; they are
  /// normalized first.
  static Rect? padClampToInt(
    Rect box,
    int width,
    int height, {
    double paddingFraction = 0.15,
    int minSize = 2,
  }) {
    if (width <= 0 || height <= 0) return null;
    if (!box.left.isFinite ||
        !box.top.isFinite ||
        !box.right.isFinite ||
        !box.bottom.isFinite) {
      return null;
    }

    final double w = width.toDouble();
    final double h = height.toDouble();

    // Normalize potentially-unordered edges.
    final double left0 = math.min(box.left, box.right);
    final double right0 = math.max(box.left, box.right);
    final double top0 = math.min(box.top, box.bottom);
    final double bottom0 = math.max(box.top, box.bottom);

    final double padX = (right0 - left0) * paddingFraction;
    final double padY = (bottom0 - top0) * paddingFraction;

    final double left = math.max(0.0, math.min(left0 - padX, w));
    final double top = math.max(0.0, math.min(top0 - padY, h));
    final double right = math.max(0.0, math.min(right0 + padX, w));
    final double bottom = math.max(0.0, math.min(bottom0 + padY, h));

    final int li = left.floor();
    final int ti = top.floor();
    final int ri = right.ceil();
    final int bi = bottom.ceil();

    if (ri - li < minSize || bi - ti < minSize) return null;

    return Rect.fromLTRB(
      li.toDouble(),
      ti.toDouble(),
      ri.toDouble(),
      bi.toDouble(),
    );
  }

  /// Convenience: inverse-transform [orientedBox] to original space, then pad,
  /// clamp, and snap to integer pixels in one step. Returns `null` if the
  /// orientation is unsupported or the resulting crop is degenerate.
  static Rect? originalSpaceCrop(
    Rect orientedBox,
    String orientation,
    int originalWidth,
    int originalHeight, {
    double paddingFraction = 0.15,
    int minSize = 2,
  }) {
    if (!isSupportedOrientation(orientation)) return null;
    if (originalWidth <= 0 || originalHeight <= 0) return null;
    final Rect original = toOriginalSpace(
      orientedBox,
      orientation,
      originalWidth,
      originalHeight,
    );
    return padClampToInt(
      original,
      originalWidth,
      originalHeight,
      paddingFraction: paddingFraction,
      minSize: minSize,
    );
  }

  /// Like [originalSpaceCrop] but takes raw oriented edges and returns integer
  /// crop bounds `(x, y, width, height)` in original-image pixels, or `null`
  /// when degenerate. Lets isolate/native code crop without constructing a
  /// `dart:ui` [Rect] at the call site.
  static (int x, int y, int w, int h)? originalSpaceCropBounds(
    double left,
    double top,
    double right,
    double bottom,
    String orientation,
    int originalWidth,
    int originalHeight, {
    double paddingFraction = 0.15,
    int minSize = 2,
  }) {
    final crop = originalSpaceCrop(
      Rect.fromLTRB(left, top, right, bottom),
      orientation,
      originalWidth,
      originalHeight,
      paddingFraction: paddingFraction,
      minSize: minSize,
    );
    if (crop == null) return null;
    return (
      crop.left.toInt(),
      crop.top.toInt(),
      (crop.right - crop.left).toInt(),
      (crop.bottom - crop.top).toInt(),
    );
  }
}
