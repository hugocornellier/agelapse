import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart' as kit;
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../services/ffmpeg_process_manager.dart';
import '../services/log_service.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart' as kitcfg;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart' as kitsession;
import 'package:ffmpeg_kit_flutter_new/log.dart' as kitlog;
import 'package:ffmpeg_kit_flutter_new/return_code.dart' as kitrc;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../utils/date_stamp_utils.dart';
import '../utils/capture_timezone.dart';

import '../services/database_helper.dart';
import 'dir_utils.dart';

/// Helper class for grouping frames with the same date
class _DateRange {
  final String date;
  final int startFrame;
  final int endFrame;
  _DateRange(this.date, this.startFrame, this.endFrame);
}

/// Data class for date stamp overlay filter info
class DateStampOverlayInfo {
  final String filterComplex;
  final List<String> pngInputPaths;
  final String tempDir;
  final String outputMapLabel;

  DateStampOverlayInfo({
    required this.filterComplex,
    required this.pngInputPaths,
    required this.tempDir,
    required this.outputMapLabel,
  });
}

class VideoUtils {
  static int currentFrame = 1;

  // Throttling for progress updates (max 10 updates/sec = 100ms interval)
  static DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _progressThrottleInterval = Duration(milliseconds: 100);

  // Throttling for FFmpeg log output
  static int _logLineCount = 0;
  static const int _logEveryNthLine =
      5; // Log every 5th line for progress visibility

  // ETA tracking for video compilation
  static final Stopwatch _videoStopwatch = Stopwatch();
  static int _totalFramesForEta = 0;

  /// Resets the video compilation stopwatch. Call before starting compilation.
  static void resetVideoStopwatch(int totalFrames) {
    _videoStopwatch.reset();
    _videoStopwatch.start();
    _totalFramesForEta = totalFrames;
  }

  /// Stops the video compilation stopwatch. Call after compilation completes.
  static void stopVideoStopwatch() {
    _videoStopwatch.stop();
  }

  /// Resets the progress throttle state. For testing only.
  @visibleForTesting
  static void resetProgressThrottle() {
    _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Calculates the ETA for video compilation based on frames processed.
  /// Returns a formatted string like "2m 30s" or null if not enough data.
  static String? calculateVideoEta(int framesProcessed) {
    if (framesProcessed <= 0 || _totalFramesForEta <= 0) return null;
    if (!_videoStopwatch.isRunning) return null;

    final elapsedMs = _videoStopwatch.elapsedMilliseconds;
    if (elapsedMs < 500) return null; // Wait for at least 500ms of data

    final avgTimePerFrame = elapsedMs / framesProcessed;
    final remainingFrames = _totalFramesForEta - framesProcessed;
    if (remainingFrames <= 0) return "0m 0s";

    final estimatedRemainingMs = (avgTimePerFrame * remainingFrames).toInt();
    return _formatDuration(estimatedRemainingMs);
  }

  /// Formats milliseconds into a human-readable duration string.
  static String _formatDuration(int milliseconds) {
    final hours = milliseconds ~/ (1000 * 60 * 60);
    final minutes = (milliseconds % (1000 * 60 * 60)) ~/ (1000 * 60);
    final seconds = (milliseconds % (1000 * 60)) ~/ 1000;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Generate date stamp overlay info with PNG assets.
  /// Returns DateStampOverlayInfo with filter_complex and PNG paths, or null if disabled.
  /// This approach renders date stamps as PNGs with rounded corners matching gallery style.
  static Future<DateStampOverlayInfo?> _generateDateStampOverlay({
    required int projectId,
    required String framesDir,
    required String orientation,
    required int videoWidth,
    required int videoHeight,
  }) async {
    final projectIdStr = projectId.toString();

    // Check if date stamp is enabled
    final dateStampEnabled = await SettingsUtil.loadExportDateStampEnabled(
      projectIdStr,
    );
    if (!dateStampEnabled) return null;

    LogService.instance
        .log("[VIDEO] Date stamp enabled, generating PNG overlay filter");

    // Load date stamp settings
    final dateFormat = await SettingsUtil.loadExportDateStampFormat(
      projectIdStr,
    );
    final datePosition = await SettingsUtil.loadExportDateStampPosition(
      projectIdStr,
    );
    final dateSize = await SettingsUtil.loadExportDateStampSize(projectIdStr);

    // Load watermark settings for collision avoidance
    final watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
      projectIdStr,
    );
    final String? watermarkPos = watermarkEnabled
        ? (await DB.instance.getSettingValueByTitle('watermark_position'))
            .toLowerCase()
        : null;

    // Get list of PNG files
    final dir = Directory(framesDir);
    if (!await dir.exists()) return null;

    var files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    // Filter to only include files that exist in the database (same as concat list)
    final validTimestamps =
        await _getValidTimestampsFromDB(projectId, orientation);
    files = files.where((filePath) {
      final filename = path.basenameWithoutExtension(filePath);
      final timestamp = int.tryParse(filename);
      return timestamp != null && validTimestamps.contains(timestamp);
    }).toList();

    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));

    if (files.isEmpty) return null;

    LogService.instance
        .log("[VIDEO] DateStamp overlay: Processing ${files.length} files");

    // Load timezone offsets for accurate date stamps
    final captureOffsetMap = await CaptureTimezone.loadOffsetsForFiles(
      files,
      projectId,
    );

    // Build list of dates for each frame
    final List<String> frameDates = [];
    for (int i = 0; i < files.length; i++) {
      final filePath = files[i];
      final filename = path.basenameWithoutExtension(filePath);
      final timestampMs = int.tryParse(filename);

      if (timestampMs == null) {
        frameDates.add('');
        continue;
      }

      final int? offsetMinutes = captureOffsetMap[filename];
      final dateText = DateStampUtils.formatTimestamp(
        timestampMs,
        dateFormat,
        captureOffsetMinutes: offsetMinutes,
      );
      frameDates.add(dateText);

      if (i < 5 || i >= files.length - 3) {
        LogService.instance.log("[VIDEO] Frame $i: $dateText");
      }
    }

    // Group consecutive frames with the same date to minimize filter complexity
    final List<_DateRange> dateRanges = [];
    String? currentDate;
    int rangeStart = 0;

    for (int i = 0; i < frameDates.length; i++) {
      if (frameDates[i] != currentDate) {
        if (currentDate != null && currentDate.isNotEmpty) {
          dateRanges.add(_DateRange(currentDate, rangeStart, i - 1));
        }
        currentDate = frameDates[i];
        rangeStart = i;
      }
    }
    // Add the last range
    if (currentDate != null && currentDate.isNotEmpty) {
      dateRanges
          .add(_DateRange(currentDate, rangeStart, frameDates.length - 1));
    }

    LogService.instance
        .log("[VIDEO] Date ranges: ${dateRanges.length} unique dates");

    // Get unique dates for PNG generation
    final uniqueDates = dateRanges.map((r) => r.date).toSet().toList();

    // Generate date stamp PNG assets
    final tempBaseDir = (await getTemporaryDirectory()).path;
    final assets = await DateStampUtils.generateDateStampAssets(
      uniqueDates: uniqueDates,
      videoHeight: videoHeight,
      sizePercent: dateSize,
      baseTempDir: tempBaseDir,
    );

    if (assets == null || assets.dateToPath.isEmpty) {
      LogService.instance.log("[VIDEO] Failed to generate date stamp PNGs");
      return null;
    }

    // Fixed 8px margin to exactly match image preview
    int marginV = 8;
    int marginH = 8;

    // Check for watermark collision and adjust margin
    final bool sameCornerAsWatermark =
        watermarkPos != null && datePosition.toLowerCase() == watermarkPos;
    if (sameCornerAsWatermark) {
      marginV += (videoHeight * 0.05).round();
    }

    // Build overlay filter chain
    // Input 0 is the video frames, inputs 1+ are the date stamp PNGs
    final List<String> pngPaths = [];
    final Map<String, int> dateToInputIndex = {};

    // Assign input indices to each unique date PNG
    for (int i = 0; i < uniqueDates.length; i++) {
      final date = uniqueDates[i];
      final pngPath = assets.dateToPath[date];
      if (pngPath != null) {
        pngPaths.add(pngPath);
        dateToInputIndex[date] = pngPaths.length; // 1-indexed (0 is video)
      }
    }

    // Build filter_complex string
    // Each overlay: [prev][inputN]overlay=x:y:enable='between(n,start,end)'[outN]
    final filterParts = <String>[];
    String currentLabel = '0'; // Start with input 0 (video)

    for (int i = 0; i < dateRanges.length; i++) {
      final range = dateRanges[i];
      final inputIndex = dateToInputIndex[range.date];
      if (inputIndex == null) continue;

      final enableExpr = range.startFrame == range.endFrame
          ? "eq(n\\,${range.startFrame})"
          : "between(n\\,${range.startFrame}\\,${range.endFrame})";

      // Calculate x,y position based on corner setting
      // For overlay, we position relative to video dimensions
      String xExpr, yExpr;
      switch (datePosition.toLowerCase()) {
        case 'lower right':
          xExpr = 'W-w-$marginH';
          yExpr = 'H-h-$marginV';
          break;
        case 'lower left':
          xExpr = '$marginH';
          yExpr = 'H-h-$marginV';
          break;
        case 'upper right':
          xExpr = 'W-w-$marginH';
          yExpr = '$marginV';
          break;
        case 'upper left':
          xExpr = '$marginH';
          yExpr = '$marginV';
          break;
        default:
          xExpr = 'W-w-$marginH';
          yExpr = 'H-h-$marginV';
      }

      final nextLabel = 't$i';
      filterParts.add(
          "[$currentLabel][$inputIndex]overlay=x=$xExpr:y=$yExpr:enable='$enableExpr'[$nextLabel]");
      currentLabel = nextLabel;
    }

    if (filterParts.isEmpty) {
      LogService.instance.log("[VIDEO] No overlay filters generated");
      return null;
    }

    final filterComplex = filterParts.join(';');
    LogService.instance.log(
        "[VIDEO] Overlay filter_complex: ${filterComplex.length} chars, ${pngPaths.length} PNGs");

    return DateStampOverlayInfo(
      filterComplex: filterComplex,
      pngInputPaths: pngPaths,
      tempDir: assets.tempDir,
      outputMapLabel: currentLabel,
    );
  }

  /// Get video dimensions from the first frame in a directory
  static Future<(int, int)?> _getFrameDimensions(String framesDir) async {
    final dir = Directory(framesDir);
    if (!await dir.exists()) return null;

    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    if (files.isEmpty) return null;

    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));

    // Read first frame to get dimensions
    try {
      final firstFrame = File(files.first);
      final bytes = await firstFrame.readAsBytes();

      // PNG dimensions are at bytes 16-23 (width at 16-19, height at 20-23)
      // PNG signature is 8 bytes, then IHDR chunk
      if (bytes.length < 24) return null;

      // Check PNG signature
      if (bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        return null;
      }

      // Width and height are big-endian 4-byte integers at offset 16 and 20
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];

      LogService.instance.log("[VIDEO] Frame dimensions: ${width}x$height");
      return (width, height);
    } catch (e) {
      LogService.instance.log("[VIDEO] Failed to read frame dimensions: $e");
      return null;
    }
  }

  static int pickBitrateKbps(String resolution) {
    // Handle resolution setting strings (e.g., "8K", "4K", "1080p")
    if (resolution == "8K") return 100000; // 8K: 100 Mbps
    if (resolution == "4K") return 50000; // 4K: 50 Mbps
    if (resolution == "1080p") return 14000; // 1080p: 14 Mbps

    // Handle custom resolution (short side as number, e.g., "1728")
    final shortSide = double.tryParse(resolution);
    if (shortSide != null) {
      // Estimate pixels assuming 16:9 aspect ratio for bitrate calculation
      final longSide = shortSide * (16 / 9);
      final pixels = (shortSide * longSide).toInt();
      return _bitrateFromPixels(pixels);
    }

    // Handle dimension strings (e.g., "7680x4320", "1920x1080")
    final m = RegExp(r'(\d+)x(\d+)').firstMatch(resolution);
    if (m == null) return 12000; // safer default
    final w = int.parse(m.group(1)!);
    final h = int.parse(m.group(2)!);
    return _bitrateFromPixels(w * h);
  }

  static int _bitrateFromPixels(int pixels) {
    if (pixels >= 5760 * 4320) return 100000; // 8K: 100 Mbps
    if (pixels >= 3840 * 2160) return 50000; // 4K: 50 Mbps
    if (pixels >= 2560 * 1440) return 20000; // 1440p: 20 Mbps
    if (pixels >= 1920 * 1080) return 14000; // 1080p: 14 Mbps
    if (pixels >= 1280 * 720) return 8000; // 720p: 8 Mbps
    return 5000; // lower
  }

  /// Check if resolution requires HEVC encoder (H.264 VideoToolbox doesn't support 8K)
  /// Returns true for 8K preset or custom resolutions with short side > 2304 (4K)
  static bool _resolutionNeedsHevc(String resolution) {
    if (resolution == "8K") return true;
    if (resolution == "4K" || resolution == "1080p") return false;

    // Handle WIDTHxHEIGHT format (e.g., "1920x1080")
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      final shortSide = w < h ? w : h;
      return shortSide > 2304;
    }

    // Custom resolution: parse short side and check if above 4K threshold
    final shortSide = double.tryParse(resolution);
    if (shortSide != null && shortSide > 2304) return true;

    return false;
  }

  static Future<bool> createTimelapse(
    int projectId,
    framerate,
    totalPhotoCount,
    Function(int currentFrame)? setCurrentFrame, {
    String? orientation,
  }) async {
    try {
      LogService.instance.log(
        "[VIDEO] createTimelapse called - projectId: $projectId, framerate: $framerate, totalPhotoCount: $totalPhotoCount",
      );
      LogService.instance.log(
        "[VIDEO] Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}",
      );

      String projectOrientation = orientation ??
          await SettingsUtil.loadProjectOrientation(projectId.toString());
      final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(
        projectId,
      );
      final String videoOutputPath = await DirUtils.getVideoOutputPath(
        projectId,
        projectOrientation,
      );
      LogService.instance.log("[VIDEO] orientation: $projectOrientation");
      LogService.instance.log("[VIDEO] stabilizedDirPath: $stabilizedDirPath");
      LogService.instance.log("[VIDEO] videoOutputPath: $videoOutputPath");

      // Check available disk space
      try {
        final outputDir = Directory(path.dirname(videoOutputPath));
        if (await outputDir.exists()) {
          if (Platform.isWindows) {
            final result = await Process.run(
                'wmic',
                [
                  'logicaldisk',
                  'where',
                  'DeviceID="${path.rootPrefix(videoOutputPath).replaceAll('\\', '')}"',
                  'get',
                  'FreeSpace',
                  '/value',
                ],
                runInShell: true);
            LogService.instance.log(
              "[VIDEO] Disk space check: ${result.stdout.toString().trim()}",
            );
          } else if (Platform.isLinux || Platform.isMacOS) {
            // df works in both .deb and Flatpak (available in freedesktop runtime)
            try {
              final result = await Process.run('df', ['-h', videoOutputPath]);
              if (result.exitCode == 0) {
                LogService.instance.log(
                  "[VIDEO] Disk space check:\n${result.stdout}",
                );
              } else {
                LogService.instance.log(
                  "[VIDEO] Disk space check unavailable (exit ${result.exitCode})",
                );
              }
            } catch (dfError) {
              // Graceful fallback - disk space check is informational only
              LogService.instance.log(
                "[VIDEO] Disk space check unavailable: $dfError",
              );
            }
          }
        }
      } catch (e) {
        LogService.instance.log("[VIDEO] Could not check disk space: $e");
      }

      await DirUtils.createDirectoryIfNotExists(videoOutputPath);

      final Directory dir = Directory(
        path.join(stabilizedDirPath, projectOrientation),
      );
      LogService.instance.log("[VIDEO] Source directory: ${dir.path}");

      // Check if directory exists
      if (!await dir.exists()) {
        LogService.instance.log(
          "[VIDEO] ERROR: Stabilized directory does not exist: ${dir.path}",
        );
        return false;
      }

      final bool framerateIsDefault = await SettingsUtil.loadFramerateIsDefault(
        projectId.toString(),
      );
      if (framerateIsDefault) {
        framerate = await getOptimalFramerateFromStabPhotoCount(projectId);
        DB.instance.setSettingByTitle(
          'framerate',
          framerate.toString(),
          projectId.toString(),
        );
        LogService.instance.log("[VIDEO] Using optimal framerate: $framerate");
      }

      if (Platform.isWindows || Platform.isLinux) {
        LogService.instance.log("[VIDEO] Using Windows/Linux encoding path");
        try {
          final String framesDir = path.join(
            stabilizedDirPath,
            projectOrientation,
          );

          // Get frame dimensions for date stamp overlay
          final dimensions = await _getFrameDimensions(framesDir);
          if (dimensions == null) {
            LogService.instance
                .log("[VIDEO] ERROR: Could not get frame dimensions");
            return false;
          }
          final (videoWidth, videoHeight) = dimensions;

          // Generate date stamp overlay with PNG assets (if enabled)
          final dateStampOverlay = await _generateDateStampOverlay(
            projectId: projectId,
            framesDir: framesDir,
            orientation: projectOrientation,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
          );

          final bool ok = await _encodeWindows(
            framesDir: framesDir,
            outputPath: videoOutputPath,
            fps: framerate,
            projectId: projectId,
            orientation: projectOrientation,
            onLog: (line) => LogService.instance.log("[FFMPEG] $line"),
            onProgress: setCurrentFrame,
            dateStampOverlay: dateStampOverlay,
          );

          // Clean up date stamp temp PNGs
          if (dateStampOverlay != null) {
            try {
              final tempDir = Directory(dateStampOverlay.tempDir);
              if (await tempDir.exists()) {
                await tempDir.delete(recursive: true);
                LogService.instance
                    .log("[VIDEO] Cleaned up date stamp temp PNGs");
              }
            } catch (e) {
              LogService.instance
                  .log("[VIDEO] Failed to clean up date stamp PNGs: $e");
            }
          }
          LogService.instance.log("[VIDEO] _encodeWindows returned: $ok");
          if (ok) {
            final String resolution = await SettingsUtil.loadVideoResolution(
              projectId.toString(),
            );
            await DB.instance.addVideo(
              projectId,
              resolution,
              (await SettingsUtil.loadWatermarkSetting(
                projectId.toString(),
              ))
                  .toString(),
              (await DB.instance.getSettingValueByTitle(
                'watermark_position',
              ))
                  .toLowerCase(),
              totalPhotoCount,
              framerate,
            );
            LogService.instance.log("[VIDEO] Video record added to database");
          }

          return ok;
        } catch (e, stackTrace) {
          LogService.instance.log(
            "[VIDEO] ERROR in Windows/Linux encoding: $e",
          );
          LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
          return false;
        }
      }

      final bool watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
        projectId.toString(),
      );
      final String watermarkPos = (await DB.instance.getSettingValueByTitle(
        'watermark_position',
      ))
          .toLowerCase();
      final String watermarkFilePath = await DirUtils.getWatermarkFilePath(
        projectId,
      );

      final String framesDir = path.join(
        stabilizedDirPath,
        projectOrientation,
      );

      // Get frame dimensions for date stamp overlay
      final dimensions = await _getFrameDimensions(framesDir);
      if (dimensions == null) {
        LogService.instance
            .log("[VIDEO] ERROR: Could not get frame dimensions");
        return false;
      }
      final (videoWidth, videoHeight) = dimensions;

      // Generate date stamp overlay with PNG assets (if enabled)
      final dateStampOverlay = await _generateDateStampOverlay(
        projectId: projectId,
        framesDir: framesDir,
        orientation: projectOrientation,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
      );

      // Build input arguments (video frames + date stamp PNGs + watermark)
      String dateStampInputs = "";
      if (dateStampOverlay != null) {
        for (final pngPath in dateStampOverlay.pngInputPaths) {
          dateStampInputs += "-i \"$pngPath\" ";
        }
      }

      // Build watermark input
      String watermarkInput = "";
      int watermarkInputIndex =
          1 + (dateStampOverlay?.pngInputPaths.length ?? 0);
      String? watermarkFilterPart;
      if (watermarkEnabled &&
          Utils.isImage(watermarkFilePath) &&
          await File(watermarkFilePath).exists()) {
        final String watermarkOpacitySettingVal =
            await DB.instance.getSettingValueByTitle('watermark_opacity');
        final double watermarkOpacity =
            double.tryParse(watermarkOpacitySettingVal) ?? 0.8;
        watermarkInput = "-i \"$watermarkFilePath\"";
        watermarkFilterPart = getWatermarkFilter(
          watermarkOpacity,
          watermarkPos,
          10,
        );
      }

      // Build combined filter string
      String filterArgs = "";
      String mapArg = "";
      if (dateStampOverlay != null && watermarkFilterPart != null) {
        // Both date stamp overlay and watermark
        // Chain: video -> date stamp overlays -> watermark overlay
        final wmFilter = watermarkFilterPart
            .replaceFirst('[0:v]', '[${dateStampOverlay.outputMapLabel}]')
            .replaceFirst('[1:v]', '[$watermarkInputIndex:v]');
        filterArgs =
            "-filter_complex \"${dateStampOverlay.filterComplex};$wmFilter\"";
        // Extract output label from watermark filter (usually ends with [out] or similar)
        final wmOutMatch = RegExp(r'\[(\w+)\]$').firstMatch(wmFilter);
        mapArg = wmOutMatch != null ? "-map \"[${wmOutMatch.group(1)}]\"" : "";
      } else if (dateStampOverlay != null) {
        // Only date stamp overlay
        filterArgs = "-filter_complex \"${dateStampOverlay.filterComplex}\"";
        mapArg = "-map \"[${dateStampOverlay.outputMapLabel}]\"";
      } else if (watermarkFilterPart != null) {
        // Only watermark
        filterArgs = "-filter_complex \"$watermarkFilterPart\"";
      }

      final String listPath = await _buildConcatListFromDir(
        framesDir,
        framerate,
        projectId: projectId,
        orientation: projectOrientation,
      );

      final resolution = await SettingsUtil.loadVideoResolution(
        projectId.toString(),
      );
      final kbps = pickBitrateKbps(resolution);
      final vtRate =
          "-b:v ${kbps}k -maxrate ${(kbps * 1.5).round()}k -bufsize ${(kbps * 3).round()}k";
      // Use HEVC hardware encoder for high resolutions on macOS/iOS (h264_videotoolbox doesn't support 8K)
      // Use libx264 on Android (FFmpegKit has it)
      final bool needsHevc = _resolutionNeedsHevc(resolution);
      final String vCodec;
      final String codecTag;
      if (Platform.isAndroid) {
        vCodec = 'libx264';
        codecTag = '-tag:v avc1';
      } else if (needsHevc) {
        // Use HEVC (H.265) for high resolutions on macOS/iOS
        // -allow_sw 1 enables software fallback when hardware encoder doesn't support resolution (e.g. 8K)
        vCodec = 'hevc_videotoolbox -allow_sw 1';
        codecTag = '-tag:v hvc1';
      } else {
        vCodec = 'h264_videotoolbox';
        codecTag = '-tag:v avc1';
      }

      String ffmpegCommand = "-y "
          "-f concat -safe 0 "
          "-i \"$listPath\" "
          "$dateStampInputs"
          "$watermarkInput "
          "-vsync cfr -r 30 "
          "$filterArgs $mapArg "
          "-c:v $vCodec $vtRate "
          "-g 240 -movflags +faststart $codecTag "
          "-pix_fmt yuv420p "
          "\"$videoOutputPath\"";

      bool success = false;
      try {
        if (Platform.isMacOS) {
          LogService.instance.log("[VIDEO] Using macOS encoding path");

          final exeDir = path.dirname(Platform.resolvedExecutable);
          final resourcesDir = path.normalize(
            path.join(exeDir, '..', 'Resources'),
          );
          final ffmpegExe = path.join(resourcesDir, 'ffmpeg');
          final cmd = '"$ffmpegExe" $ffmpegCommand';

          LogService.instance.log('[VIDEO] ffmpeg executable: $ffmpegExe');
          LogService.instance.log('[VIDEO] ffmpeg command: $ffmpegCommand');

          // Use 'sh' without absolute path - works in both .deb (/bin/sh)
          // and Flatpak (sandbox provides sh in PATH)
          final proc = await Process.start(
              'sh',
              [
                '-c',
                cmd,
              ],
              runInShell: false);
          FFmpegProcessManager.instance.registerProcess(proc);

          // Reset throttle counters for new compilation
          _logLineCount = 0;
          _lastProgressUpdate = DateTime.now();

          proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            // Throttle stdout logging
            _logLineCount++;
            if (_logLineCount % _logEveryNthLine == 0) {
              LogService.instance.log("[FFMPEG] $line");
            }
          });
          proc.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            // Always parse for progress, but throttle logging
            parseFFmpegOutput(line, framerate, setCurrentFrame);
            _logLineCount++;
            if (_logLineCount % _logEveryNthLine == 0) {
              LogService.instance.log("[FFMPEG] $line");
            }
          });

          final code = await proc.exitCode;
          FFmpegProcessManager.instance.unregisterProcess();
          LogService.instance.log("[VIDEO] ffmpeg exit code: $code");

          try {
            await File(listPath).delete();
          } catch (e) {
            LogService.instance.log("[VIDEO] Failed to delete concat list: $e");
          }
          if (code == 0) {
            final String resolution = await SettingsUtil.loadVideoResolution(
              projectId.toString(),
            );
            await DB.instance.addVideo(
              projectId,
              resolution,
              watermarkEnabled.toString(),
              watermarkPos,
              totalPhotoCount,
              framerate,
            );
            LogService.instance.log(
              "[VIDEO] Video compilation successful, record added to database",
            );
            success = true;
          } else {
            LogService.instance.log(
              "[VIDEO] ffmpeg failed with exit code: $code",
            );
          }
        } else {
          LogService.instance.log(
            "[VIDEO] Using mobile (FFmpegKit) encoding path",
          );

          // Reset throttle counters for new compilation
          _logLineCount = 0;
          _lastProgressUpdate = DateTime.now();

          kitcfg.FFmpegKitConfig.enableLogCallback((kitlog.Log log) {
            final String output = log.getMessage();
            // Always parse for progress (internally throttled)
            parseFFmpegOutput(output, framerate, setCurrentFrame);
            // Throttle logging to reduce UI thread load
            _logLineCount++;
            if (_logLineCount % _logEveryNthLine == 0) {
              LogService.instance.log("[FFMPEG] $output");
            }
          });

          LogService.instance.log(
            "[VIDEO] Executing ffmpeg command: $ffmpegCommand",
          );
          final kitsession.FFmpegSession session = await kit.FFmpegKit.execute(
            ffmpegCommand,
          );
          FFmpegProcessManager.instance.registerSession(session);

          final returnCode = await session.getReturnCode();
          FFmpegProcessManager.instance.unregisterSession();
          LogService.instance.log(
            "[VIDEO] FFmpegKit return code: ${returnCode?.getValue()}",
          );

          if (kitrc.ReturnCode.isSuccess(returnCode)) {
            final String resolution = await SettingsUtil.loadVideoResolution(
              projectId.toString(),
            );
            await DB.instance.addVideo(
              projectId,
              resolution,
              watermarkEnabled.toString(),
              watermarkPos,
              totalPhotoCount,
              framerate,
            );
            LogService.instance.log(
              "[VIDEO] Video compilation successful, record added to database",
            );
            success = true;
          } else {
            final logs = await session.getAllLogsAsString();
            LogService.instance.log(
              "[VIDEO] FFmpegKit failed. Full logs: $logs",
            );
          }
        }
      } catch (e, stackTrace) {
        LogService.instance.log("[VIDEO] ERROR in video compilation: $e");
        LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      }

      // Clean up date stamp temp PNGs
      if (dateStampOverlay != null) {
        try {
          final tempDir = Directory(dateStampOverlay.tempDir);
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
            LogService.instance.log("[VIDEO] Cleaned up date stamp temp PNGs");
          }
        } catch (e) {
          LogService.instance
              .log("[VIDEO] Failed to clean up date stamp PNGs: $e");
        }
      }

      return success;
    } catch (e, stackTrace) {
      LogService.instance.log("[VIDEO] ERROR in createTimelapse: $e");
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
  }

  static Future<bool> createTimelapseFromProjectId(
    int projectId,
    Function(int currentFrame)? setCurrentFrame,
  ) async {
    LogService.instance.log(
      "[VIDEO] createTimelapseFromProjectId called - projectId: $projectId",
    );
    try {
      String projectOrientation = await SettingsUtil.loadProjectOrientation(
        projectId.toString(),
      );
      final List<Map<String, dynamic>> stabilizedPhotos = await DB.instance
          .getStabilizedPhotosByProjectID(projectId, projectOrientation);
      LogService.instance.log(
        "[VIDEO] Found ${stabilizedPhotos.length} stabilized photos for orientation: $projectOrientation",
      );
      if (stabilizedPhotos.isEmpty) {
        LogService.instance.log("[VIDEO] No stabilized photos found, aborting");
        return false;
      }

      final int framerate = await SettingsUtil.loadFramerate(
        projectId.toString(),
      );
      LogService.instance.log("[VIDEO] Loaded framerate: $framerate");

      return await createTimelapse(
        projectId,
        framerate,
        stabilizedPhotos.length,
        setCurrentFrame,
        orientation: projectOrientation,
      );
    } catch (e, stackTrace) {
      LogService.instance.log(
        "[VIDEO] ERROR in createTimelapseFromProjectId: $e",
      );
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
  }

  static Future<int> getOptimalFramerateFromStabPhotoCount(
    int projectId,
  ) async {
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

  /// Parses FFmpeg output to extract frame progress.
  /// Throttled to max 10 updates/second to prevent UI lag.
  static void parseFFmpegOutput(
    String output,
    int framerate,
    Function(int currentFrame)? setCurrentFrame,
  ) {
    final RegExp frameRegex = RegExp(r'frame=\s*(\d+)');
    final match = frameRegex.allMatches(output).isNotEmpty
        ? frameRegex.allMatches(output).last
        : null;
    if (match == null) return;

    final int videoFrame = int.parse(match.group(1)!);
    final int currFrame = videoFrame ~/ (30 / framerate);
    currentFrame = currFrame;

    // Throttle callback to prevent UI lag (max 10 updates/sec)
    if (setCurrentFrame != null) {
      final now = DateTime.now();
      if (now.difference(_lastProgressUpdate) >= _progressThrottleInterval) {
        _lastProgressUpdate = now;
        setCurrentFrame(currentFrame);
      }
    }
  }

  static Future<int> getStabilizedPhotoCount(int projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    return await DB.instance.getStabilizedPhotoCountByProjectID(
      projectId,
      projectOrientation,
    );
  }

  static Future<void> createGif(String videoOutputPath, int framerate) async {
    if (Platform.isWindows) return;
    final String gifPath = videoOutputPath.replaceAll(
      path.extension(videoOutputPath),
      ".gif",
    );
    await kit.FFmpegKit.execute('-i $videoOutputPath $gifPath');
  }

  static Future<bool> videoOutputSettingsChanged(
    int projectId,
    Map<String, dynamic>? newestVideo,
  ) async {
    if (newestVideo == null) return false;

    final bool newPhotos = newestVideo['photoCount'] !=
        await _getTotalPhotoCountByProjectId(projectId);
    if (newPhotos) {
      return true;
    }

    final framerateSetting = await _getFramerate(projectId);
    final bool framerateChanged = newestVideo['framerate'] != framerateSetting;
    if (framerateChanged) {
      return true;
    }

    final String watermarkEnabled = (await SettingsUtil.loadWatermarkSetting(
      projectId.toString(),
    ))
        .toString();
    if (newestVideo['watermarkEnabled'] != watermarkEnabled) {
      return true;
    }

    final String watermarkPos = (await DB.instance.getSettingValueByTitle(
      'watermark_position',
    ))
        .toLowerCase();
    if (newestVideo['watermarkPos'] != watermarkPos) {
      return true;
    }

    return false;
  }

  static Future<int> _getTotalPhotoCountByProjectId(int projectId) async {
    String projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    List<Map<String, dynamic>> allStabilizedPhotos = await DB.instance
        .getStabilizedPhotosByProjectID(projectId, projectOrientation);
    return allStabilizedPhotos.length;
  }

  static Future<int> _getFramerate(int projectId) async =>
      await SettingsUtil.loadFramerate(projectId.toString());

  static String getWatermarkFilter(
    double opacity,
    String watermarkPos,
    int offset,
  ) {
    String watermarkFilter =
        "[1:v]format=rgba,colorchannelmixer=aa=$opacity[watermark];[0:v][watermark]overlay=";

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
    LogService.instance.log("[VIDEO] Ensuring bundled ffmpeg is extracted...");
    final dir = await getApplicationSupportDirectory();
    final binDir = Directory(path.join(dir.path, 'bin'));
    if (!await binDir.exists()) {
      LogService.instance.log("[VIDEO] Creating bin directory: ${binDir.path}");
      await binDir.create(recursive: true);
    }
    final exePath = path.join(binDir.path, 'ffmpeg.exe');
    final markerPath = path.join(binDir.path, _winMarkerName);
    final exeExists = await File(exePath).exists();
    final markerExists = await File(markerPath).exists();
    final needsWrite = !exeExists || !markerExists;
    LogService.instance.log(
      "[VIDEO] ffmpeg.exe exists: $exeExists, marker exists: $markerExists, needs extraction: $needsWrite",
    );
    if (needsWrite) {
      LogService.instance.log(
        "[VIDEO] Extracting bundled ffmpeg from assets...",
      );
      try {
        final bytes = await rootBundle.load(_winFfmpegAssetPath);
        await File(
          exePath,
        ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        await File(markerPath).writeAsString('1', flush: true);
        LogService.instance.log(
          "[VIDEO] Bundled ffmpeg extracted successfully to: $exePath",
        );
      } catch (e) {
        LogService.instance.log("[VIDEO] ERROR extracting bundled ffmpeg: $e");
        rethrow;
      }
    }
    return exePath;
  }

  static Future<String> _findFfmpegOnPath() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    LogService.instance.log(
      "[VIDEO] Searching for ffmpeg on PATH using '$cmd'...",
    );
    try {
      final result = await Process.run(cmd, ['ffmpeg'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final p = line.trim();
          if (p.isNotEmpty && await File(p).exists()) {
            LogService.instance.log("[VIDEO] Found ffmpeg on PATH: $p");
            return p;
          }
        }
      }
      LogService.instance.log(
        "[VIDEO] ffmpeg not found on PATH (exit code: ${result.exitCode})",
      );
    } catch (e) {
      LogService.instance.log("[VIDEO] Error searching PATH for ffmpeg: $e");
    }
    return '';
  }

  static Future<String> _resolveFfmpegPath() async {
    LogService.instance.log("[VIDEO] Resolving ffmpeg path...");
    if (Platform.isWindows) {
      try {
        final bundled = await _ensureBundledFfmpeg();
        if (bundled.isNotEmpty && await File(bundled).exists()) {
          LogService.instance.log("[VIDEO] Using bundled ffmpeg: $bundled");
          return bundled;
        }
      } catch (e) {
        LogService.instance.log("[VIDEO] Failed to use bundled ffmpeg: $e");
      }
      final onPathWin = await _findFfmpegOnPath();
      if (onPathWin.isNotEmpty) {
        LogService.instance.log("[VIDEO] Using ffmpeg from PATH: $onPathWin");
        return onPathWin;
      }
      LogService.instance.log(
        "[VIDEO] WARNING: No ffmpeg found, falling back to 'ffmpeg' command",
      );
      return 'ffmpeg';
    } else {
      // Linux/macOS path resolution
      if (Platform.isLinux) {
        // In Flatpak, ffmpeg extension is mounted at /app/lib/ffmpeg/bin/ffmpeg
        // Check this first before falling back to PATH lookup
        const flatpakFfmpegExt = '/app/lib/ffmpeg/bin/ffmpeg';
        if (await File(flatpakFfmpegExt).exists()) {
          LogService.instance.log(
            "[VIDEO] Using Flatpak ffmpeg extension: $flatpakFfmpegExt",
          );
          return flatpakFfmpegExt;
        }

        // Also check /app/bin/ffmpeg (if bundled directly in Flatpak)
        const flatpakBundled = '/app/bin/ffmpeg';
        if (await File(flatpakBundled).exists()) {
          LogService.instance.log(
            "[VIDEO] Using Flatpak bundled ffmpeg: $flatpakBundled",
          );
          return flatpakBundled;
        }
      }

      // Standard PATH lookup for .deb installations and macOS
      final onPath = await _findFfmpegOnPath();
      if (onPath.isNotEmpty) return onPath;

      // Final fallback - rely on ffmpeg being in PATH
      LogService.instance.log(
        "[VIDEO] Using 'ffmpeg' command (assuming it's in PATH)",
      );
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
  static Future<Set<int>> _getValidTimestampsFromDB(
    int projectId,
    String orientation,
  ) async {
    final photos = await DB.instance.getStabilizedPhotosByProjectID(
      projectId,
      orientation,
    );
    final Set<int> timestamps = {};
    for (final photo in photos) {
      final ts = int.tryParse(photo['timestamp']?.toString() ?? '');
      if (ts != null) {
        timestamps.add(ts);
      }
    }
    return timestamps;
  }

  static Future<String> _buildConcatListFromDir(
    String framesDir,
    int fps, {
    int? projectId,
    String? orientation,
  }) async {
    LogService.instance.log(
      "[VIDEO] Building concat list from directory: $framesDir",
    );
    final dir = Directory(framesDir);
    if (!await dir.exists()) {
      LogService.instance.log(
        "[VIDEO] ERROR: Image directory does not exist: $framesDir",
      );
      throw FileSystemException('image directory not found', framesDir);
    }
    var files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .map((e) => e.path)
        .toList();

    // Validate files against database and clean up orphans
    if (projectId != null && orientation != null) {
      final validTimestamps = await _getValidTimestampsFromDB(
        projectId,
        orientation,
      );
      final int originalFileCount = files.length;
      final List<String> validFiles = [];
      final List<String> orphanedFiles = [];

      for (final filePath in files) {
        final filename = path.basenameWithoutExtension(filePath);
        final timestamp = int.tryParse(filename);
        if (timestamp != null && validTimestamps.contains(timestamp)) {
          validFiles.add(filePath);
        } else {
          orphanedFiles.add(filePath);
        }
      }

      // Delete orphaned files in parallel (batched to avoid overwhelming filesystem)
      if (orphanedFiles.isNotEmpty) {
        LogService.instance.log(
          "[VIDEO] Cleaning up ${orphanedFiles.length} orphaned files in parallel",
        );
        const int batchSize = 20;
        for (int i = 0; i < orphanedFiles.length; i += batchSize) {
          final batch = orphanedFiles.skip(i).take(batchSize);
          await Future.wait(
            batch.map((filePath) async {
              try {
                await File(filePath).delete();
              } catch (e) {
                LogService.instance.log(
                  "[VIDEO] Failed to delete orphaned file: $e",
                );
              }
            }),
          );
        }
      }

      final int orphansRemoved = originalFileCount - validFiles.length;
      files = validFiles;
      LogService.instance.log(
        "[VIDEO] After DB validation: ${files.length} valid files (removed $orphansRemoved orphans)",
      );
    }

    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));
    LogService.instance.log(
      "[VIDEO] Found ${files.length} PNG files for concat list",
    );

    // Log sample files for debugging
    if (files.length >= 2) {
      LogService.instance.log(
        "[VIDEO] Frame range: ${path.basename(files.first)} → ${path.basename(files.last)}",
      );
    }

    // Log first few files to compare with ASS file
    for (int i = 0; i < files.length && i < 5; i++) {
      LogService.instance.log(
        "[VIDEO] Concat frame $i: ${path.basename(files[i])}",
      );
    }

    if (files.isEmpty) {
      LogService.instance.log(
        "[VIDEO] ERROR: No .png files found in $framesDir",
      );
      throw StateError('no .png files found in $framesDir');
    }

    final tmpPath = path.join(
      Directory.systemTemp.path,
      'ffconcat_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    final f = File(tmpPath);
    final perFrame = 1.0 / fps;
    LogService.instance.log("[VIDEO] Frame duration: ${perFrame}s (fps: $fps)");

    final sb = StringBuffer();
    for (final fp in files) {
      final norm = fp.replaceAll(r'\', '/');
      final esc = norm.replaceAll("'", r"'\''");
      sb.writeln("file '$esc'");
      sb.writeln('duration $perFrame');
    }
    sb.writeln('duration $perFrame');

    await f.writeAsString(sb.toString(), flush: true);
    LogService.instance.log("[VIDEO] Concat list written to: $tmpPath");
    return tmpPath;
  }

  /// Determines H.264 profile and level based on resolution.
  /// H.264 Level 4.1 only supports up to ~1920x1080.
  /// Level 5.1 supports up to 4096x2304 (4K).
  /// Level 6.0+ supports up to 8192x4320 (8K).
  static (String, String) _getH264ProfileAndLevel(String resolution) {
    if (resolution == "8K" || _resolutionNeedsHevc(resolution)) {
      // 8K or custom resolution above 4K needs Level 6.0, High profile
      return ('high', '6.0');
    }
    if (resolution == "4K") {
      // 4K needs Level 5.1, High profile
      return ('high', '5.1');
    }
    // 1080p and below: Level 4.1, Main profile
    return ('main', '4.1');
  }

  static Future<bool> _encodeWindows({
    required String framesDir,
    required String outputPath,
    required int fps,
    required int projectId,
    required String orientation,
    void Function(String line)? onLog,
    void Function(int frameIndex)? onProgress,
    DateStampOverlayInfo? dateStampOverlay,
  }) async {
    LogService.instance.log("[VIDEO] _encodeWindows started");
    LogService.instance.log("[VIDEO] framesDir: $framesDir");
    LogService.instance.log("[VIDEO] outputPath: $outputPath");
    LogService.instance.log("[VIDEO] fps: $fps");
    if (dateStampOverlay != null) {
      LogService.instance.log(
          "[VIDEO] Date stamp overlay enabled with ${dateStampOverlay.pngInputPaths.length} PNGs");
    }

    final exe = await _resolveFfmpegPath();
    LogService.instance.log("[VIDEO] Resolved ffmpeg executable: $exe");

    // Verify ffmpeg exists
    final exeFile = File(exe);
    if (!exe.contains(path.separator) || !await exeFile.exists()) {
      LogService.instance.log(
        "[VIDEO] WARNING: ffmpeg path '$exe' may not exist as a file (might be a PATH command)",
      );
    }

    await _ensureOutDir(outputPath);
    final listPath = await _buildConcatListFromDir(
      framesDir,
      fps,
      projectId: projectId,
      orientation: orientation,
    );

    // Get resolution setting to determine H.264 profile/level
    final resolution = await SettingsUtil.loadVideoResolution(
      projectId.toString(),
    );
    final (profile, level) = _getH264ProfileAndLevel(resolution);
    final kbps = pickBitrateKbps(resolution);
    LogService.instance.log(
      "[VIDEO] Resolution: $resolution, Profile: $profile, Level: $level, Bitrate: ${kbps}k",
    );

    // Build FFmpeg arguments with overlay inputs if date stamp is enabled
    final args = <String>['-y'];

    // Add video frames input (input 0)
    args.addAll(['-f', 'concat', '-safe', '0', '-i', listPath]);

    // Add date stamp PNG inputs (inputs 1, 2, 3, ...)
    if (dateStampOverlay != null) {
      for (final pngPath in dateStampOverlay.pngInputPaths) {
        args.addAll(['-i', pngPath]);
      }
    }

    // Add filter (either filter_complex for overlay or nothing)
    if (dateStampOverlay != null) {
      args.addAll(['-filter_complex', dateStampOverlay.filterComplex]);
      args.addAll(['-map', '[${dateStampOverlay.outputMapLabel}]']);
    }

    // Video settings
    args.addAll([
      '-vsync',
      'cfr',
      '-r',
      '$fps',
      '-pix_fmt',
      'yuv420p',
      '-c:v',
      'libx264',
      '-profile:v',
      profile,
      '-level',
      level,
      '-b:v',
      '${kbps}k',
      '-maxrate',
      '${(kbps * 1.5).round()}k',
      '-bufsize',
      '${(kbps * 3).round()}k',
      '-movflags',
      '+faststart',
      outputPath,
    ]);

    LogService.instance.log("[VIDEO] ffmpeg arguments: ${args.join(' ')}");
    LogService.instance.log("[VIDEO] Starting ffmpeg process...");

    try {
      final proc = await Process.start(exe, args, runInShell: false);
      FFmpegProcessManager.instance.registerProcess(proc);
      LogService.instance.log(
        "[VIDEO] ffmpeg process started with PID: ${proc.pid}",
      );

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (onLog != null) onLog(line);
      });
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (onLog != null) onLog(line);
        final m = RegExp(r'frame=\s*(\d+)').firstMatch(line);
        if (m != null && onProgress != null) {
          final f = int.tryParse(m.group(1)!);
          if (f != null) onProgress(f);
        }
      });

      final code = await proc.exitCode;
      FFmpegProcessManager.instance.unregisterProcess();
      LogService.instance.log("[VIDEO] ffmpeg process exited with code: $code");

      try {
        await File(listPath).delete();
        LogService.instance.log("[VIDEO] Cleaned up concat list file");
      } catch (e) {
        LogService.instance.log("[VIDEO] Failed to clean up concat list: $e");
      }

      // Check if output file was created
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final size = await outputFile.length();
        LogService.instance.log(
          "[VIDEO] Output file created: $outputPath (${(size / 1024 / 1024).toStringAsFixed(2)} MB)",
        );
      } else {
        LogService.instance.log(
          "[VIDEO] WARNING: Output file was not created: $outputPath",
        );
      }

      return code == 0;
    } catch (e, stackTrace) {
      LogService.instance.log("[VIDEO] ERROR starting ffmpeg process: $e");
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return false;
    }
  }
}
