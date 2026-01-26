import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../styles/app_colors_data.dart';
import '../theme/theme.dart';

/// Provides theme state and responds to system brightness changes.
class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  String _themeMode;
  final MaterialTheme _materialTheme;

  ThemeProvider(this._themeMode, this._materialTheme) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Notify listeners when system brightness changes (if in system mode)
    if (_themeMode == 'system') {
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Linux, D-Bus notifications may not work reliably.
    // Refresh theme when app resumes to catch any system theme changes.
    if (Platform.isLinux && state == AppLifecycleState.resumed) {
      if (_themeMode == 'system') {
        notifyListeners();
      }
    }
  }

  String get themeMode => _themeMode;

  set themeMode(String value) {
    if (_themeMode != value) {
      _themeMode = value;
      notifyListeners();
    }
  }

  bool get isLightMode {
    if (_themeMode == 'system') {
      final brightness =
          SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.light;
    }
    return _themeMode == 'light';
  }

  /// Returns the Flutter ThemeMode enum for MaterialApp.
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Returns the current AppColorsData based on resolved brightness.
  AppColorsData get currentColors {
    return isLightMode ? AppColorsData.light() : AppColorsData.dark();
  }

  /// Light theme with AppColorsData extension.
  ThemeData get lightTheme {
    return _materialTheme.light().copyWith(
      extensions: [AppColorsData.light()],
      // Align colorScheme.primary with AppColors.accent
      colorScheme: _materialTheme.light().colorScheme.copyWith(
            primary: AppColorsData.light().accent,
          ),
    );
  }

  /// Dark theme with AppColorsData extension.
  ThemeData get darkTheme {
    return _materialTheme.dark().copyWith(
      extensions: [AppColorsData.dark()],
      colorScheme: _materialTheme.dark().colorScheme.copyWith(
            primary: AppColorsData.dark().accent,
          ),
    );
  }

  /// Returns the current ThemeData based on resolved theme mode.
  ThemeData get themeData {
    return isLightMode ? lightTheme : darkTheme;
  }

  static String? getActiveTheme(String themeMode) {
    return themeMode;
  }
}
