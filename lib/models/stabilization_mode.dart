/// Stabilization algorithm mode.
///
/// - [fast]: Translation-only multi-pass correction (up to 4 passes).
///   Faster but may not correct rotation/scale errors.
/// - [slow]: Full affine refinement with rotation, scale, and translation
///   passes (up to 10 passes). More thorough but slower.
enum StabilizationMode {
  fast,
  slow;

  /// Parse from string, defaults to [fast] if invalid.
  static StabilizationMode fromString(String value) {
    return StabilizationMode.values.firstWhere(
      (mode) => mode.name == value.toLowerCase(),
      orElse: () => StabilizationMode.fast,
    );
  }
}
