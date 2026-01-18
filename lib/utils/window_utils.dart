import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import '../constants/window_constants.dart';

/// Utility class for desktop window management.
/// All methods are no-ops on mobile platforms.
class WindowUtils {
  /// Returns true if running on a desktop platform with window management.
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Transitions window from welcome state to default state.
  ///
  /// This should be called after the user completes onboarding
  /// (creates their first project). It:
  /// - Updates minimum size constraints
  /// - Resizes window to standard default size
  ///
  /// No-op if:
  /// - Running on mobile platform
  /// - Window is maximized or fullscreen
  static Future<void> transitionToDefaultWindowState() async {
    if (!isDesktop) return;

    // Don't resize if user has maximized or fullscreened the window
    final isMaximized = await windowManager.isMaximized();
    final isFullScreen = await windowManager.isFullScreen();
    if (isMaximized || isFullScreen) return;

    // Update minimum size first (must be <= new size)
    await windowManager.setMinimumSize(kWindowMinSizeDefault);

    // Resize to default
    await windowManager.setSize(kWindowSizeDefault);
  }
}
