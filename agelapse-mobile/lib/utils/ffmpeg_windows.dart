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

  final normalizedInput = inputPattern.replaceAll(r'\', '/');
  final args = <String>[
    '-y',
    if (normalizedInput.contains('*')) ...['-pattern_type', 'glob', '-safe', '0'],
    '-framerate', '$fps',
    '-i', normalizedInput,
    '-vf', 'fps=$fps,format=yuv420p',
    '-c:v', 'libx264',
    '-profile:v', 'main',
    '-level', '4.1',
    '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart',
    outputPath,
  ];

  print("encodeTimelapseWindows step 2/2...");

  try {
    final code = await FfmpegRunner.run(exe, args, onStderr: (line) {
      print(line);
      if (line.contains('time=')) {
        // optional: parse progress
      }
    });

    return code == 0;
  } catch (e) {
    print("Error caught during windows ffmpeg run");
    print(e);

    return false;
  }
}

