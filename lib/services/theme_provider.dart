import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/theme.dart';

class ThemeProvider extends ChangeNotifier {
  String _themeMode;
  final MaterialTheme _materialTheme;

  ThemeProvider(this._themeMode, this._materialTheme);

  String get themeMode => _themeMode;

  set themeMode(String value) {
    _themeMode = value;
    notifyListeners();
  }

  bool get isLightMode {
    if (_themeMode == 'system') {
      var brightness =
          SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.light;
    }
    return _themeMode == 'light';
  }

  ThemeData get themeData {
    return isLightMode ? _materialTheme.light() : _materialTheme.dark();
  }

  static String? getActiveTheme(String themeMode) {
    return themeMode;
  }
}
