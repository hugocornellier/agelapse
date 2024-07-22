import 'dart:io';

import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_video/log.dart';
import 'package:ffmpeg_kit_flutter_video/return_code.dart';
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
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String inputPattern = path.join(
        await DirUtils.getStabilizedDirPath(projectId),
        projectOrientation,
        '*.png'
    );
    final String videoOutputPath = await DirUtils.getVideoOutputPath(
        projectId,
        projectOrientation
    );
    await DirUtils.createDirectoryIfNotExists(videoOutputPath);

    // If watermark enabled & valid image file exists, configure watermarkConfig
    final bool watermarkEnabled = await SettingsUtil.loadWatermarkSetting(projectId.toString());
    final String watermarkPos = (await DB.instance
        .getSettingValueByTitle('watermark_position'))
        .toLowerCase();
    final String watermarkFilePath = await DirUtils
        .getWatermarkFilePath(projectId);
    String watermarkConfig = "";

    if (watermarkEnabled && Utils.isImage(watermarkFilePath) && await File(watermarkFilePath).exists()) {
      final String watermarkOpacitySettingVal = await DB.instance.getSettingValueByTitle('watermark_opacity');
      final double watermarkOpacity = double.tryParse(watermarkOpacitySettingVal) ?? 0.8;
      final String watermarkFilter = getWatermarkFilter(watermarkOpacity, watermarkPos, 10);
      watermarkConfig = watermarkEnabled ? "-i $watermarkFilePath -filter_complex '$watermarkFilter'" : "";
    }

    final bool framerateIsDefault = await SettingsUtil.loadFramerateIsDefault(projectId.toString());
    if (framerateIsDefault) {
      framerate = await getOptimalFramerateFromStabPhotoCount(projectId);
      DB.instance.setSettingByTitle(
        'framerate',
        framerate.toString(),
        projectId.toString()
      );
    }

    // Final ffmpeg command
    String ffmpegCommand = "-y "
        "-framerate $framerate "
        "-pattern_type glob "
        "-i '$inputPattern' "
        "-r 30 "
        "$watermarkConfig "
        "-c:v mpeg4 -q:v 1 "
        "-pix_fmt yuv420p "
        "$videoOutputPath";

    try {
      FFmpegKitConfig.enableLogCallback((Log log) {
        final String output = log.getMessage();
        print(output);
        parseFFmpegOutput(output, framerate, setCurrentFrame);
      });

      FFmpegSession session = await FFmpegKit.execute(ffmpegCommand);

      if (ReturnCode.isSuccess(await session.getReturnCode())) {
        final String resolution = await SettingsUtil.loadVideoResolution(projectId.toString());
        await DB.instance.addVideo(
          projectId,
          resolution,
          watermarkEnabled.toString(),
          watermarkPos,
          totalPhotoCount,
          framerate!
        );
        return true;
      } else {
        //print('FFmpeg command failed with return code: ${await session.getReturnCode()}');
        return false;
      }
    } catch (e) {
      //print('An error occurred: $e');
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
    final Iterable<RegExpMatch> matches = frameRegex.allMatches(output);
    if (matches.isNotEmpty) {
      final RegExpMatch match = matches.last;
      final int videoFrame = int.parse(match.group(1)!);
      final int currFrame = videoFrame ~/ (30 / framerate);
      currentFrame = currFrame;
      setCurrentFrame!(currentFrame);
      print("Processing frame $currentFrame");
    }
  }

  static Future<int> getStabilizedPhotoCount(int projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    return (await DB.instance.getStabilizedPhotosByProjectID(projectId, projectOrientation)).length;
  }

  static createGif(videoOutputPath, framerate) async {
    String gifPath = videoOutputPath.replaceAll(path.extension(videoOutputPath), ".gif");
    print("Trying to save gif to $gifPath");

    await FFmpegKit.execute('-i $videoOutputPath $gifPath');
  }

  static Future<bool> videoOutputSettingsChanged(projectId, newestVideo) async {
    if (newestVideo == null) return false;

    final bool newPhotos = newestVideo['photoCount'] != await _getTotalPhotoCountByProjectId(projectId);
    if (newPhotos) {
      print("New photos found");
      return true;
    }

    final framerateSetting = await _getFramerate(projectId);
    final bool framerateChanged = newestVideo['framerate'] != framerateSetting;
    if (framerateChanged) {
      print("Framerate changed. video framerate: ${newestVideo['framerate']}, framerate setting: $framerateSetting");
      return true;
    }

    final String watermarkEnabled = (await SettingsUtil.loadWatermarkSetting(projectId.toString())).toString();
    if (newestVideo['watermarkEnabled'] != watermarkEnabled) {
      print("Watermark enabled setting changed");
      return true;
    }

    final String watermarkPos = (await DB.instance.getSettingValueByTitle('watermark_position')).toLowerCase();
    if (newestVideo['watermarkPos'] != watermarkPos) {
      print("Watermark pos setting changed");
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