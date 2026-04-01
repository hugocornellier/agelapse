import 'dart:io';

/// Whether the current platform is a mobile platform (Android or iOS).
bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// Whether the current platform is an Apple platform (macOS or iOS).
bool get isApple => Platform.isMacOS || Platform.isIOS;

/// Whether the current platform is a desktop platform (macOS, Windows, or Linux).
bool get isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Whether the platform uses a custom Flutter-rendered title bar.
bool get hasCustomTitleBar =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;
