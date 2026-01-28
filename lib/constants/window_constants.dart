import 'dart:ui' show Size;

/// Window size constants for desktop platforms.
///
/// The app has two window states:
/// - Welcome state: Shown during onboarding when no projects exist
/// - Default state: Normal app usage after at least one project exists

/// Standard window size for normal app usage (has projects)
const Size kWindowSizeDefault = Size(1440, 910);

/// Window size for welcome/onboarding flow (no projects)
const Size kWindowSizeWelcome = Size(840, 820);

/// Minimum window size for normal app usage
const Size kWindowMinSizeDefault = Size(840, 450);

/// Minimum window size during welcome flow (maintains content visibility)
const Size kWindowMinSizeWelcome = Size(840, 820);
