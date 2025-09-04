import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class FfmpegWin {
  static Future<String> getFfmpegPath() async {
    try {
      final which = await Process.run('where', ['ffmpeg'], runInShell: true);
      if (which.exitCode == 0) {
        final out = (which.stdout as String).trim().split(RegExp(r'\r?\n')).first;
        if (out.isNotEmpty && await File(out).exists()) return out;
      }
    } catch (_) {}

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, 'ffmpeg', 'ffmpeg.exe'),
      p.join(exeDir, 'assets', 'ffmpeg_win', 'ffmpeg.exe'),
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }

    return 'ffmpeg';
  }

  static Future<String> buildConcatList({
    required String imageDir,
    required int framerate,
  }) async {
    final dir = Directory(imageDir);
    if (!await dir.exists()) {
      throw FileSystemException('image directory not found', imageDir);
    }
    final entries = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    entries.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    if (entries.isEmpty) {
      throw StateError('no .png files found in $imageDir');
    }

    final tmp = await File.fromUri(
      Uri.file(p.join(Directory.systemTemp.path, 'ffconcat_${DateTime.now().millisecondsSinceEpoch}.txt')),
    ).create();

    final perFrame = (1.0 / framerate);
    final buf = StringBuffer();
    for (final fp in entries) {
      final normalized = fp.replaceAll('\\', '/');
      final escaped = normalized.replaceAll("'", r"'\''");
      buf.writeln("file '$escaped'");
      buf.writeln('duration $perFrame');
    }
    buf.writeln('duration $perFrame');

    await tmp.writeAsString(buf.toString(), flush: true);
    return tmp.path;
  }

  static Future<int> encodeFromDir({
    required String imageDir,
    required String outputPath,
    required int framerate,
    void Function(String line)? onLog,
  }) async {
    final ffmpeg = await getFfmpegPath();
    final listPath = await buildConcatList(imageDir: imageDir, framerate: framerate);

    final args = <String>[
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listPath,
      '-vsync', 'cfr',
      '-r', '$framerate',
      '-pix_fmt', 'yuv420p',
      '-c:v', 'libx264',
      '-profile:v', 'main',
      '-level', '4.1',
      '-movflags', '+faststart',
      outputPath,
    ];

    final proc = await Process.start(ffmpeg, args, runInShell: true);
    proc.stdout.transform(utf8.decoder).listen((s) => onLog?.call(s));
    proc.stderr.transform(utf8.decoder).listen((s) => onLog?.call(s));

    final code = await proc.exitCode;
    try { await File(listPath).delete(); } catch (_) {}
    return code;
  }
}
