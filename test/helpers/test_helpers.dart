import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:agelapse/services/stabilization_progress.dart';
import 'package:agelapse/services/stabilization_state.dart';

/// Registers fallback values for Mocktail.
/// Call this in setUpAll() before using any mocks.
void registerFallbackValues() {
  registerFallbackValue(StabilizationProgress.idle());
  registerFallbackValue(StabilizationState.idle);
}

/// Wraps a widget with MaterialApp for testing.
Widget createTestableWidget(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

/// Wraps a widget with MaterialApp and a custom theme for testing.
Widget createTestableWidgetWithTheme(Widget child, {bool isDark = false}) {
  return MaterialApp(
    theme: isDark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(body: child),
  );
}

/// Creates a mock SettingsCache-like map with default values.
/// This is useful for testing widgets that depend on settings.
Map<String, dynamic> createMockSettingsMap({
  bool hasOpenedNonEmptyGallery = false,
  bool isLightTheme = false,
  bool noPhotos = true,
  int streak = 0,
  int photoCount = 0,
  String projectOrientation = 'portrait',
  String aspectRatio = '16:9',
  String resolution = '1080p',
  bool watermarkEnabled = false,
  String stabilizationMode = 'slow',
  double eyeOffsetX = 0.065,
  double eyeOffsetY = 0.421875,
}) {
  return {
    'hasOpenedNonEmptyGallery': hasOpenedNonEmptyGallery,
    'isLightTheme': isLightTheme,
    'noPhotos': noPhotos,
    'streak': streak,
    'photoCount': photoCount,
    'projectOrientation': projectOrientation,
    'aspectRatio': aspectRatio,
    'resolution': resolution,
    'watermarkEnabled': watermarkEnabled,
    'stabilizationMode': stabilizationMode,
    'eyeOffsetX': eyeOffsetX,
    'eyeOffsetY': eyeOffsetY,
  };
}

/// A test utility that waits for a condition to be true.
Future<void> waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException(
        'Condition not met within ${timeout.inSeconds} seconds',
      );
    }
    await Future.delayed(pollInterval);
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}
