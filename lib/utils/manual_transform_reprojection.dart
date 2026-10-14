/// A transform as the stabilizer applies it: rotate about the image centre,
/// scale, and land the image centre at the canvas centre plus the translation.
typedef ManualTransform = ({
  double rotationDegrees,
  double scaleFactor,
  double translateX,
  double translateY,
});

/// Carries a hand-tuned transform from the Manual Stabilization page across a
/// change of eye position, aspect ratio, resolution or custom canvas size.
///
/// The automatic pass derives the four transform values from the two eye
/// points so that the eyes come out level, at the goal spacing
/// (2 * eyeOffsetX * canvasWidth), with the left eye on its goal
/// (canvasWidth / 2 - eyeOffsetX * canvasWidth, eyeOffsetY * canvasHeight).
/// A manual edit is the same four values chosen by hand. Inverting it tells
/// where the eyes would have to be in the raw photo for the automatic pass to
/// produce exactly that framing under the settings it was saved with, and
/// running the automatic pass on those virtual eyes under the new settings
/// gives the carried-over edit. Because every step is a similarity transform
/// this collapses to a closed form with no trigonometry and no raw image size:
///
///   f    = (eyeOffsetX' * canvasWidth') / (eyeOffsetX * canvasWidth)
///   rot' = rot
///   s'   = f * s
///   t'   = (G' - C') - f * (G - C - t)
///
/// where G is the left eye goal, C the canvas centre, t the translation and
/// primed values belong to the new settings. The rotation is unchanged because
/// the eye position never changes how level the eyes are; the scale follows
/// the goal eye spacing; and the vector from the landed image centre to the
/// eye goal scales with the face. A manual offset is therefore measured in
/// raw-photo pixels: a nudge made to fix one photo's alignment keeps its size
/// relative to the face when the framing changes, rather than relative to the
/// frame.
///
/// Under unchanged settings the result is the saved edit exactly. Under a pure
/// resolution change it equals a proportional rescale of the saved values,
/// which is what the transform cache did for manual rows before this existed.
class ManualTransformReprojection {
  ManualTransformReprojection._();

  /// Re-projects a transform saved under the `saved*` settings onto the
  /// current ones. Returns null when that cannot be done: an eye offset X of
  /// zero on either side (the goal eye spacing collapses, which already
  /// yields a blank image on the automatic pass), a missing canvas size, or a
  /// non-finite result.
  static ManualTransform? reproject({
    required double rotationDegrees,
    required double scaleFactor,
    required double translateX,
    required double translateY,
    required int savedCanvasWidth,
    required int savedCanvasHeight,
    required double savedEyeOffsetX,
    required double savedEyeOffsetY,
    required int canvasWidth,
    required int canvasHeight,
    required double eyeOffsetX,
    required double eyeOffsetY,
  }) {
    final saved = (
      rotationDegrees: rotationDegrees,
      scaleFactor: scaleFactor,
      translateX: translateX,
      translateY: translateY,
    );
    if (savedCanvasWidth == canvasWidth &&
        savedCanvasHeight == canvasHeight &&
        savedEyeOffsetX == eyeOffsetX &&
        savedEyeOffsetY == eyeOffsetY) {
      // Same settings: hand back the saved values untouched rather than
      // routing them through arithmetic that could add rounding noise.
      return saved;
    }
    if (savedCanvasWidth <= 0 ||
        savedCanvasHeight <= 0 ||
        canvasWidth <= 0 ||
        canvasHeight <= 0) {
      return null;
    }
    final double savedGoalSpacing = savedEyeOffsetX * savedCanvasWidth;
    final double goalSpacing = eyeOffsetX * canvasWidth;
    if (!(savedGoalSpacing > 0) || !(goalSpacing > 0)) return null;

    final double f = goalSpacing / savedGoalSpacing;

    // Vector from the landed image centre to the left eye goal, under the
    // saved settings. The goal sits eyeOffsetX * width left of the canvas
    // centre and at eyeOffsetY * height from the top.
    final double dx = -savedGoalSpacing - translateX;
    final double dy =
        savedEyeOffsetY * savedCanvasHeight -
        savedCanvasHeight / 2 -
        translateY;

    final double newTranslateX = -goalSpacing - f * dx;
    final double newTranslateY =
        eyeOffsetY * canvasHeight - canvasHeight / 2 - f * dy;
    final double newScale = f * scaleFactor;

    final result = (
      rotationDegrees: rotationDegrees,
      scaleFactor: newScale,
      translateX: newTranslateX,
      translateY: newTranslateY,
    );
    final values = [
      result.rotationDegrees,
      result.scaleFactor,
      result.translateX,
      result.translateY,
    ];
    if (!values.every((v) => v.isFinite)) return null;
    return result;
  }
}
