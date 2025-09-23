import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart' as kit;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart' as kitcfg;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart' as kitsession;
import 'package:ffmpeg_kit_flutter_new/log.dart' as kitlog;
import 'package:ffmpeg_kit_flutter_new/return_code.dart' as kitrc;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/settings_utils.dart';
import '../utils/utils.dart';

import '../services/database_helper.dart';
import 'dir_utils.dart';

class VideoUtils {
  static int currentFrame = 1;

  static Future<bool> createTimelapse(
    int projectId,
    framerate,
    totalPhotoCount,
    Function(int currentFrame)? setCurrentFrame
  ) async {
    print("createTimelapse called...");

    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(projectId);
    final String videoOutputPath = await DirUtils.getVideoOutputPath(projectId, projectOrientation);
    await DirUtils.createDirectoryIfNotExists(videoOutputPath);

    final Directory dir = Directory(path.join(stabilizedDirPath, projectOrientation));
    final List<String> pngFiles = dir
        .listSync()
        .where((f) => f.path.endsWith('.png'))
        .map((f) => f.path)
        .toList()
      ..sort();

    final bool framerateIsDefault = await SettingsUtil.loadFramerateIsDefault(projectId.toString());
    if (framerateIsDefault) {
      framerate = await getOptimalFramerateFromStabPhotoCount(projectId);
      DB.instance.setSettingByTitle('framerate', framerate.toString(), projectId.toString());
    }

    if (Platform.isWindows) {
      final String framesDir = path.join(stabilizedDirPath, projectOrientation);
      final bool ok = await _encodeWindows(
        framesDir: framesDir,
        outputPath: videoOutputPath,
        fps: framerate,
        onProgress: setCurrentFrame,
      );
      if (ok) {
        final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
        await DB.instance.addVideo(
          projectId,
          resolution,
          (await SettingsUtil.loadWatermarkSetting(projectId.toString())).toString(),
          (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase(),
          totalPhotoCount,
          framerate,
        );
      }
      return ok;
    }

    final bool watermarkEnabled = await SettingsUtil.loadWatermarkSetting(projectId.toString());
    final String watermarkPos = (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase();
    final String watermarkFilePath = await DirUtils.getWatermarkFilePath(projectId);

    String watermarkInputsAndFilter = "";
    if (watermarkEnabled && Utils.isImage(watermarkFilePath) && await File(watermarkFilePath).exists()) {
      final String watermarkOpacitySettingVal = await DB.instance.getSettingValueByTitle('watermark_opacity');
      final double watermarkOpacity = double.tryParse(watermarkOpacitySettingVal) ?? 0.8;
      final String watermarkFilter = getWatermarkFilter(watermarkOpacity, watermarkPos, 10);
      watermarkInputsAndFilter = "-i \"$watermarkFilePath\" -filter_complex \"$watermarkFilter\"";
    }

    final String framesDir = path.join(stabilizedDirPath, projectOrientation);
    final String listPath = await _buildConcatListFromDir(framesDir, framerate);

    String ffmpegCommand = "-y "
        "-f concat -safe 0 "
        "-i \"$listPath\" "
        "-vsync cfr "
        "-r 30 "
        "$watermarkInputsAndFilter "
        "-c:v libx264 -profile:v main -level 4.1 -movflags +faststart "
        "-pix_fmt yuv420p "
        "\"$videoOutputPath\"";

    try {
      print("2...");
      kitcfg.FFmpegKitConfig.enableLogCallback((kitlog.Log log) {
        final String output = log.getMessage();
        parseFFmpegOutput(output, framerate, setCurrentFrame);

        print(output);
      });

      final kitsession.FFmpegSession session = await kit.FFmpegKit.execute(ffmpegCommand);
      if (kitrc.ReturnCode.isSuccess(await session.getReturnCode())) {
        final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
        await DB.instance.addVideo(projectId, resolution, watermarkEnabled.toString(), watermarkPos, totalPhotoCount, framerate);
        return true;
      } else {
        print("ffmpeg failure");
        return false;
      }
    } catch (e) {
      print(e);

      return false;
    }
  }

  static Future<bool> createTimelapseFromProjectId(
    int projectId,
    Function(int currentFrame)? setCurrentFrame
  ) async {
    try {
      String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
      final List<Map<String, dynamic>> stabilizedPhotos = await DB.instance.getStabilizedPhotosByProjectID(projectId, projectOrientation);
      if (stabilizedPhotos.isEmpty) return false;

      final int framerate = await SettingsUtil.loadFramerate(projectId.toString());

      return await createTimelapse(projectId, framerate, stabilizedPhotos.length, setCurrentFrame);
    } catch (e) {
      return false;
    }
  }

  static Future<int> getOptimalFramerateFromStabPhotoCount(int projectId) async {
    final int stabPhotoCount = await getStabilizedPhotoCount(projectId);
    const List<int> thresholds = [2, 4, 6, 8, 12, 16];
    const List<int> framerates = [2, 3, 4, 6, 8, 10, 14];

    for (int i = 0; i < thresholds.length; i++) {
      if (stabPhotoCount < thresholds[i]) {
        return framerates[i];
      }
    }
    return framerates.last;
  }

  static void parseFFmpegOutput(String output, int framerate, Function(int currentFrame)? setCurrentFrame) {
    final RegExp frameRegex = RegExp(r'frame=\s*(\d+)');
    final match = frameRegex.allMatches(output).isNotEmpty ? frameRegex.allMatches(output).last : null;
    if (match == null || setCurrentFrame == null) return;
    final int videoFrame = int.parse(match.group(1)!);
    final int currFrame = videoFrame ~/ (30 / framerate);
    currentFrame = currFrame;
    setCurrentFrame(currentFrame);
  }

  static Future<int> getStabilizedPhotoCount(int projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    return (await DB.instance.getStabilizedPhotosByProjectID(projectId, projectOrientation)).length;
  }

  static createGif(videoOutputPath, framerate) async {
    if (Platform.isWindows) return;
    final String gifPath = videoOutputPath.replaceAll(path.extension(videoOutputPath), ".gif");
    await kit.FFmpegKit.execute('-i $videoOutputPath $gifPath');
  }

  static Future<bool> videoOutputSettingsChanged(projectId, newestVideo) async {
    if (newestVideo == null) return false;

    final bool newPhotos = newestVideo['photoCount'] != await _getTotalPhotoCountByProjectId(projectId);
    if (newPhotos) {
      return true;
    }

    final framerateSetting = await _getFramerate(projectId);
    final bool framerateChanged = newestVideo['framerate'] != framerateSetting;
    if (framerateChanged) {
      return true;
    }

    final String watermarkEnabled = (await SettingsUtil.loadWatermarkSetting(projectId.toString())).toString();
    if (newestVideo['watermarkEnabled'] != watermarkEnabled) {
      return true;
    }

    final String watermarkPos = (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase();
    if (newestVideo['watermarkPos'] != watermarkPos) {
      return true;
    }

    return false;
  }

  static Future<int> _getTotalPhotoCountByProjectId(int projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    List<Map<String, dynamic>> allStabilizedPhotos = await DB.instance.getStabilizedPhotosByProjectID(projectId, projectOrientation);
    return allStabilizedPhotos.length;
  }

  static Future<int> _getFramerate(projectId) async => await SettingsUtil.loadFramerate(projectId.toString());

  static String getWatermarkFilter(double opacity, String watermarkPos, int offset) {
    String watermarkFilter = "[1:v]format=rgba,colorchannelmixer=aa=$opacity[watermark];[0:v][watermark]overlay=";

    switch (watermarkPos) {
      case "lower left":
        watermarkFilter += "$offset:main_h-overlay_h-$offset";
        break;
      case "lower right":
        watermarkFilter += "main_w-overlay_w-$offset:main_h-overlay_h-$offset";
        break;
      case "upper left":
        watermarkFilter += "$offset:$offset";
        break;
      case "upper right":
        watermarkFilter += "main_w-overlay_w-$offset:$offset";
        break;
      default:
        watermarkFilter += "$offset:main_h-overlay_h-$offset";
        break;
    }

    return watermarkFilter;
  }

  static const String _winFfmpegAssetPath = 'assets/ffmpeg/windows/ffmpeg.exe';
  static const String _winMarkerName = 'ffmpeg.version';

  static Future<String> _ensureBundledFfmpeg() async {
    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(path.join(dir.path, 'bin'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    final exePath = path.join(binDir.path, 'ffmpeg.exe');
    final markerPath = path.join(binDir.path, _winMarkerName);
    final needsWrite = !(await File(exePath).exists()) || !(await File(markerPath).exists());
    if (needsWrite) {
      final bytes = await rootBundle.load(_winFfmpegAssetPath);
      await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await File(markerPath).writeAsString('1', flush: true);
    }
    return exePath;
  }

  static Future<String> _findFfmpegOnPath() async {
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
      final bundled = await _ensureBundledFfmpeg();
      if (await File(bundled).exists()) return bundled;
    } catch (_) {}
    final onPath = await _findFfmpegOnPath();
    if (onPath.isNotEmpty) return onPath;
    return 'ffmpeg';
  }

  static Future<void> _ensureOutDir(String outputPath) async {
    final outDir = Directory(path.dirname(outputPath));
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

    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));
    if (files.isEmpty) {
      throw StateError('no .png files found in $framesDir');
    }

    final tmpPath = path.join(Directory.systemTemp.path, 'ffconcat_${DateTime.now().millisecondsSinceEpoch}.txt');
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

  static Future<bool> _encodeWindows({
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
