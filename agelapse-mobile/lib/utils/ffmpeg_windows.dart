import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ffmpeg_runner.dart';

class FfmpegWindows {
  static const _assetPath = 'assets/ffmpeg/windows/ffmpeg.exe';
  static const _markerName = 'ffmpeg.version';

  static Future<String> ensureFfmpegAvailable() async {
    print("ensureFfmpegAvailable called...");

    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(p.join(dir.path, 'bin'));
    if (!await binDir.exists()) await binDir.create(recursive: true);

    final exePath = p.join(binDir.path, 'ffmpeg.exe');
    final markerPath = p.join(binDir.path, _markerName);

    final needsWrite = !(await File(exePath).exists()) || !(await File(markerPath).exists());
    if (needsWrite) {
      final bytes = await rootBundle.load(_assetPath);
      await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await File(markerPath).writeAsString('1');
    }
    return exePath;
  }
}

Future<bool> encodeTimelapseWindows({
  required String inputPattern,
  required String outputPath,
  int fps = 30,
}) async {
  print("encodeTimelapseWindows called...");

  final exe = await FfmpegWindows.ensureFfmpegAvailable();

  final outDir = Directory(p.dirname(outputPath));
  if (!await outDir.exists()) {
    await outDir.create(recursive: true);
  }

  final listPath = await _buildConcatListFromPattern(inputPattern, fps);

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

  print("encodeTimelapseWindows step 2/2...");

  try {
    final code = await FfmpegRunner.run(exe, args, onStderr: (line) {
      print(line);
    });
    try {
      await File(listPath).delete();
    } catch (_) {}
    return code == 0;
  } catch (e) {
    print("Error caught during windows ffmpeg run");
    print(e);
    try {
      await File(listPath).delete();
    } catch (_) {}
    return false;
  }
}

Future<String> _buildConcatListFromPattern(String inputPattern, int fps) async {
  final normalized = inputPattern.replaceAll(r'\', '/');
  final dirPath = normalized.contains('*') ? p.dirname(normalized) : normalized;
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    throw FileSystemException('image directory not found', dirPath);
  }

  final files = await dir
      .list()
      .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
      .map((e) => e.path)
      .toList();

  files.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
  if (files.isEmpty) {
    throw StateError('no .png files found in $dirPath');
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

