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

  static int pickBitrateKbps(String resolution) {
    final m = RegExp(r'(\d+)x(\d+)').firstMatch(resolution);
    if (m == null) return 12000; // safer default
    final w = int.parse(m.group(1)!);
    final h = int.parse(m.group(2)!);
    final pixels = w * h;

    if (pixels >= 3840 * 2160) return 50000; // 4K: 50 Mbps
    if (pixels >= 2560 * 1440) return 20000; // 1440p: 20 Mbps
    if (pixels >= 1920 * 1080) return 14000; // 1080p: 14 Mbps
    if (pixels >= 1280 * 720)  return 8000;  // 720p: 8 Mbps
    return 5000;                              // lower
  }

  static Future<bool> createTimelapse(
    int projectId,
    framerate,
    totalPhotoCount,
    Function(int currentFrame)? setCurrentFrame
  ) async {
    try {
    print("[VIDEO] createTimelapse called - projectId: $projectId, framerate: $framerate, totalPhotoCount: $totalPhotoCount");
    print("[VIDEO] Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}");

    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(projectId);
    final String videoOutputPath = await DirUtils.getVideoOutputPath(projectId, projectOrientation);
    print("[VIDEO] orientation: $projectOrientation");
    print("[VIDEO] stabilizedDirPath: $stabilizedDirPath");
    print("[VIDEO] videoOutputPath: $videoOutputPath");

    // Check available disk space
    try {
      final outputDir = Directory(path.dirname(videoOutputPath));
      if (await outputDir.exists()) {
        if (Platform.isWindows) {
          final result = await Process.run('wmic', ['logicaldisk', 'where', 'DeviceID="${path.rootPrefix(videoOutputPath).replaceAll('\\', '')}"', 'get', 'FreeSpace', '/value'], runInShell: true);
          print("[VIDEO] Disk space check: ${result.stdout.toString().trim()}");
        } else if (Platform.isLinux || Platform.isMacOS) {
          final result = await Process.run('df', ['-h', videoOutputPath]);
          print("[VIDEO] Disk space check:\n${result.stdout}");
        }
      }
    } catch (e) {
      print("[VIDEO] Could not check disk space: $e");
    }

    await DirUtils.createDirectoryIfNotExists(videoOutputPath);

    final Directory dir = Directory(path.join(stabilizedDirPath, projectOrientation));
    print("[VIDEO] Listing PNG files from: ${dir.path}");

    // Check if directory exists
    if (!await dir.exists()) {
      print("[VIDEO] ERROR: Stabilized directory does not exist: ${dir.path}");
      return false;
    }

    List<String> pngFiles;
    try {
      pngFiles = await dir
          .list()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.path)
          .toList()
        ..sort();
    } catch (e, stackTrace) {
      print("[VIDEO] ERROR: Failed to list directory contents: $e");
      print("[VIDEO] Stack trace: $stackTrace");
      return false;
    }

    print("[VIDEO] Found ${pngFiles.length} PNG files in ${dir.path}");

    // Log sample PNG paths for debugging
    if (pngFiles.isNotEmpty) {
      final sampleCount = pngFiles.length < 3 ? pngFiles.length : 3;
      print("[VIDEO] Sample PNG files (first $sampleCount):");
      for (int i = 0; i < sampleCount; i++) {
        final file = File(pngFiles[i]);
        final exists = await file.exists();
        final size = exists ? await file.length() : 0;
        print("[VIDEO]   ${i + 1}. ${pngFiles[i]} (exists: $exists, size: ${(size / 1024).toStringAsFixed(1)} KB)");
      }
    }

    final bool framerateIsDefault = await SettingsUtil.loadFramerateIsDefault(projectId.toString());
    if (framerateIsDefault) {
      framerate = await getOptimalFramerateFromStabPhotoCount(projectId);
      DB.instance.setSettingByTitle('framerate', framerate.toString(), projectId.toString());
      print("[VIDEO] Using optimal framerate: $framerate");
    }

    if (Platform.isWindows || Platform.isLinux) {
      print("[VIDEO] Using Windows/Linux encoding path");
      try {
        final String framesDir = path.join(stabilizedDirPath, projectOrientation);
        final bool ok = await _encodeWindows(
          framesDir: framesDir,
          outputPath: videoOutputPath,
          fps: framerate,
          projectId: projectId,
          orientation: projectOrientation,
          onLog: (line) => print("[FFMPEG] $line"),
          onProgress: setCurrentFrame,
        );
        print("[VIDEO] _encodeWindows returned: $ok");
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
          print("[VIDEO] Video record added to database");
        }

        return ok;
      } catch (e, stackTrace) {
        print("[VIDEO] ERROR in Windows/Linux encoding: $e");
        print("[VIDEO] Stack trace: $stackTrace");
        return false;
      }
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
    final String listPath = await _buildConcatListFromDir(framesDir, framerate, projectId: projectId, orientation: projectOrientation);

    final resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
    final kbps = pickBitrateKbps(resolution);
    final vtRate = "-b:v ${kbps}k -maxrate ${ (kbps * 1.5).round() }k -bufsize ${ (kbps * 3).round() }k";
    final vCodec = Platform.isAndroid ? 'libx264' : 'h264_videotoolbox';

    String ffmpegCommand = "-y "
        "-f concat -safe 0 "
        "-i \"$listPath\" "
        "-vsync cfr -r 30 "
        "$watermarkInputsAndFilter "
        "-c:v $vCodec $vtRate "
        "-g 240 -movflags +faststart -tag:v avc1 "
        "-pix_fmt yuv420p "
        "\"$videoOutputPath\"";

    try {
      if (Platform.isMacOS) {
        print("[VIDEO] Using macOS encoding path");

        final exeDir = path.dirname(Platform.resolvedExecutable);
        final resourcesDir = path.normalize(path.join(exeDir, '..', 'Resources'));
        final ffmpegExe = path.join(resourcesDir, 'ffmpeg');
        final cmd = '"$ffmpegExe" $ffmpegCommand';

        print('[VIDEO] ffmpeg executable: $ffmpegExe');
        print('[VIDEO] ffmpeg command: $ffmpegCommand');

        final proc = await Process.start('/bin/sh', ['-c', cmd], runInShell: false);
        proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          print("[FFMPEG] $line");
        });
        proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          print("[FFMPEG] $line");
          parseFFmpegOutput(line, framerate, setCurrentFrame);
        });

        final code = await proc.exitCode;
        print("[VIDEO] ffmpeg exit code: $code");

        try {
          await File(listPath).delete();
        } catch (e) {
          print("[VIDEO] Failed to delete concat list: $e");
        }
        if (code == 0) {
          final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
          await DB.instance.addVideo(projectId, resolution, watermarkEnabled.toString(), watermarkPos, totalPhotoCount, framerate);
          print("[VIDEO] Video compilation successful, record added to database");
          return true;
        }
        print("[VIDEO] ffmpeg failed with exit code: $code");
        return false;
      } else {
        print("[VIDEO] Using mobile (FFmpegKit) encoding path");
        kitcfg.FFmpegKitConfig.enableLogCallback((kitlog.Log log) {
          final String output = log.getMessage();
          parseFFmpegOutput(output, framerate, setCurrentFrame);
          print("[FFMPEG] $output");
        });

        print("[VIDEO] Executing ffmpeg command: $ffmpegCommand");
        final kitsession.FFmpegSession session = await kit.FFmpegKit.execute(ffmpegCommand);
        final returnCode = await session.getReturnCode();
        print("[VIDEO] FFmpegKit return code: ${returnCode?.getValue()}");

        if (kitrc.ReturnCode.isSuccess(returnCode)) {
          final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
          await DB.instance.addVideo(projectId, resolution, watermarkEnabled.toString(), watermarkPos, totalPhotoCount, framerate);
          print("[VIDEO] Video compilation successful, record added to database");
          return true;
        } else {
          final logs = await session.getAllLogsAsString();
          print("[VIDEO] FFmpegKit failed. Full logs: $logs");
          return false;
        }
      }
    } catch (e, stackTrace) {
      print("[VIDEO] ERROR in video compilation: $e");
      print("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
    } catch (e, stackTrace) {
      print("[VIDEO] ERROR in createTimelapse: $e");
      print("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
  }

  static Future<bool> createTimelapseFromProjectId(
    int projectId,
    Function(int currentFrame)? setCurrentFrame
  ) async {
    print("[VIDEO] createTimelapseFromProjectId called - projectId: $projectId");
    try {
      String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
      final List<Map<String, dynamic>> stabilizedPhotos = await DB.instance.getStabilizedPhotosByProjectID(projectId, projectOrientation);
      print("[VIDEO] Found ${stabilizedPhotos.length} stabilized photos for orientation: $projectOrientation");
      if (stabilizedPhotos.isEmpty) {
        print("[VIDEO] No stabilized photos found, aborting");
        return false;
      }

      final int framerate = await SettingsUtil.loadFramerate(projectId.toString());
      print("[VIDEO] Loaded framerate: $framerate");

      return await createTimelapse(projectId, framerate, stabilizedPhotos.length, setCurrentFrame);
    } catch (e, stackTrace) {
      print("[VIDEO] ERROR in createTimelapseFromProjectId: $e");
      print("[VIDEO] Stack trace: $stackTrace");
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
    if (!Platform.isWindows) {
      return '';
    }
    print("[VIDEO] Ensuring bundled ffmpeg is extracted...");
    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(path.join(dir.path, 'bin'));
    if (!await binDir.exists()) {
      print("[VIDEO] Creating bin directory: ${binDir.path}");
      await binDir.create(recursive: true);
    }
    final exePath = path.join(binDir.path, 'ffmpeg.exe');
    final markerPath = path.join(binDir.path, _winMarkerName);
    final exeExists = await File(exePath).exists();
    final markerExists = await File(markerPath).exists();
    final needsWrite = !exeExists || !markerExists;
    print("[VIDEO] ffmpeg.exe exists: $exeExists, marker exists: $markerExists, needs extraction: $needsWrite");
    if (needsWrite) {
      print("[VIDEO] Extracting bundled ffmpeg from assets...");
      try {
        final bytes = await rootBundle.load(_winFfmpegAssetPath);
        await File(exePath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        await File(markerPath).writeAsString('1', flush: true);
        print("[VIDEO] Bundled ffmpeg extracted successfully to: $exePath");
      } catch (e) {
        print("[VIDEO] ERROR extracting bundled ffmpeg: $e");
        rethrow;
      }
    }
    return exePath;
  }

  static Future<String> _findFfmpegOnPath() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    print("[VIDEO] Searching for ffmpeg on PATH using '$cmd'...");
    try {
      final result = await Process.run(cmd, ['ffmpeg'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final p = line.trim();
          if (p.isNotEmpty && await File(p).exists()) {
            print("[VIDEO] Found ffmpeg on PATH: $p");
            return p;
          }
        }
      }
      print("[VIDEO] ffmpeg not found on PATH (exit code: ${result.exitCode})");
    } catch (e) {
      print("[VIDEO] Error searching PATH for ffmpeg: $e");
    }
    return '';
  }

  static Future<String> _resolveFfmpegPath() async {
    print("[VIDEO] Resolving ffmpeg path...");
    if (Platform.isWindows) {
      try {
        final bundled = await _ensureBundledFfmpeg();
        if (bundled.isNotEmpty && await File(bundled).exists()) {
          print("[VIDEO] Using bundled ffmpeg: $bundled");
          return bundled;
        }
      } catch (e) {
        print("[VIDEO] Failed to use bundled ffmpeg: $e");
      }
      final onPathWin = await _findFfmpegOnPath();
      if (onPathWin.isNotEmpty) {
        print("[VIDEO] Using ffmpeg from PATH: $onPathWin");
        return onPathWin;
      }
      print("[VIDEO] WARNING: No ffmpeg found, falling back to 'ffmpeg' command");
      return 'ffmpeg';
    } else {
      final onPath = await _findFfmpegOnPath();
      if (onPath.isNotEmpty) return onPath;
      return 'ffmpeg';
    }
  }


  static Future<void> _ensureOutDir(String outputPath) async {
    final outDir = Directory(path.dirname(outputPath));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
  }

  /// Returns a set of valid timestamps from the database for the given project and orientation.
  /// Used to validate filesystem files against the database to prevent orphaned files from appearing in videos.
  static Future<Set<int>> _getValidTimestampsFromDB(int projectId, String orientation) async {
    final photos = await DB.instance.getStabilizedPhotosByProjectID(projectId, orientation);
    final Set<int> timestamps = {};
    for (final photo in photos) {
      final ts = int.tryParse(photo['timestamp']?.toString() ?? '');
      if (ts != null) {
        timestamps.add(ts);
      }
    }
    return timestamps;
  }

  static Future<String> _buildConcatListFromDir(String framesDir, int fps, {int? projectId, String? orientation}) async {
    print("[VIDEO] Building concat list from directory: $framesDir");
    final dir = Directory(framesDir);
    if (!await dir.exists()) {
      print("[VIDEO] ERROR: Image directory does not exist: $framesDir");
      throw FileSystemException('image directory not found', framesDir);
    }
    var files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    // Validate files against database and clean up orphans
    if (projectId != null && orientation != null) {
      final validTimestamps = await _getValidTimestampsFromDB(projectId, orientation);
      final int originalFileCount = files.length;
      final List<String> validFiles = [];
      for (final filePath in files) {
        final filename = path.basenameWithoutExtension(filePath);
        final timestamp = int.tryParse(filename);
        if (timestamp != null && validTimestamps.contains(timestamp)) {
          validFiles.add(filePath);
        } else {
          // Orphaned file: exists in filesystem but not in DB - delete it
          print("[VIDEO] Cleaning up orphaned file (not in DB): $filePath");
          try {
            await File(filePath).delete();
          } catch (e) {
            print("[VIDEO] Failed to delete orphaned file: $e");
          }
        }
      }
      final int orphansRemoved = originalFileCount - validFiles.length;
      files = validFiles;
      print("[VIDEO] After DB validation: ${files.length} valid files (removed $orphansRemoved orphans)");
    }

    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));
    print("[VIDEO] Found ${files.length} PNG files for concat list");
    if (files.isEmpty) {
      print("[VIDEO] ERROR: No .png files found in $framesDir");
      throw StateError('no .png files found in $framesDir');
    }

    final tmpPath = path.join(Directory.systemTemp.path, 'ffconcat_${DateTime.now().millisecondsSinceEpoch}.txt');
    final f = File(tmpPath);
    final perFrame = 1.0 / fps;
    print("[VIDEO] Frame duration: ${perFrame}s (fps: $fps)");

    final sb = StringBuffer();
    for (final fp in files) {
      final norm = fp.replaceAll(r'\', '/');
      final esc = norm.replaceAll("'", r"'\''");
      sb.writeln("file '$esc'");
      sb.writeln('duration $perFrame');
    }
    sb.writeln('duration $perFrame');

    await f.writeAsString(sb.toString(), flush: true);
    print("[VIDEO] Concat list written to: $tmpPath");
    return tmpPath;
  }

  static Future<bool> _encodeWindows({
    required String framesDir,
    required String outputPath,
    required int fps,
    required int projectId,
    required String orientation,
    void Function(String line)? onLog,
    void Function(int frameIndex)? onProgress,
  }) async {
    print("[VIDEO] _encodeWindows started");
    print("[VIDEO] framesDir: $framesDir");
    print("[VIDEO] outputPath: $outputPath");
    print("[VIDEO] fps: $fps");

    final exe = await _resolveFfmpegPath();
    print("[VIDEO] Resolved ffmpeg executable: $exe");

    // Verify ffmpeg exists
    final exeFile = File(exe);
    if (!exe.contains(path.separator) || !await exeFile.exists()) {
      print("[VIDEO] WARNING: ffmpeg path '$exe' may not exist as a file (might be a PATH command)");
    }

    await _ensureOutDir(outputPath);
    final listPath = await _buildConcatListFromDir(framesDir, fps, projectId: projectId, orientation: orientation);

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

    print("[VIDEO] ffmpeg arguments: ${args.join(' ')}");
    print("[VIDEO] Starting ffmpeg process...");

    try {
      final proc = await Process.start(exe, args, runInShell: false);
      print("[VIDEO] ffmpeg process started with PID: ${proc.pid}");

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
      print("[VIDEO] ffmpeg process exited with code: $code");

      try {
        await File(listPath).delete();
        print("[VIDEO] Cleaned up concat list file");
      } catch (e) {
        print("[VIDEO] Failed to clean up concat list: $e");
      }

      // Check if output file was created
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final size = await outputFile.length();
        print("[VIDEO] Output file created: $outputPath (${(size / 1024 / 1024).toStringAsFixed(2)} MB)");
      } else {
        print("[VIDEO] WARNING: Output file was not created: $outputPath");
      }

      return code == 0;
    } catch (e, stackTrace) {
      print("[VIDEO] ERROR starting ffmpeg process: $e");
      print("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
  }
}
