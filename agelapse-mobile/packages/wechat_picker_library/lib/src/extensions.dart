// Copyright 2023 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';

/// Common extensions for the [BuildContext].
extension BuildContextExtension on BuildContext {
  /// [Theme.of].
  ThemeData get theme => Theme.of(this);

  /// [IconTheme.of].
  IconThemeData get iconTheme => IconTheme.of(this);

  /// [ThemeData.textTheme].
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// [MediaQueryData.padding].top
  double get topPadding => MediaQuery.paddingOf(this).top;

  /// [MediaQueryData.padding].bottom
  double get bottomPadding => MediaQuery.paddingOf(this).bottom;

  /// [MediaQueryData.viewInsets].bottom
  double get bottomInsets => MediaQuery.viewInsetsOf(this).bottom;
}

/// Common extensions for the [Brightness].
extension BrightnessExtension on Brightness {
  /// [Brightness.dark].
  bool get isDark => this == Brightness.dark;

  /// [Brightness.light].
  bool get isLight => this == Brightness.light;

  /// Get the reversed [Brightness].
  Brightness get reverse =>
      this == Brightness.light ? Brightness.dark : Brightness.light;
}

/// Common extensions for the [Color].
extension ColorExtension on Color {
  /// Determine the transparent color by 0 alpha.
  bool get isTransparent => alpha == 0x00;
}

/// Common extensions for the [ThemeData].
extension ThemeDataExtension on ThemeData {
  /// The effective brightness from the
  /// [SystemUiOverlayStyle.statusBarBrightness]
  /// and [ThemeData.brightness].
  Brightness get effectiveBrightness =>
      appBarTheme.systemOverlayStyle?.statusBarBrightness ?? brightness;
}

/// Common extensions for the [State].
extension SafeSetStateExtension on State {
  /// [setState] after the [fn] is done while the [State] is still [mounted]
  /// and [State.context] is safe to mark needs build.
  FutureOr<void> safeSetState(FutureOr<dynamic> Function() fn) async {
    await fn();
    if (mounted &&
        !context.debugDoingBuild &&
        context.owner?.debugBuilding != true) {
      // ignore: invalid_use_of_protected_member
      setState(() {});
    }
  }
}
