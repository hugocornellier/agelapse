// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Default theme color from WeChat.
const Color defaultThemeColorWeChat = Color(0xff00bc56);

/// Rounded border radius.
const BorderRadius maxBorderRadius = BorderRadius.all(Radius.circular(9999999));

/// {@template wechat_picker_library.themeData}
/// Build a [ThemeData] with the given [themeColor] for the picker.
/// 为选择器构建基于 [themeColor] 的 [ThemeData]。
///
/// If [themeColor] is null, the color will use the fallback
/// [defaultThemeColorWeChat] which is the default color in the WeChat design.
/// 如果 [themeColor] 为 null，主题色将回落使用 [defaultThemeColorWeChat]，
/// 即微信设计中的绿色主题色。
///
/// Set [light] to true if pickers require a light version of the theme.
/// 设置 [light] 为 true 时可以获取浅色版本的主题。
/// {@endtemplate}
ThemeData buildTheme(Color? themeColor, {bool light = false}) {
  themeColor ??= defaultThemeColorWeChat;
  if (light) {
    return ThemeData.light().copyWith(
      primaryColor: Colors.grey[50],
      primaryColorLight: Colors.grey[50],
      primaryColorDark: Colors.grey[50],
      canvasColor: Colors.grey[100],
      scaffoldBackgroundColor: Colors.grey[50],
      cardColor: Colors.grey[50],
      highlightColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: themeColor,
        selectionColor: themeColor.withAlpha(100),
        selectionHandleColor: themeColor,
      ),
      indicatorColor: themeColor,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[100],
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
        iconTheme: IconThemeData(color: Colors.grey[900]),
        elevation: 0,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: Colors.grey[100],
      ),
      buttonTheme: ButtonThemeData(buttonColor: themeColor),
      iconTheme: IconThemeData(color: Colors.grey[900]),
      checkboxTheme: CheckboxThemeData(
        // ignore: deprecated_member_use
        checkColor: MaterialStateProperty.all(Colors.black),
        // ignore: deprecated_member_use
        fillColor: MaterialStateProperty.resolveWith((states) {
          // ignore: deprecated_member_use
          if (states.contains(MaterialState.selected)) {
            return themeColor;
          }
          return null;
        }),
        side: const BorderSide(color: Colors.black),
      ),
      colorScheme: ColorScheme(
        primary: Colors.grey[50]!,
        secondary: themeColor,
        // ignore: deprecated_member_use
        background: Colors.grey[50]!,
        surface: Colors.grey[50]!,
        brightness: Brightness.light,
        error: const Color(0xffcf6679),
        onPrimary: Colors.white,
        onSecondary: Colors.grey[100]!,
        onSurface: Colors.black,
        // ignore: deprecated_member_use
        onBackground: Colors.black,
        onError: Colors.white,
      ),
    );
  }
  return ThemeData.dark().copyWith(
    primaryColor: Colors.grey[900],
    primaryColorLight: Colors.grey[900],
    primaryColorDark: Colors.grey[900],
    canvasColor: Colors.grey[850],
    scaffoldBackgroundColor: Colors.grey[900],
    cardColor: Colors.grey[900],
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: themeColor,
      selectionColor: themeColor.withAlpha(100),
      selectionHandleColor: themeColor,
    ),
    indicatorColor: themeColor,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[850],
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      elevation: 0,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: Colors.grey[100],
    ),
    buttonTheme: ButtonThemeData(buttonColor: themeColor),
    iconTheme: const IconThemeData(color: Colors.white),
    checkboxTheme: CheckboxThemeData(
      // ignore: deprecated_member_use
      checkColor: MaterialStateProperty.all(Colors.white),
      // ignore: deprecated_member_use
      fillColor: MaterialStateProperty.resolveWith((states) {
        // ignore: deprecated_member_use
        if (states.contains(MaterialState.selected)) {
          return themeColor;
        }
        return null;
      }),
      side: const BorderSide(color: Colors.white),
    ),
    colorScheme: ColorScheme(
      primary: Colors.grey[900]!,
      secondary: themeColor,
      // ignore: deprecated_member_use
      background: Colors.grey[900]!,
      surface: Colors.grey[900]!,
      brightness: Brightness.dark,
      error: const Color(0xffcf6679),
      onPrimary: Colors.black,
      onSecondary: Colors.grey[850]!,
      onSurface: Colors.white,
      // ignore: deprecated_member_use
      onBackground: Colors.white,
      onError: Colors.black,
    ),
  );
}
