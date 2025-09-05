import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FfmpegWindows {
  static const _assetPath = 'assets/ffmpeg/windows/ffmpeg.exe';
  static const _markerName = 'ffmpeg.version';

  static Future<String> _ensureBundled() async {
    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(p.join(dir.path, 'bin'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    final exePath = p.join(binDir.path, 'ffmpeg.exe');
    final markerPath = p.join(binDir.path, _markerName);
    final needsWrite = !(await File(exePath).exists()) || !(await File(markerPath).exists());
    if (needsWrite) {
      final bytes = await rootBundle.load(_assetPath);
      await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await File(markerPath).writeAsString('1', flush: true);
    }
    return exePath;
  }

  static Future<String> _findOnPath() async {
    try {
      final result = await Process.run('where', ['ffmpeg'], runInShell: true);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim().split(RegExp(r'\r?\n')).first;
        if (out.isNotEmpty && await File(out).exists()) {
          return out;
        }
      }
    } catch (_) {}
    return '';
  }

  static Future<String> _resolveFfmpegPath() async {
    try {
      final bundled = await _ensureBundled();
      if (await File(bundled).exists()) return bundled;
    } catch (_) {}
    final onPath = await _findOnPath();
    if (onPath.isNotEmpty) return onPath;
    return 'ffmpeg';
  }

  static Future<void> _ensureOutDir(String outputPath) async {
    final outDir = Directory(p.dirname(outputPath));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
  }

  static Future<String> _buildConcatListFromDir(String framesDir, int fps) async {
    final dir = Directory(framesDir);
    if (!await dir.exists()) {
      throw FileSystemException('image directory not found', framesDir);
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    files.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    if (files.isEmpty) {
      throw StateError('no .png files found in $framesDir');
    }

    final tmpPath = p.join(Directory.systemTemp.path, 'ffconcat_${DateTime.now().millisecondsSinceEpoch}.txt');
    final f = File(tmpPath);
    final perFrame = 1.0 / fps;

    final sb = StringBuffer();
    for (final fp in files) {
      final norm = fp.replaceAll(r'\', '/');
      final esc = norm.replaceAll("'", r"'\''");
      sb.writeln("file '$esc'");
      sb.writeln('duration $perFrame');
    }
    sb.writeln('duration $perFrame');

    await f.writeAsString(sb.toString(), flush: true);
    return tmpPath;
  }

  static Future<bool> encode({
    required String framesDir,
    required String outputPath,
    required int fps,
    void Function(String line)? onLog,
    void Function(int frameIndex)? onProgress,
  }) async {
    final exe = await _resolveFfmpegPath();
    await _ensureOutDir(outputPath);
    final listPath = await _buildConcatListFromDir(framesDir, fps);

    final args = <String>[
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listPath,
      '-vsync', 'cfr',
      '-r', '$fps',
      '-pix_fmt', 'yuv420p',
      '-c:v', 'libx264',
      '-profile:v', 'main',
      '-level', '4.1',
      '-movflags', '+faststart',
      outputPath,
    ];

    final proc = await Process.start(exe, args, runInShell: false);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (onLog != null) onLog(line);
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (onLog != null) onLog(line);
      final m = RegExp(r'frame=\s*(\d+)').firstMatch(line);
      if (m != null && onProgress != null) {
        final f = int.tryParse(m.group(1)!);
        if (f != null) onProgress(f);
      }
    });

    final code = await proc.exitCode;
    try {
      await File(listPath).delete();
    } catch (_) {}
    return code == 0;
  }
}
