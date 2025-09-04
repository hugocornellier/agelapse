import 'dart:convert';
import 'dart:io';

class FfmpegRunner {
  static Future<int> run(String exePath, List<String> args, {
    void Function(String line)? onStderr,
    void Function(String line)? onStdout,
  }) async {
    final proc = await Process.start(exePath, args, runInShell: false);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (onStdout != null) onStdout(line);
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (onStderr != null) onStderr(line);
    });
    return await proc.exitCode;
  }
}
