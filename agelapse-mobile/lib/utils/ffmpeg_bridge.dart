import 'dart:io';

typedef LogFn = void Function(String);

class FFmpegBridge {
  static Future<void> init({LogFn? onLog, void Function(int)? onStats}) async {
    if (Platform.isWindows) return;
  }

  static Future<int> encode({
    required String nonWindowsCmd,
    required Future<bool> Function() windowsPath,
    LogFn? onLog,
  }) async {
    if (Platform.isWindows) {
      final ok = await windowsPath();
      return ok ? 0 : 1;
    } else {
      return 0;
    }
  }
}
