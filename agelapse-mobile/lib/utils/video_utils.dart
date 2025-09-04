import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart' as kit;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart' as kitcfg;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart' as kitsession;
import 'package:ffmpeg_kit_flutter_new/log.dart' as kitlog;
import 'package:ffmpeg_kit_flutter_new/return_code.dart' as kitrc;
import '../utils/ffmpeg_windows.dart' show encodeTimelapseWindows;

import 'package:path/path.dart' as path;
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
      final String inputPattern = path.join(framesDir, '*.png').replaceAll(r'\', '/');
      final bool ok = await encodeTimelapseWindows(
        inputPattern: inputPattern,
        outputPath: videoOutputPath,
        fps: framerate,
      );
      if (ok) {
        final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
        await DB.instance.addVideo(projectId, resolution, (await SettingsUtil.loadWatermarkSetting(projectId.toString())).toString(),
            (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase(), totalPhotoCount, framerate);
      }
      return ok;
    }

    final String inputFiles = pngFiles.join('|');

    final bool watermarkEnabled = await SettingsUtil.loadWatermarkSetting(projectId.toString());
    final String watermarkPos = (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase();
    final String watermarkFilePath = await DirUtils.getWatermarkFilePath(projectId);
    String watermarkConfig = "";
    if (watermarkEnabled && Utils.isImage(watermarkFilePath) && await File(watermarkFilePath).exists()) {
      final String watermarkOpacitySettingVal = await DB.instance.getSettingValueByTitle('watermark_opacity');
      final double watermarkOpacity = double.tryParse(watermarkOpacitySettingVal) ?? 0.8;
      final String watermarkFilter = getWatermarkFilter(watermarkOpacity, watermarkPos, 10);
      watermarkConfig = "-i $watermarkFilePath -filter_complex '$watermarkFilter'";
    }

    String ffmpegCommand = "-y "
        "-framerate $framerate "
        "-i 'concat:$inputFiles' "
        "-r 30 "
        "$watermarkConfig "
        "-c:v mpeg4 -q:v 1 "
        "-pix_fmt yuv420p "
        "$videoOutputPath";

    try {
      kitcfg.FFmpegKitConfig.enableLogCallback((kitlog.Log log) {
        final String output = log.getMessage();
        parseFFmpegOutput(output, framerate, setCurrentFrame);
      });

      final kitsession.FFmpegSession session = await kit.FFmpegKit.execute(ffmpegCommand);
      if (kitrc.ReturnCode.isSuccess(await session.getReturnCode())) {
        final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
        await DB.instance.addVideo(projectId, resolution, watermarkEnabled.toString(), watermarkPos, totalPhotoCount, framerate);
        return true;
      } else {
        return false;
      }
    } catch (_) {
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

    // Set watermark position based on watermarkPos setting
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
      // Default to lower left if the setting is invalid or not specified
        watermarkFilter += "$offset:main_h-overlay_h-$offset";
        break;
    }

    return watermarkFilter;
  }
}