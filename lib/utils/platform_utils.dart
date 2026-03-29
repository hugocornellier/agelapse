import 'dart:io';

/// Whether the platform uses a custom Flutter-rendered title bar.
bool get hasCustomTitleBar =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;
