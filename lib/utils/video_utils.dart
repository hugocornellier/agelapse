import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/video_background.dart';
import '../models/video_codec.dart';
import '../services/ffmpeg_process_manager.dart';
import '../services/log_service.dart';
import '../services/video_compile_coordinator.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart' as kitlog;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/platform_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../utils/date_stamp_utils.dart';
import '../utils/capture_timezone.dart';
import '../services/custom_font_manager.dart';

import '../services/database_helper.dart';
import 'dir_utils.dart';
import 'gallery_utils.dart';

/// Data class for date stamp overlay filter info
class DateStampOverlayInfo {
  final String filterComplex;
  final List<String> pngInputPaths; // empty for drawtext mode
  final String? tempDir; // font temp dir if bundled font was extracted
  final String outputMapLabel;

  DateStampOverlayInfo({
    required this.filterComplex,
    this.pngInputPaths = const [],
    this.tempDir,
    required this.outputMapLabel,
  });
}

/// What an FFmpeg encode reported, used to decide whether its output can be
/// published.
@visibleForTesting
class EncodeResult {
  const EncodeResult({
    required this.exitCode,
    required this.cancelled,
    this.expectedFrames = 0,
    this.lastFrame = 0,
    this.suspectLine,
  });

  final int exitCode;
  final bool cancelled;

  /// Output frames the encode should produce; 0 if unknown.
  final int expectedFrames;

  /// Highest frame number FFmpeg reported; 0 if it reported none.
  final int lastFrame;

  /// First log line showing the output can't be trusted despite exit code 0.
  final String? suspectLine;

  /// Why [output] must not be published, or null if it can be.
  Future<String?> problemWith(File output) async {
    if (exitCode != 0) return 'FFmpeg exited with $exitCode';
    if (suspectLine != null) return 'FFmpeg reported: $suspectLine';
    if (!await output.exists() || await output.length() == 0) {
      return 'no output file';
    }
    // The last progress line can trail the end slightly, and very short
    // encodes may not report a count at all.
    if (expectedFrames >= 30 &&
        lastFrame > 0 &&
        lastFrame < expectedFrames * 0.9) {
      return 'encoded $lastFrame of $expectedFrames frames';
    }
    return null;
  }
}

/// Watches an encode's FFmpeg output for the frame count and for messages
/// that make the output untrustworthy even when FFmpeg exits with 0.
class _EncodeMonitor {
  _EncodeMonitor({required int inputFrames, required int inputFps})
    : expectedFrames = inputFps > 0
          ? inputFrames * VideoUtils.outputFps(inputFps) ~/ inputFps
          : 0;

  final int expectedFrames;
  int lastFrame = 0;
  String? suspectLine;

  static final RegExp _frame = RegExp(r'frame=\s*(\d+)');

  static const List<String> _suspectMessages = [
    // iOS invalidated the VideoToolbox session mid-encode (the app went to
    // the background) and FFmpeg restarted it; timestamps after a restart
    // have been seen going backwards.
    'VT session restarted',
    'Non-monotonous DTS',
    'Non-monotonic DTS',
    // A frame disappeared while the concat demuxer was reading it.
    'Impossible to open',
  ];

  void onLine(String line) {
    final match = _frame.firstMatch(line);
    if (match != null) {
      final frame = int.tryParse(match.group(1)!);
      if (frame != null && frame > lastFrame) lastFrame = frame;
    }
    if (suspectLine == null) {
      for (final message in _suspectMessages) {
        if (line.contains(message)) {
          suspectLine = line.trim();
          break;
        }
      }
    }
  }

  EncodeResult result({required int exitCode, required bool cancelled}) =>
      EncodeResult(
        exitCode: exitCode,
        cancelled: cancelled,
        expectedFrames: expectedFrames,
        lastFrame: lastFrame,
        suspectLine: suspectLine,
      );
}

/// Result of building an FFmpeg filter chain for video compilation.
class FilterChainResult {
  /// Raw filter_complex expression (without `-filter_complex` flag or quotes).
  final String? filterComplex;

  /// Stream label for `-map`, e.g. `[base]` or `[vout]`.
  /// Null when FFmpeg should auto-select the last output.
  final String? mapLabel;

  const FilterChainResult({this.filterComplex, this.mapLabel});

  bool get hasFilter => filterComplex != null && filterComplex!.isNotEmpty;
  bool get hasMap => mapLabel != null && mapLabel!.isNotEmpty;
}

class VideoUtils {
  static int currentFrame = 1;

  // Minimum output fps to ensure broad player/browser compatibility.
  // Videos below ~10fps can cause jittery playback in VLC, seeking issues
  // in QuickTime, and hardware decoder quirks in some browsers.
  static const int _minOutputFps = 10;

  /// Calculates the output fps for video encoding from [inputFps], the
  /// photos-per-second setting.
  ///
  /// At or above [_minOutputFps] every photo is one frame, so the output rate
  /// is the setting itself. Below it each photo is repeated to reach the
  /// floor, and the output rate is the smallest multiple of [inputFps] that
  /// is at least [_minOutputFps], so every photo gets the same whole number
  /// of frames: 3 photos/s becomes 12 fps with 4 frames per photo, not 10 fps
  /// with a 3-3-4 pattern.
  static int outputFps(int inputFps) {
    if (inputFps <= 0) return _minOutputFps;
    if (inputFps >= _minOutputFps) return inputFps;
    final int framesPerPhoto = (_minOutputFps + inputFps - 1) ~/ inputFps;
    return inputFps * framesPerPhoto;
  }

  /// Formats [seconds] for an FFmpeg `enable` expression, truncated (not
  /// rounded) to microseconds. Frame timestamps are exact multiples of 1/fps;
  /// rounding a boundary up past the frame it belongs to (2/3 s would become
  /// "0.666667") pushes that frame into the previous window.
  @visibleForTesting
  static String formatFilterSeconds(double seconds) =>
      ((seconds * 1e6).floor() / 1e6).toStringAsFixed(6);

  /// `enable` expression selecting the frames of photos [startFrame] through
  /// [endFrame] (inclusive) at [fps] photos per second.
  ///
  /// Each boundary sits half a microsecond before the exact photo start, so a
  /// frame whose timestamp comes out one rounding error below k/fps (FFmpeg
  /// computes it as pts * (1/fps) in doubles; 49 * (1/49) is 0.999...) still
  /// lands in its own window. The previous photo's frames are a full 1/fps
  /// earlier, so they never reach it.
  @visibleForTesting
  static String dateStampEnableExpr({
    required int startFrame,
    required int endFrame,
    required int fps,
  }) {
    const double margin = 0.5e-6;
    final double startSec = startFrame == 0 ? 0 : startFrame / fps - margin;
    final String start = formatFilterSeconds(startSec);
    final String end = formatFilterSeconds((endFrame + 1) / fps - margin);
    return 'gte(t\\,$start)*lt(t\\,$end)';
  }

  /// Calculates Gaussian blur sigma based on video height and optional
  /// [strength] multiplier.  Produces ~20 at 1080p, ~40 at 4K with the
  /// default strength of 1.0.  Clamped to [1, 100].
  @visibleForTesting
  static int blurSigma(int videoHeight, {double strength = 1.0}) =>
      (videoHeight / 54 * strength).round().clamp(1, 100);

  /// Builds the FFmpeg filter for blurred background.
  /// Splits input, scales up the background copy by [blurZoom]x (pushing
  /// transparent black edges off-screen), crops back to original size, blurs,
  /// then overlays the original frame (with alpha) on top.
  @visibleForTesting
  static String buildBlurFilter(
    int videoHeight, {
    double blurZoom = 3.0,
    double blurStrength = 1.0,
  }) {
    final sigma = blurSigma(videoHeight, strength: blurStrength);
    return '[0:v]split=2[orig][bg];'
        '[bg]format=rgb24,scale=iw*$blurZoom:ih*$blurZoom,crop=iw/$blurZoom:ih/$blurZoom,gblur=sigma=$sigma[blurred];'
        '[blurred][orig]overlay=0:0[base]';
  }

  // Throttling for progress updates (max 10 updates/sec = 100ms interval)
  static DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _progressThrottleInterval = Duration(milliseconds: 100);

  // Throttling for FFmpeg log output
  static int _logLineCount = 0;
  static const int _logEveryNthLine =
      5; // Log every 5th line for progress visibility

  // ETA tracking for video compilation
  static final Stopwatch _videoStopwatch = Stopwatch();
  static final Stopwatch _encodingStopwatch = Stopwatch();
  static int _totalFramesForEta = 0;

  /// Resets the video compilation stopwatch. Call before starting compilation.
  static void resetVideoStopwatch(int totalFrames) {
    _videoStopwatch.reset();
    _videoStopwatch.start();
    _encodingStopwatch.reset();
    _totalFramesForEta = totalFrames;
  }

  /// Stops the video compilation stopwatch. Call after compilation completes.
  static void stopVideoStopwatch() {
    _videoStopwatch.stop();
    _encodingStopwatch.stop();
  }

  /// Resets the progress throttle state. For testing only.
  @visibleForTesting
  static void resetProgressThrottle() {
    _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Extracts the output stream label from a filter string ending with `[label]`.
  /// Returns `'[label]'` or null if no label is found.
  static String? _extractOutputLabel(String filterString) {
    final match = RegExp(r'\[(\w+)\]$').firstMatch(filterString);
    return match != null ? '[${match.group(1)}]' : null;
  }

  /// Rewires [baseFilter] by substituting `[0:v]` with `[inputLabel]` and
  /// `[1:v]` with `[$wmIndex:v]`, as required when a color overlay shifts all
  /// input indices by 1.
  static String _composeWatermarkFilter(
    String baseFilter,
    String inputLabel,
    int wmIndex,
  ) => baseFilter
      .replaceFirst('[0:v]', inputLabel)
      .replaceFirst('[1:v]', '[$wmIndex:v]');

  /// Builds the FFmpeg filter_complex string from overlay components.
  ///
  /// Pure function; all async work (loading settings, generating PNGs) must
  /// be done by the caller before invoking this.
  @visibleForTesting
  static FilterChainResult buildFilterChain({
    required String? colorOverlayFilter,
    required DateStampOverlayInfo? dateStampOverlay,
    required String? watermarkFilterPart,
    required int watermarkInputIndex,
    required bool needsColorOverlay,
    required String pixelFormat,
  }) {
    final bool hasColor =
        colorOverlayFilter != null && colorOverlayFilter.isNotEmpty;
    final bool hasDateStamp = dateStampOverlay != null;
    final bool hasWatermark =
        watermarkFilterPart != null && watermarkFilterPart.isNotEmpty;

    String? filterComplex;
    String? mapLabel;

    if (hasColor && hasDateStamp && hasWatermark) {
      // Color overlay + date stamps + watermark
      final wmFilter = _composeWatermarkFilter(
        watermarkFilterPart,
        '[${dateStampOverlay.outputMapLabel}]',
        watermarkInputIndex,
      );
      filterComplex =
          '$colorOverlayFilter;${dateStampOverlay.filterComplex};$wmFilter';
      mapLabel = _extractOutputLabel(wmFilter);
    } else if (hasColor && hasDateStamp) {
      // Color overlay + date stamps
      filterComplex = '$colorOverlayFilter;${dateStampOverlay.filterComplex}';
      mapLabel = '[${dateStampOverlay.outputMapLabel}]';
    } else if (hasColor && hasWatermark) {
      // Color overlay + watermark
      final wmFilter = _composeWatermarkFilter(
        watermarkFilterPart,
        '[base]',
        watermarkInputIndex,
      );
      filterComplex = '$colorOverlayFilter;$wmFilter';
      mapLabel = _extractOutputLabel(wmFilter);
    } else if (hasColor) {
      // Color overlay only
      filterComplex = colorOverlayFilter;
      mapLabel = '[base]';
    } else if (hasDateStamp && hasWatermark) {
      // Date stamps + watermark
      final wmFilter = _composeWatermarkFilter(
        watermarkFilterPart,
        '[${dateStampOverlay.outputMapLabel}]',
        watermarkInputIndex,
      );
      filterComplex = '${dateStampOverlay.filterComplex};$wmFilter';
      mapLabel = _extractOutputLabel(wmFilter);
    } else if (hasDateStamp) {
      // Date stamps only
      filterComplex = dateStampOverlay.filterComplex;
      mapLabel = '[${dateStampOverlay.outputMapLabel}]';
    } else if (hasWatermark) {
      // Watermark only
      filterComplex = watermarkFilterPart;
      mapLabel = null;
    } else {
      // No filters
      return const FilterChainResult();
    }

    // Post-processing: when compositing onto solid background, append
    // format conversion so hardware encoders receive the correct pixel format.
    if (needsColorOverlay && mapLabel != null && mapLabel.isNotEmpty) {
      final labelMatch = RegExp(r'\[(\w+)\]').firstMatch(mapLabel);
      if (labelMatch != null) {
        final currentLabel = labelMatch.group(1)!;
        filterComplex =
            '$filterComplex;[$currentLabel]format=$pixelFormat[vout]';
        mapLabel = '[vout]';
      }
    }

    return FilterChainResult(filterComplex: filterComplex, mapLabel: mapLabel);
  }

  /// Calculates the ETA for video compilation based on frames processed.
  /// Returns a formatted string like "2m 30s" or null if not enough data.
  static String? calculateVideoEta(int framesProcessed) {
    if (framesProcessed <= 0 || _totalFramesForEta <= 0) return null;
    if (!_videoStopwatch.isRunning) return null;
    if (!_encodingStopwatch.isRunning) _encodingStopwatch.start();

    final elapsedMs = _encodingStopwatch.elapsedMilliseconds;
    if (elapsedMs < 200 || framesProcessed < 3) {
      return null; // Wait for at least 200ms of encoding data AND at least 3 frames
    }

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

  /// Generate date stamp overlay info using FFmpeg's drawtext filter.
  /// Returns DateStampOverlayInfo with a single drawtext filter string and the
  /// frame→date map (for embedding file_packet_meta in the concat list), or
  /// null if date stamps are disabled.
  static Future<DateStampOverlayInfo?> _generateDateStampOverlay({
    required int projectId,
    required String framesDir,
    required String orientation,
    required int videoWidth,
    required int videoHeight,
    required int fps,
    String videoInputLabel = '0',
    int inputIndexOffset = 0,
  }) async {
    if (fps <= 0) {
      LogService.instance.log("[VIDEO] ERROR: fps must be > 0, got $fps");
      return null;
    }
    LogService.instance.log(
      "[VIDEO] _generateDateStampOverlay started for project $projectId",
    );
    final projectIdStr = projectId.toString();

    // Check if date stamp is enabled
    final dateStampEnabled = await SettingsUtil.loadExportDateStampEnabled(
      projectIdStr,
    );
    if (!dateStampEnabled) {
      LogService.instance.log("[VIDEO] Date stamp disabled, skipping overlay");
      return null;
    }

    // Load date stamp settings
    final dateFormat = await SettingsUtil.loadExportDateStampFormat(
      projectIdStr,
    );
    final datePosition = await SettingsUtil.loadExportDateStampPosition(
      projectIdStr,
    );
    final dateSize = await SettingsUtil.loadExportDateStampSize(projectIdStr);
    final gallerySize = await SettingsUtil.loadGalleryDateStampSize(
      projectIdStr,
    );
    final resolvedSize = DateStampUtils.resolveExportSize(
      dateSize,
      gallerySize,
    );
    final exportFont = await SettingsUtil.loadExportDateStampFont(projectIdStr);
    final galleryFont = await SettingsUtil.loadGalleryDateStampFont(
      projectIdStr,
    );
    final resolvedFont = DateStampUtils.resolveExportFont(
      exportFont,
      galleryFont,
    );
    LogService.instance.log(
      "[VIDEO] Date stamp settings: enabled=$dateStampEnabled, format=$dateFormat, "
      "position=$datePosition, size=$resolvedSize, font=$resolvedFont",
    );

    // Load watermark settings for collision avoidance
    final watermarkEnabled = await SettingsUtil.loadWatermarkSetting(
      projectIdStr,
    );
    final String? watermarkPos = watermarkEnabled
        ? (await DB.instance.getSettingValueByTitle(
            'watermark_position',
          )).toLowerCase()
        : null;

    // Get list of PNG files
    final allFiles = await _listSortedPngFiles(Directory(framesDir));
    if (allFiles == null) {
      LogService.instance.log(
        "[VIDEO] No PNG files found in $framesDir, skipping date stamp overlay",
      );
      return null;
    }

    // Filter to only include files that exist in the database (same as concat list)
    final validTimestamps = await _getValidTimestampsFromDB(
      projectId,
      orientation,
    );
    final files = allFiles.where((filePath) {
      final filename = path.basenameWithoutExtension(filePath);
      final timestamp = int.tryParse(filename);
      return timestamp != null && validTimestamps.contains(timestamp);
    }).toList();
    LogService.instance.log(
      "[VIDEO] Date stamp frames: ${allFiles.length} total, ${files.length} valid",
    );

    if (files.isEmpty) {
      LogService.instance.log(
        "[VIDEO] No valid frames after DB filter, skipping date stamp overlay",
      );
      return null;
    }

    // Load timezone offsets for accurate date stamps
    final captureOffsetMap = await CaptureTimezone.loadOffsetsForFiles(
      files,
      projectId,
    );

    // Build list of dates for each frame
    final List<String> frameDates = [];
    for (final filePath in files) {
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
    }

    // Group consecutive frames with the same date to minimize filter count
    final List<({String date, int startFrame, int endFrame})> dateRanges = [];
    String? currentDate;
    int rangeStart = 0;
    for (int i = 0; i < frameDates.length; i++) {
      if (frameDates[i] != currentDate) {
        if (currentDate != null && currentDate.isNotEmpty) {
          dateRanges.add((
            date: currentDate,
            startFrame: rangeStart,
            endFrame: i - 1,
          ));
        }
        currentDate = frameDates[i];
        rangeStart = i;
      }
    }
    if (currentDate != null && currentDate.isNotEmpty) {
      dateRanges.add((
        date: currentDate,
        startFrame: rangeStart,
        endFrame: frameDates.length - 1,
      ));
    }

    LogService.instance.log(
      "[VIDEO] Date stamp: ${dateRanges.length} date ranges from ${frameDates.length} frames",
    );

    if (dateRanges.isEmpty) {
      LogService.instance.log(
        "[VIDEO] No date ranges generated, skipping date stamp overlay",
      );
      return null;
    }

    // Resolve font file path on disk for FFmpeg's drawtext filter
    final fontResolution = await _resolveFontFilePath(resolvedFont);
    if (fontResolution == null) {
      LogService.instance.log(
        "[VIDEO] Could not resolve font file path for $resolvedFont, skipping date stamp overlay",
      );
      return null;
    }
    final (fontFilePath, fontTempDir) = fontResolution;
    LogService.instance.log("[VIDEO] Resolved font file: $fontFilePath");

    // Calculate margins
    final (marginSettingH, marginSettingV) =
        await SettingsUtil.loadResolvedMargin(projectIdStr);
    int marginV = (videoHeight * marginSettingV / 100).round();
    int marginH = (videoWidth * marginSettingH / 100).round();

    // Check for watermark collision and adjust margin
    final bool sameCornerAsWatermark =
        watermarkPos != null && datePosition.toLowerCase() == watermarkPos;
    if (sameCornerAsWatermark) {
      marginV += (videoHeight * 0.05).round();
    }

    // Calculate font size
    final int fontSize = (videoHeight * resolvedSize / 100)
        .clamp(12, 200)
        .round();

    // Calculate position expressions
    String xExpr, yExpr;
    switch (datePosition.toLowerCase()) {
      case 'lower right':
        xExpr = 'W-tw-$marginH';
        yExpr = 'H-th-$marginV';
        break;
      case 'lower left':
        xExpr = '$marginH';
        yExpr = 'H-th-$marginV';
        break;
      case 'upper right':
        xExpr = 'W-tw-$marginH';
        yExpr = '$marginV';
        break;
      case 'upper left':
        xExpr = '$marginH';
        yExpr = '$marginV';
        break;
      default:
        xExpr = 'W-tw-$marginH';
        yExpr = 'H-th-$marginV';
    }

    // Escape font path for FFmpeg filter option parsing:
    // 1. Convert Windows backslashes to forward slashes
    // 2. Escape colons with \: (colon is FFmpeg's filter option separator)
    // 3. Escape single quotes
    // In Dart: '\\:' produces the string \: which FFmpeg interprets as literal colon.
    final escapedFontPath = fontFilePath
        .replaceAll('\\', '/')
        .replaceAll(':', '\\:');

    // Build chained drawtext filters: one per date range with enable expressions.
    // Each drawtext renders text for its time window. This uses zero extra inputs
    // (unlike the old overlay approach) while correctly showing per-frame dates.
    final filterParts = <String>[];
    String currentLabel = videoInputLabel;

    for (int i = 0; i < dateRanges.length; i++) {
      final range = dateRanges[i];
      final enableExpr = dateStampEnableExpr(
        startFrame: range.startFrame,
        endFrame: range.endFrame,
        fps: fps,
      );

      // Escape the date text for FFmpeg filter option parsing.
      // Colons, single quotes, backslashes, and semicolons must be escaped.
      final escapedText = range.date
          .replaceAll('\\', '\\\\\\\\')
          .replaceAll("'", "'\\\\\\''")
          .replaceAll(':', '\\\\:')
          .replaceAll(';', '\\\\;');

      final nextLabel = 'dt$i';
      filterParts.add(
        '[$currentLabel]drawtext='
        "fontfile='$escapedFontPath'"
        ":text='$escapedText'"
        ':fontsize=$fontSize'
        ':fontcolor=white'
        ':shadowcolor=black@0.54'
        ':shadowx=1'
        ':shadowy=1'
        ':box=1'
        ':boxcolor=black@0.5'
        ':boxborderw=4'
        ':x=$xExpr'
        ':y=$yExpr'
        ":enable='$enableExpr'"
        '[$nextLabel]',
      );
      currentLabel = nextLabel;
    }

    final filterComplex = filterParts.join(';');

    LogService.instance.log(
      "[VIDEO] Date stamp using ${dateRanges.length} chained drawtext filters "
      "(font=$resolvedFont, size=$fontSize)",
    );
    LogService.instance.log(
      "[VIDEO] _generateDateStampOverlay complete. Filter length: ${filterComplex.length} chars",
    );

    return DateStampOverlayInfo(
      filterComplex: filterComplex,
      pngInputPaths: const [],
      tempDir: fontTempDir,
      outputMapLabel: currentLabel,
    );
  }

  /// Resolves a font family name to a file path on disk for FFmpeg's drawtext filter.
  /// For bundled fonts, extracts the asset to a temp directory.
  /// For custom fonts, returns the existing file path.
  /// Returns (filePath, tempDir) or null if the font cannot be resolved.
  /// tempDir is non-null only when a temp directory was created for the font file.
  static Future<(String, String?)?> _resolveFontFilePath(
    String fontFamily,
  ) async {
    const bundledFontAssets = {
      'Inter': 'assets/fonts/Inter/Inter-Medium.ttf',
      'Roboto': 'assets/fonts/Roboto/Roboto-Medium.ttf',
      'SourceSans3': 'assets/fonts/SourceSans3/SourceSans3-Medium.ttf',
      'Nunito': 'assets/fonts/Nunito/Nunito-Variable.ttf',
      'JetBrainsMono': 'assets/fonts/JetBrainsMono/JetBrainsMono-Medium.ttf',
    };

    if (bundledFontAssets.containsKey(fontFamily)) {
      final assetPath = bundledFontAssets[fontFamily]!;
      try {
        final bytes = await rootBundle.load(assetPath);
        final tempBase = (await getTemporaryDirectory()).path;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fontTempDir = path.join(tempBase, 'date_stamps_$timestamp');
        await Directory(fontTempDir).create(recursive: true);
        final fontFile = File(
          path.join(fontTempDir, 'agelapse_drawtext_font.ttf'),
        );
        await fontFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        return (fontFile.path, fontTempDir);
      } catch (e) {
        LogService.instance.log(
          '[VIDEO] Failed to extract bundled font $fontFamily: $e',
        );
        return null;
      }
    }

    // Custom font: get file path from CustomFontManager
    if (DateStampUtils.isCustomFont(fontFamily)) {
      final customFont = await CustomFontManager.instance
          .getCustomFontByFamilyName(fontFamily);
      if (customFont != null && customFont.filePath.isNotEmpty) {
        final file = File(customFont.filePath);
        if (await file.exists()) {
          return (customFont.filePath, null);
        }
      }
      LogService.instance.log(
        '[VIDEO] Custom font file not found for $fontFamily',
      );
      return null;
    }

    return null;
  }

  /// Lists all PNG files in [dir], sorted by numeric basename.
  /// Returns null if the directory doesn't exist, can't be read, or contains no PNGs.
  static Future<List<String>?> _listSortedPngFiles(Directory dir) async {
    try {
      if (!await dir.exists()) return null;
      final files = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
          .map((e) => e.path)
          .toList();
      if (files.isEmpty) return null;
      files.sort(GalleryUtils.compareByNumericBasename);
      return files;
    } catch (_) {
      return null;
    }
  }

  /// Loads the three core watermark settings shared by all encoding paths.
  static Future<({bool enabled, String pos, String filePath})>
  _loadWatermarkSettings(int projectId) async {
    final bool enabled = await SettingsUtil.loadWatermarkSetting(
      projectId.toString(),
    );
    final String pos = (await DB.instance.getSettingValueByTitle(
      'watermark_position',
    )).toLowerCase();
    final String filePath = await DirUtils.getWatermarkFilePath(projectId);
    return (enabled: enabled, pos: pos, filePath: filePath);
  }

  /// Builds the watermark filter string and returns the active file path,
  /// or returns nulls when the watermark is disabled / file is missing.
  static Future<({String? filterPart, String? filePath})> _resolveWatermark(
    int projectId,
    String pos,
    String filePath,
  ) async {
    if (!Utils.isImage(filePath) || !await File(filePath).exists()) {
      return (filterPart: null, filePath: null);
    }
    final String opacityVal = await DB.instance.getSettingValueByTitle(
      'watermark_opacity',
    );
    final double opacity = double.tryParse(opacityVal) ?? 0.8;
    return (
      filterPart: getWatermarkFilter(opacity, pos, 10),
      filePath: filePath,
    );
  }

  /// Deletes the temporary directory used for date stamp assets (font or PNGs).
  static Future<void> _cleanupDateStampTemp(
    DateStampOverlayInfo? overlay,
  ) async {
    if (overlay == null || overlay.tempDir == null) return;
    try {
      final tempDir = Directory(overlay.tempDir!);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      LogService.instance.log(
        "[VIDEO] Failed to clean up date stamp temp dir: $e",
      );
    }
  }

  /// Reads the PNG signature + IHDR chunk from [filePath].
  /// Returns `({width, height, bitDepth})` or null if the file is not a valid PNG.
  static Future<({int width, int height, int bitDepth})?> _readPngIhdr(
    String filePath,
  ) async {
    try {
      final raf = await File(filePath).open();
      final bytes = await raf.read(25);
      await raf.close();
      if (bytes.length < 25) return null;
      // Verify PNG signature (first 4 bytes of the 8-byte signature)
      if (bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        return null;
      }
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      final bitDepth = bytes[24];
      return (width: width, height: height, bitDepth: bitDepth);
    } catch (_) {
      return null;
    }
  }

  /// Get video dimensions from the first frame in a directory
  static Future<(int, int)?> _getFrameDimensions(String framesDir) async {
    final files = await _listSortedPngFiles(Directory(framesDir));
    if (files == null) return null;

    final ihdr = await _readPngIhdr(files.first);
    if (ihdr == null) return null;

    LogService.instance.log(
      "[VIDEO] Frame dimensions: ${ihdr.width}x${ihdr.height}",
    );
    return (ihdr.width, ihdr.height);
  }

  /// Check if any frames in [framesDir] have bit depth > 8.
  /// Reads the PNG IHDR chunk (byte offset 24) of the first frame.
  static Future<bool> _hasHighBitDepthFrames(String framesDir) async {
    final files = await _listSortedPngFiles(Directory(framesDir));
    if (files == null) return false;

    final ihdr = await _readPngIhdr(files.first);
    if (ihdr == null) return false;

    LogService.instance.log("[VIDEO] Frame bit depth: ${ihdr.bitDepth}");
    return ihdr.bitDepth > 8;
  }

  /// Get frame dimensions and high-bit-depth flag from the first frame in a
  /// directory, performing only a single directory listing and IHDR read.
  static Future<({int width, int height, bool highBitDepth})?> _getFrameInfo(
    String framesDir,
  ) async {
    final files = await _listSortedPngFiles(Directory(framesDir));
    if (files == null) return null;

    final ihdr = await _readPngIhdr(files.first);
    if (ihdr == null) return null;

    LogService.instance.log(
      "[VIDEO] Frame dimensions: ${ihdr.width}x${ihdr.height}, bit depth: ${ihdr.bitDepth}",
    );
    return (
      width: ihdr.width,
      height: ihdr.height,
      highBitDepth: ihdr.bitDepth > 8,
    );
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
  /// Returns true for 8K preset or custom resolutions with any dimension > 4096
  static bool _resolutionNeedsHevc(
    String resolution, {
    int? actualWidth,
    int? actualHeight,
  }) {
    // Check actual frame dimensions first (most accurate)
    if (actualWidth != null && actualHeight != null) {
      // VideoToolbox H.264 limit is ~4096 on any dimension
      if (actualWidth > 4096 || actualHeight > 4096) return true;
    }

    if (resolution == "8K") return true;
    if (resolution == "4K" || resolution == "1080p") return false;

    // Handle WIDTHxHEIGHT format (e.g., "1920x1080")
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      // Check if either dimension exceeds H.264 VideoToolbox limit
      return w > 4096 || h > 4096;
    }

    // Custom resolution: parse short side and estimate long side
    final shortSide = double.tryParse(resolution);
    if (shortSide != null) {
      // Estimate long side assuming 16:9 aspect ratio
      final estimatedLongSide = shortSide * (16 / 9);
      if (shortSide > 4096 || estimatedLongSide > 4096) return true;
    }

    return false;
  }

  /// Encodes [job]'s project into a private file next to the video, then
  /// publishes it over the video only if the encode finished cleanly and the
  /// job is still wanted. Until then the previous video is untouched.
  ///
  /// Runs inside [VideoCompileCoordinator]; use [compileVideo] or
  /// [createTimelapseFromProjectId] instead of calling this directly.
  ///
  /// [newVideoNeededAtStart] is the project's rebuild flag, read before any
  /// of the compile's inputs were loaded. It is cleared after publishing only
  /// if unchanged, so a request made during the compile survives it.
  static Future<CompileOutcome> createTimelapse(
    CompileJob job,
    framerate,
    totalPhotoCount,
    Function(int currentFrame)? setCurrentFrame, {
    required int newVideoNeededAtStart,
    String? orientation,
  }) async {
    final int projectId = job.projectId;
    String? privateOutputPath;
    try {
      LogService.instance.log(
        "[VIDEO] createTimelapse called: projectId: $projectId, framerate: $framerate, totalPhotoCount: $totalPhotoCount, job: ${job.id}",
      );
      LogService.instance.log(
        "[VIDEO] Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}",
      );

      String projectOrientation =
          orientation ??
          await SettingsUtil.loadProjectOrientation(projectId.toString());
      final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(
        projectId,
      );

      // Check if transparent background is enabled
      final String bgColor = await SettingsUtil.loadBackgroundColor(
        projectId.toString(),
      );
      final bool isTransparent = SettingsUtil.isTransparent(bgColor);
      if (isTransparent) {
        LogService.instance.log("[VIDEO] Transparent background enabled");
      }

      // Load codec and video background settings
      final VideoCodec userCodec = await SettingsUtil.loadVideoCodec(
        projectId.toString(),
      );
      final VideoBackground videoBg = isTransparent
          ? await SettingsUtil.loadVideoBackground(projectId.toString())
          : VideoBackground.solidColor(bgColor);

      // Determine if the OUTPUT video itself has alpha
      final bool videoHasAlpha = isTransparent && videoBg.keepTransparent;

      // Resolve effective codec: if transparent video, lock to platform codec
      final VideoCodec effectiveCodec = videoHasAlpha
          ? VideoCodec.defaultCodec(isTransparentVideo: true)
          : userCodec;

      // Whether transparent PNGs need compositing onto a solid color
      final bool needsColorOverlay =
          isTransparent && !videoHasAlpha && !videoBg.isBlurred;
      final bool needsBlurOverlay =
          isTransparent && !videoHasAlpha && videoBg.isBlurred;
      final bool needsBackgroundComposite =
          needsColorOverlay || needsBlurOverlay;

      LogService.instance.log(
        "[VIDEO] Codec: ${effectiveCodec.name}, videoHasAlpha: $videoHasAlpha, needsColorOverlay: $needsColorOverlay, needsBlurOverlay: $needsBlurOverlay",
      );

      final String videoOutputPath = await DirUtils.getVideoOutputPath(
        projectId,
        projectOrientation,
        codec: effectiveCodec,
      );
      // FFmpeg writes here; the result is moved over videoOutputPath only
      // once it is complete (see _finishEncode).
      privateOutputPath = privateOutputPathFor(videoOutputPath, job.id);
      LogService.instance.log("[VIDEO] orientation: $projectOrientation");
      LogService.instance.log("[VIDEO] stabilizedDirPath: $stabilizedDirPath");
      LogService.instance.log("[VIDEO] videoOutputPath: $videoOutputPath");
      LogService.instance.log("[VIDEO] encoding to: $privateOutputPath");

      // Check available disk space (fire-and-forget: informational only)
      try {
        final outputDir = Directory(path.dirname(videoOutputPath));
        if (await outputDir.exists()) {
          if (Platform.isWindows) {
            Process.run('wmic', [
                  'logicaldisk',
                  'where',
                  'DeviceID="${path.rootPrefix(videoOutputPath).replaceAll('\\', '')}"',
                  'get',
                  'FreeSpace',
                  '/value',
                ], runInShell: true)
                .then((result) {
                  LogService.instance.log(
                    "[VIDEO] Disk space check: ${result.stdout.toString().trim()}",
                  );
                })
                .catchError((e) {
                  LogService.instance.log(
                    "[VIDEO] Disk space check failed: $e",
                  );
                });
          } else if (Platform.isLinux || Platform.isMacOS) {
            // df works in both .deb and Flatpak (available in freedesktop runtime)
            Process.run('df', ['-h', videoOutputPath])
                .then((result) {
                  if (result.exitCode == 0) {
                    LogService.instance.log(
                      "[VIDEO] Disk space check:\n${result.stdout}",
                    );
                  } else {
                    LogService.instance.log(
                      "[VIDEO] Disk space check unavailable (exit ${result.exitCode})",
                    );
                  }
                })
                .catchError((dfError) {
                  LogService.instance.log(
                    "[VIDEO] Disk space check unavailable: $dfError",
                  );
                });
          }
        }
      } catch (e) {
        LogService.instance.log("[VIDEO] Could not check disk space: $e");
      }

      await DirUtils.createDirectoryIfNotExists(videoOutputPath);

      // Record the video this compile replaces, so a playback problem reported
      // later can be matched to the file that was on disk before.
      try {
        final existing = File(videoOutputPath);
        if (await existing.exists()) {
          final stat = await existing.stat();
          LogService.instance.log(
            "[VIDEO] Replacing existing video: ${stat.size} bytes, modified ${stat.modified.toIso8601String()}",
          );
        }
      } catch (_) {}

      final Directory dir = Directory(
        path.join(stabilizedDirPath, projectOrientation),
      );
      LogService.instance.log("[VIDEO] Source directory: ${dir.path}");

      // Check if directory exists
      if (!await dir.exists()) {
        LogService.instance.log(
          "[VIDEO] ERROR: Stabilized directory does not exist: ${dir.path}",
        );
        return CompileOutcome.failed;
      }

      final bool framerateIsDefault = await SettingsUtil.loadFramerateIsDefault(
        projectId.toString(),
      );
      if (framerateIsDefault) {
        framerate = await getOptimalFramerateFromStabPhotoCount(projectId);
        // Stored for the settings UI and change detection, without marking
        // it user-chosen: the next compile must be free to pick again.
        await DB.instance.setAutoFramerate(framerate, projectId.toString());
        LogService.instance.log("[VIDEO] Using optimal framerate: $framerate");
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final String platformName = Platform.isMacOS
            ? 'macOS'
            : 'Windows/Linux';
        LogService.instance.log("[VIDEO] Using $platformName encoding path");
        try {
          final String framesDir = path.join(
            stabilizedDirPath,
            projectOrientation,
          );

          // Get frame dimensions and bit depth for date stamp overlay
          final frameInfo = await _getFrameInfo(framesDir);
          if (frameInfo == null) {
            LogService.instance.log(
              "[VIDEO] ERROR: Could not get frame dimensions",
            );
            return CompileOutcome.failed;
          }
          final (videoWidth, videoHeight) = (frameInfo.width, frameInfo.height);

          // Input index offset: 0 normally, 1 when color overlay is present
          final int idxOffset = needsColorOverlay ? 1 : 0;

          final dateStampOverlay = await _generateDateStampOverlay(
            projectId: projectId,
            framesDir: framesDir,
            orientation: projectOrientation,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            fps: framerate,
            videoInputLabel: needsBackgroundComposite ? 'base' : '0',
            inputIndexOffset: idxOffset,
          );

          // Load watermark settings
          final wmSettings = await _loadWatermarkSettings(projectId);
          int wmInputIndex =
              1 + idxOffset + (dateStampOverlay?.pngInputPaths.length ?? 0);
          final wm = wmSettings.enabled
              ? await _resolveWatermark(
                  projectId,
                  wmSettings.pos,
                  wmSettings.filePath,
                )
              : (filterPart: null, filePath: null);

          // Platform-specific ffmpeg path resolution
          final String ffmpegExe;
          if (Platform.isMacOS) {
            final exeDir = path.dirname(Platform.resolvedExecutable);
            final resourcesDir = path.normalize(
              path.join(exeDir, '..', 'Resources'),
            );
            ffmpegExe = path.join(resourcesDir, 'ffmpeg');
          } else {
            ffmpegExe = await _resolveFfmpegPath();
            final exeFile = File(ffmpegExe);
            if (!ffmpegExe.contains(path.separator) ||
                !await exeFile.exists()) {
              LogService.instance.log(
                "[VIDEO] WARNING: ffmpeg path '$ffmpegExe' may not exist as a file (might be a PATH command)",
              );
            }
          }

          // Captured before encoding so the video record describes what was
          // actually encoded, even if settings change meanwhile.
          final String resolution = await SettingsUtil.loadVideoResolution(
            projectId.toString(),
          );

          final encode = await _encodeDesktop(
            job: job,
            ffmpegExe: ffmpegExe,
            isMacOS: Platform.isMacOS,
            framesDir: framesDir,
            outputPath: privateOutputPath,
            fps: framerate,
            projectId: projectId,
            orientation: projectOrientation,
            onLog: (line) => LogService.instance.log("[FFMPEG] $line"),
            onProgress: setCurrentFrame,
            dateStampOverlay: dateStampOverlay,
            effectiveCodec: effectiveCodec,
            videoHasAlpha: videoHasAlpha,
            needsColorOverlay: needsColorOverlay,
            needsBlurOverlay: needsBlurOverlay,
            videoBg: videoBg,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            watermarkFilterPart: wm.filterPart,
            watermarkFilePath: wm.filePath,
            watermarkInputIndex: wmInputIndex,
            knownHighBitDepth: frameInfo.highBitDepth,
          );

          await _cleanupDateStampTemp(dateStampOverlay);
          LogService.instance.log(
            "[VIDEO] _encodeDesktop exited with ${encode.exitCode}",
          );
          return await _finishEncode(
            job: job,
            encode: encode,
            privatePath: privateOutputPath,
            publishPath: videoOutputPath,
            newVideoNeededAtStart: newVideoNeededAtStart,
            addRecord: () => DB.instance.addVideo(
              projectId,
              resolution,
              wmSettings.enabled.toString(),
              wmSettings.pos,
              totalPhotoCount,
              framerate,
            ),
          );
        } catch (e, stackTrace) {
          LogService.instance.log(
            "[VIDEO] ERROR in $platformName encoding: $e",
          );
          LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
          return CompileOutcome.failed;
        }
      }

      final wmSettingsMobile = await _loadWatermarkSettings(projectId);

      final String framesDir = path.join(stabilizedDirPath, projectOrientation);

      // Get frame dimensions for date stamp overlay
      final dimensions = await _getFrameDimensions(framesDir);
      if (dimensions == null) {
        LogService.instance.log(
          "[VIDEO] ERROR: Could not get frame dimensions",
        );
        return CompileOutcome.failed;
      }
      final (videoWidth, videoHeight) = dimensions;
      LogService.instance.log(
        "[VIDEO] Frame dimensions: ${videoWidth}x$videoHeight",
      );

      // Generate date stamp overlay with PNG assets (if enabled)
      // When color overlay is present, video input shifts and indices offset by 1.
      final dateStampOverlay = await _generateDateStampOverlay(
        projectId: projectId,
        framesDir: framesDir,
        orientation: projectOrientation,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        fps: framerate,
        videoInputLabel: needsBackgroundComposite ? 'base' : '0',
        inputIndexOffset: needsColorOverlay ? 1 : 0,
      );
      LogService.instance.log(
        "[VIDEO] Date stamp overlay: ${dateStampOverlay != null ? 'drawtext enabled' : 'disabled'}",
      );

      // Input index offset: 0 normally, 1 when color overlay is present
      final int idxOffset = needsColorOverlay ? 1 : 0;

      // Build input arguments (video frames + date stamp PNGs + watermark)
      final dateStampInputs = dateStampOverlay != null
          ? '${dateStampOverlay.pngInputPaths.map((p) => '-i "$p"').join(' ')} '
          : "";

      // Build watermark input
      String watermarkInput = "";
      int watermarkInputIndex =
          1 + idxOffset + (dateStampOverlay?.pngInputPaths.length ?? 0);
      String? watermarkFilterPart;
      if (wmSettingsMobile.enabled) {
        final wm = await _resolveWatermark(
          projectId,
          wmSettingsMobile.pos,
          wmSettingsMobile.filePath,
        );
        if (wm.filePath != null) {
          watermarkInput = "-i \"${wm.filePath}\"";
          watermarkFilterPart = wm.filterPart;
        }
      }

      // Build color overlay filter prefix (transparent PNGs on solid video bg)
      // format= converts rgba overlay output to the codec's pixel format so
      // hardware encoders (e.g. h264_videotoolbox) don't receive unsupported frames.
      String backgroundFilter = "";
      if (needsColorOverlay && videoBg.solidColorHex != null) {
        // [0:v] = color source, [1:v] = concat frames → overlay → [base]
        backgroundFilter =
            "[0:v][1:v]overlay=shortest=1,format=${effectiveCodec.pixelFormat}[base]";
      } else if (needsBlurOverlay) {
        final blurZoom = await SettingsUtil.loadBlurZoom(projectId.toString());
        final blurStrength = await SettingsUtil.loadBlurStrength(
          projectId.toString(),
        );
        backgroundFilter = buildBlurFilter(
          videoHeight,
          blurZoom: blurZoom,
          blurStrength: blurStrength,
        );
      }

      // Build combined filter chain
      final filterResult = buildFilterChain(
        colorOverlayFilter: backgroundFilter.isNotEmpty
            ? backgroundFilter
            : null,
        dateStampOverlay: dateStampOverlay,
        watermarkFilterPart: watermarkFilterPart,
        watermarkInputIndex: watermarkInputIndex,
        needsColorOverlay: needsBackgroundComposite,
        pixelFormat: effectiveCodec.pixelFormat,
      );

      String filterArgs = filterResult.hasFilter
          ? '-filter_complex "${filterResult.filterComplex}"'
          : "";
      String mapArg = filterResult.hasMap
          ? '-map "${filterResult.mapLabel}"'
          : "";
      LogService.instance.log(
        "[VIDEO] Filter chain: hasFilter=${filterResult.hasFilter}, "
        "mapLabel=${filterResult.mapLabel}, "
        "filterLength=${filterResult.filterComplex?.length ?? 0}",
      );

      final String listPath = await _buildConcatListFromDir(
        framesDir,
        framerate,
        projectId: projectId,
        orientation: projectOrientation,
      );
      LogService.instance.log("[VIDEO] Concat list: $listPath");

      final resolution = await SettingsUtil.loadVideoResolution(
        projectId.toString(),
      );
      final kbps = pickBitrateKbps(resolution);

      // Check if resolution exceeds H.264 VideoToolbox limits (4096px on any dimension)
      // In that case, upgrade h264 -> hevc automatically
      VideoCodec finalCodec = effectiveCodec;
      if (isApple &&
          effectiveCodec == VideoCodec.h264 &&
          _resolutionNeedsHevc(
            resolution,
            actualWidth: videoWidth,
            actualHeight: videoHeight,
          )) {
        LogService.instance.log(
          "[VIDEO] 8K resolution detected, upgrading H.264 to HEVC (h264_videotoolbox doesn't support 8K)",
        );
        finalCodec = VideoCodec.hevc;
      }

      // Detect high-bit-depth source frames for 10-bit output
      final bool highBitDepth = await _hasHighBitDepthFrames(framesDir);

      // Use codec model for all encoding parameters
      final String vCodec = finalCodec.encoder;
      final String codecTag = finalCodec.codecTag;
      final String pixFmt = finalCodec.pixelFormatForSource(
        highBitDepth: highBitDepth,
      );
      final String rateControl;

      if (finalCodec == VideoCodec.vp9) {
        rateControl = "-b:v ${kbps}k -crf 30 -row-mt 1 -auto-alt-ref 0";
      } else if (finalCodec.usesBitrateControl) {
        rateControl =
            "-b:v ${kbps}k -maxrate ${(kbps * 1.5).round()}k -bufsize ${(kbps * 3).round()}k";
      } else {
        rateControl = ''; // ProRes doesn't use bitrate control
      }

      LogService.instance.log(
        "[VIDEO] Encoding config: codec=${finalCodec.displayName}, encoder=$vCodec, "
        "resolution=$resolution, bitrate=${kbps}k, pixFmt=$pixFmt, "
        "highBitDepth=$highBitDepth, rateControl=$rateControl",
      );

      // Build movflags
      final String movFlags = finalCodec.usesMovFlags
          ? '-movflags +faststart'
          : '';

      // For transparent videos with alpha output, ensure alpha channel is
      // preserved through the filter pipeline.
      // For all videos: always include a format filter when no filter_complex
      // is present; FFmpeg 6's concat demuxer can hit "Error reinitializing
      // filters" without one when frame metadata varies between segments.
      // It goes through -filter_complex rather than -vf: on FFmpeg 6.1 the
      // simple-graph path gives the first photo one frame too few below 10
      // photos/s (199 frames for 20 photos at 1 fps), the complex-graph path
      // gives it the full count.
      if (filterArgs.isEmpty) {
        filterArgs = '-filter_complex "[0:v]format=$pixFmt[v]"';
        mapArg = '-map "[v]"';
      }

      // Build the color source input (before concat) when needed
      final int outFps = outputFps(framerate);
      final String colorSourceInput =
          needsColorOverlay && videoBg.solidColorHex != null
          ? '-f lavfi -i "color=c=${videoBg.solidColorHex!.replaceFirst('#', '0x')}:s=${videoWidth}x$videoHeight:r=$outFps" '
          : '';

      // Input -r stamps each photo at an exact multiple of 1/framerate.
      // Without it the concat demuxer rounds the list's durations to the PNG
      // stream's 1/25 s clock, which repeats or drops photos above 25 fps,
      // makes the pacing uneven below 10, and lands frames in the wrong
      // date-stamp window. -fps_mode is the current spelling of -vsync,
      // which FFmpeg 9 no longer accepts.
      String ffmpegCommand =
          "-y "
          "$colorSourceInput"
          "-r $framerate -f concat -safe 0 "
          "-i \"$listPath\" "
          "$dateStampInputs"
          "$watermarkInput "
          "-fps_mode cfr -r $outFps "
          "$filterArgs $mapArg "
          "-c:v $vCodec $rateControl "
          "${videoHasAlpha ? '' : '-g 240 '}$movFlags $codecTag "
          "-color_primaries bt709 -color_trc bt709 -colorspace bt709 "
          "-pix_fmt $pixFmt "
          "\"$privateOutputPath\"";

      LogService.instance.log('[VIDEO] DEBUG full command=$ffmpegCommand');
      LogService.instance.log(
        "[VIDEO] Command stats: ${ffmpegCommand.length} chars, "
        "filter_complex=${filterResult.filterComplex?.length ?? 0} chars",
      );

      try {
        LogService.instance.log(
          "[VIDEO] Using mobile (FFmpegKit) encoding path",
        );

        // Reset throttle counters for new compilation
        _logLineCount = 0;
        _lastProgressUpdate = DateTime.now();

        final monitor = _EncodeMonitor(
          inputFrames: await _countConcatFrames(listPath),
          inputFps: framerate,
        );

        // Verify date stamp PNGs still exist on disk before FFmpeg reads them.
        // Android can evict temp/cache files at any time.
        if (dateStampOverlay != null) {
          int missing = 0;
          for (final pngPath in dateStampOverlay.pngInputPaths) {
            if (!await File(pngPath).exists()) {
              missing++;
              LogService.instance.log(
                "[VIDEO] WARNING: Date stamp PNG missing: $pngPath",
              );
            }
          }
          LogService.instance.log(
            "[VIDEO] Date stamp PNG check: "
            "${dateStampOverlay.pngInputPaths.length - missing}/${dateStampOverlay.pngInputPaths.length} exist on disk",
          );
        }

        LogService.instance.log(
          "[VIDEO] Executing ffmpeg command: $ffmpegCommand",
        );
        await LogService.instance.flush();

        // This session's logs only: progress from another session must never
        // reach this compile's callback.
        final run = FFmpegProcessManager.instance.startSession(
          ffmpegCommand,
          onLog: (kitlog.Log log) {
            final String output = log.getMessage();
            monitor.onLine(output);
            // Always parse for progress (internally throttled)
            parseFFmpegOutput(output, framerate, setCurrentFrame);
            // Throttle logging to reduce UI thread load
            _logLineCount++;
            // Log every line for the first 20 lines (catch early native crashes),
            // then every 5th line after that. Warnings and errors always.
            final bool shouldLog =
                _logLineCount <= 20 ||
                _logLineCount % _logEveryNthLine == 0 ||
                log.getLevel() <= _avLogWarning;
            if (shouldLog) {
              LogService.instance.log("[FFMPEG] $output");
              // Flush early lines so we know FFmpeg started, then periodically
              // so crash logs survive. Fire-and-forget (callback is sync).
              if (_logLineCount <= 20 || _logLineCount % 50 == 0) {
                LogService.instance.flush();
              }
            }
          },
        );
        void cancelRun() => unawaited(run.cancel());
        job.token.addListener(cancelRun);
        final int exitCode;
        try {
          exitCode = await run.exitCode;
        } finally {
          job.token.removeListener(cancelRun);
        }
        LogService.instance.log("[VIDEO] FFmpegKit return code: $exitCode");

        await _cleanupDateStampTemp(dateStampOverlay);
        await _deleteQuietly(listPath);

        return await _finishEncode(
          job: job,
          encode: monitor.result(
            exitCode: exitCode,
            cancelled: run.cancelRequested,
          ),
          privatePath: privateOutputPath,
          publishPath: videoOutputPath,
          newVideoNeededAtStart: newVideoNeededAtStart,
          addRecord: () => DB.instance.addVideo(
            projectId,
            resolution,
            wmSettingsMobile.enabled.toString(),
            wmSettingsMobile.pos,
            totalPhotoCount,
            framerate,
          ),
        );
      } catch (e, stackTrace) {
        LogService.instance.log("[VIDEO] ERROR in video compilation: $e");
        LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
        await _cleanupDateStampTemp(dateStampOverlay);
        await _deleteQuietly(listPath);
        return CompileOutcome.failed;
      }
    } catch (e, stackTrace) {
      LogService.instance.log("[VIDEO] ERROR in createTimelapse: $e");
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return CompileOutcome.failed;
    } finally {
      // Anything not published (cancelled, failed, rejected) is discarded.
      // After a publish the private file has already been renamed away.
      if (privateOutputPath != null) await _deleteQuietly(privateOutputPath);
    }
  }

  /// FFmpeg's AV_LOG_WARNING level; lower values are more severe.
  static const int _avLogWarning = 24;

  static const String _privateOutputPrefix = '.agelapse-job';

  /// Where job [jobId] encodes before its result is published over
  /// [videoOutputPath]. Same folder, so publishing is a same-volume rename.
  static String privateOutputPathFor(String videoOutputPath, int jobId) =>
      path.join(
        path.dirname(videoOutputPath),
        '$_privateOutputPrefix$jobId${path.extension(videoOutputPath)}',
      );

  /// Decides what to do with a finished encode: discard it (cancelled or
  /// failed) or publish it over the project's video and record it.
  static Future<CompileOutcome> _finishEncode({
    required CompileJob job,
    required EncodeResult encode,
    required String privatePath,
    required String publishPath,
    required int newVideoNeededAtStart,
    required Future<void> Function() addRecord,
  }) async {
    if (encode.cancelled || job.isCancelled) {
      LogService.instance.log(
        "[VIDEO] Job ${job.id} was cancelled; discarding its output",
      );
      return CompileOutcome.cancelled;
    }
    final String? problem = await encode.problemWith(File(privatePath));
    if (problem != null) {
      LogService.instance.log(
        "[VIDEO] Job ${job.id} rejected ($problem); keeping the previous video",
      );
      return CompileOutcome.failed;
    }
    if (!await _publishVideo(job, privatePath, publishPath)) {
      return job.isCancelled ? CompileOutcome.cancelled : CompileOutcome.failed;
    }
    await addRecord();
    if (newVideoNeededAtStart != 0) {
      await DB.instance.clearNewVideoNeededIfUnchanged(
        job.projectId,
        newVideoNeededAtStart,
      );
    }
    LogService.instance.log(
      "[VIDEO] Job ${job.id} published $publishPath, record added to database",
    );
    return CompileOutcome.published;
  }

  /// Moves a checked encode over the project's video. Returns false, leaving
  /// the previous video in place, if the job was cancelled, the project was
  /// deleted, or the move fails.
  static Future<bool> _publishVideo(
    CompileJob job,
    String privatePath,
    String publishPath,
  ) async {
    if (job.isCancelled) return false;
    if (await DB.instance.getProjectNameById(job.projectId) == null) {
      LogService.instance.log(
        "[VIDEO] Project ${job.projectId} no longer exists; not publishing job ${job.id}",
      );
      return false;
    }
    // A rename replaces the old file in one step. On Windows it can fail
    // while a player still holds the old file, so retry briefly.
    const retryDelays = [
      Duration(milliseconds: 200),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
    ];
    for (var attempt = 0; ; attempt++) {
      if (job.isCancelled) return false;
      try {
        await File(privatePath).rename(publishPath);
        break;
      } on FileSystemException catch (e) {
        if (attempt >= retryDelays.length) {
          LogService.instance.log(
            "[VIDEO] Could not publish job ${job.id}: $e; keeping the previous video",
          );
          return false;
        }
        await Future.delayed(retryDelays[attempt]);
      }
    }
    // Only now that the new video is in place: remove the project's video in
    // other containers (e.g. the .mp4 after switching to ProRes .mov).
    final videoDir = path.dirname(publishPath);
    final currentExt = path.extension(publishPath);
    for (final ext in ['.mp4', '.mov', '.webm']) {
      if (ext == currentExt) continue;
      final oldFile = File(path.join(videoDir, 'agelapse$ext'));
      if (await oldFile.exists()) {
        LogService.instance.log(
          "[VIDEO] Removing old video file: ${oldFile.path}",
        );
        await _deleteQuietly(oldFile.path);
      }
    }
    return true;
  }

  /// Deletes encode output left behind by compiles that never finished (the
  /// app was killed or suspended mid-encode). Only call while no compile is
  /// running.
  static Future<void> deleteAbandonedOutputs(int projectId) async {
    final videosDir = Directory(
      path.join(await DirUtils.getProjectDirPath(projectId), 'videos'),
    );
    if (!await videosDir.exists()) return;
    await for (final entity in videosDir.list(recursive: true)) {
      if (entity is File &&
          path.basename(entity.path).startsWith(_privateOutputPrefix)) {
        LogService.instance.log(
          "[VIDEO] Deleting abandoned encode output: ${entity.path}",
        );
        await _deleteQuietly(entity.path);
      }
    }
  }

  static Future<int> _countConcatFrames(String listPath) async {
    try {
      final lines = await File(listPath).readAsLines();
      return lines.where((line) => line.startsWith('file ')).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _deleteQuietly(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      LogService.instance.log("[VIDEO] Could not delete $filePath: $e");
    }
  }

  /// Compiles [projectId]'s video and returns true if a new video was
  /// published. Serialized with every other compile; see [compileVideo].
  static Future<bool> createTimelapseFromProjectId(
    int projectId,
    Function(int currentFrame)? setCurrentFrame,
  ) async {
    final outcome = await compileVideo(
      projectId,
      setCurrentFrame,
      reason: 'createTimelapseFromProjectId',
    );
    return outcome == CompileOutcome.published;
  }

  /// Compiles [projectId]'s video through [VideoCompileCoordinator]: any
  /// running compile is cancelled and awaited first, and the result only
  /// replaces the current video if it finishes cleanly.
  static Future<CompileOutcome> compileVideo(
    int projectId,
    Function(int currentFrame)? setCurrentFrame, {
    required String reason,
  }) {
    LogService.instance.log(
      "[VIDEO] compileVideo called: projectId: $projectId, reason: $reason",
    );
    return VideoCompileCoordinator.instance.compile(
      projectId,
      onProgress: setCurrentFrame == null
          ? null
          : (frame) => setCurrentFrame(frame),
      reason: reason,
    );
  }

  /// Runs one compile for [VideoCompileCoordinator].
  static Future<CompileOutcome> compileForJob(
    CompileJob job,
    void Function(int frame)? setCurrentFrame,
  ) async {
    final int projectId = job.projectId;
    try {
      // First, so a rebuild request made while inputs load isn't cleared.
      final int newVideoNeededAtStart =
          await DB.instance.getNewVideoNeeded(projectId) ?? 0;
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
        return CompileOutcome.failed;
      }

      final int framerate = await SettingsUtil.loadFramerate(
        projectId.toString(),
      );
      LogService.instance.log("[VIDEO] Loaded framerate: $framerate");

      if (job.isCancelled) return CompileOutcome.cancelled;
      return await createTimelapse(
        job,
        framerate,
        stabilizedPhotos.length,
        setCurrentFrame,
        newVideoNeededAtStart: newVideoNeededAtStart,
        orientation: projectOrientation,
      );
    } catch (e, stackTrace) {
      LogService.instance.log("[VIDEO] ERROR in compileForJob: $e");
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return CompileOutcome.failed;
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
    final matches = frameRegex.allMatches(output);
    final match = matches.isNotEmpty ? matches.last : null;
    if (match == null) return;

    final int videoFrame = int.parse(match.group(1)!);
    final int outFps = outputFps(framerate);
    final int currFrame = (videoFrame * framerate) ~/ outFps;
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

  static Future<bool> videoOutputSettingsChanged(
    int projectId,
    Map<String, dynamic>? newestVideo,
  ) async {
    if (newestVideo == null) return false;

    final bool newPhotos =
        newestVideo['photoCount'] !=
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
    )).toString();
    if (newestVideo['watermarkEnabled'] != watermarkEnabled) {
      return true;
    }

    final String watermarkPos = (await DB.instance.getSettingValueByTitle(
      'watermark_position',
    )).toLowerCase();
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
  static const List<String> _winFfmpegDlls = [
    'libgcc_s_seh-1.dll',
    'libwinpthread-1.dll',
  ];

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
        // Extract required DLLs alongside ffmpeg.exe.
        for (final dll in _winFfmpegDlls) {
          try {
            final dllBytes = await rootBundle.load(
              'assets/ffmpeg/windows/$dll',
            );
            await File(
              path.join(binDir.path, dll),
            ).writeAsBytes(dllBytes.buffer.asUint8List(), flush: true);
            LogService.instance.log("[VIDEO] Extracted DLL: $dll");
          } catch (e) {
            LogService.instance.log(
              "[VIDEO] WARNING: Could not extract $dll: $e",
            );
          }
        }
        await File(markerPath).writeAsString('2', flush: true);
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

      // Final fallback; rely on ffmpeg being in PATH
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
    if (fps <= 0) {
      throw ArgumentError('fps must be positive, got $fps');
    }
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

    files.sort(GalleryUtils.compareByNumericBasename);
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
    // The durations record the intended pacing and keep the list usable on
    // its own. The encode passes input -r, which regenerates the timestamps
    // at exact multiples of 1/fps; the concat demuxer alone rounds these
    // durations to the PNG stream's 1/25 s clock.
    final String perFrame = (1.0 / fps).toStringAsFixed(6);
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

  static Future<EncodeResult> _encodeDesktop({
    required CompileJob job,
    required String ffmpegExe,
    required bool isMacOS,
    required String framesDir,
    required String outputPath,
    required int fps,
    required int projectId,
    required String orientation,
    void Function(String line)? onLog,
    void Function(int frameIndex)? onProgress,
    DateStampOverlayInfo? dateStampOverlay,
    required VideoCodec effectiveCodec,
    required bool videoHasAlpha,
    bool needsColorOverlay = false,
    bool needsBlurOverlay = false,
    VideoBackground? videoBg,
    int? videoWidth,
    int? videoHeight,
    String? watermarkFilterPart,
    String? watermarkFilePath,
    int watermarkInputIndex = 0,
    bool? knownHighBitDepth,
  }) async {
    LogService.instance.log(
      "[VIDEO] _encodeDesktop started (${isMacOS ? 'macOS' : 'Windows/Linux'})",
    );
    LogService.instance.log("[VIDEO] framesDir: $framesDir");
    LogService.instance.log("[VIDEO] outputPath: $outputPath");
    LogService.instance.log("[VIDEO] fps: $fps");
    if (dateStampOverlay != null) {
      LogService.instance.log("[VIDEO] Date stamp overlay enabled (drawtext)");
    }

    LogService.instance.log("[VIDEO] Resolved ffmpeg executable: $ffmpegExe");

    await _ensureOutDir(outputPath);
    final listPath = await _buildConcatListFromDir(
      framesDir,
      fps,
      projectId: projectId,
      orientation: orientation,
    );

    // Get resolution setting
    final resolution = await SettingsUtil.loadVideoResolution(
      projectId.toString(),
    );
    final kbps = pickBitrateKbps(resolution);

    // macOS-specific: auto-upgrade H.264 to HEVC for 8K (VideoToolbox limit)
    VideoCodec codec = effectiveCodec;
    if (isMacOS &&
        effectiveCodec == VideoCodec.h264 &&
        videoWidth != null &&
        videoHeight != null &&
        _resolutionNeedsHevc(
          resolution,
          actualWidth: videoWidth,
          actualHeight: videoHeight,
        )) {
      LogService.instance.log(
        "[VIDEO] 8K resolution detected, upgrading H.264 to HEVC (h264_videotoolbox doesn't support 8K)",
      );
      codec = VideoCodec.hevc;
    }

    LogService.instance.log(
      "[VIDEO] Resolution: $resolution, Codec: ${codec.name}, Bitrate: ${kbps}k",
    );

    // Build FFmpeg arguments
    final args = <String>['-y'];

    // Add color source input (input 0) when compositing transparent PNGs onto solid bg
    if (needsColorOverlay &&
        videoBg != null &&
        videoBg.solidColorHex != null &&
        videoWidth != null &&
        videoHeight != null) {
      final String hex = videoBg.solidColorHex!.replaceFirst('#', '0x');
      final int outFps = outputFps(fps);
      args.addAll([
        '-f',
        'lavfi',
        '-i',
        'color=c=$hex:s=${videoWidth}x$videoHeight:r=$outFps',
      ]);
    }

    // Add video frames input (input 0 normally, input 1 with color overlay).
    // Input -r stamps each photo at an exact multiple of 1/fps; see the
    // mobile command in createTimelapse for why that matters.
    args.addAll(['-r', '$fps', '-f', 'concat', '-safe', '0', '-i', listPath]);

    // Add date stamp PNG inputs
    if (dateStampOverlay != null) {
      for (final pngPath in dateStampOverlay.pngInputPaths) {
        args.addAll(['-i', pngPath]);
      }
    }

    // Add watermark input
    if (watermarkFilePath != null) {
      args.addAll(['-i', watermarkFilePath]);
    }

    // Build filter_complex via shared filter chain builder
    final String? backgroundFilterStr;
    if (needsColorOverlay) {
      backgroundFilterStr =
          '[0:v][1:v]overlay=shortest=1,format=${codec.pixelFormat}[base]';
    } else if (needsBlurOverlay && videoHeight != null) {
      final blurZoom = await SettingsUtil.loadBlurZoom(projectId.toString());
      final blurStrength = await SettingsUtil.loadBlurStrength(
        projectId.toString(),
      );
      backgroundFilterStr = buildBlurFilter(
        videoHeight,
        blurZoom: blurZoom,
        blurStrength: blurStrength,
      );
    } else {
      backgroundFilterStr = null;
    }
    final filterResult = buildFilterChain(
      colorOverlayFilter: backgroundFilterStr,
      dateStampOverlay: dateStampOverlay,
      watermarkFilterPart: watermarkFilterPart,
      watermarkInputIndex: watermarkInputIndex,
      needsColorOverlay: needsColorOverlay || needsBlurOverlay,
      pixelFormat: codec.pixelFormat,
    );
    if (filterResult.hasFilter) {
      args.addAll(['-filter_complex', filterResult.filterComplex!]);
    }
    if (filterResult.hasMap) {
      args.addAll(['-map', filterResult.mapLabel!]);
    }

    // Detect high-bit-depth source frames for 10-bit output
    final bool highBitDepth =
        knownHighBitDepth ?? await _hasHighBitDepthFrames(framesDir);

    // Video encoding settings based on codec model
    final pixFmt = codec.pixelFormatForSource(highBitDepth: highBitDepth);

    // Without any overlay, still run the frames through a format filter, and
    // through -filter_complex rather than -vf: on FFmpeg 6.1 (the Linux
    // distro builds) the simple-graph path gives the first photo one frame
    // too few below 10 photos/s. Same format as the output, so nothing is
    // converted twice.
    if (!filterResult.hasFilter) {
      args.addAll(['-filter_complex', '[0:v]format=$pixFmt[v]', '-map', '[v]']);
    }

    LogService.instance.log(
      "[VIDEO] Using ${codec.displayName} encoder: ${codec.encoder}",
    );

    final int outFps = outputFps(fps);
    args.addAll(['-fps_mode', 'cfr', '-r', '$outFps', '-pix_fmt', pixFmt]);

    // Color space metadata for correct rendering in all players
    args.addAll([
      '-color_primaries',
      'bt709',
      '-color_trc',
      'bt709',
      '-colorspace',
      'bt709',
    ]);

    // Encoder: uses .encoder which returns encoderApple on macOS
    // (e.g. h264_videotoolbox, hevc_videotoolbox, prores_ks) or
    // encoderDesktop on Windows/Linux (e.g. libx264, libx265, libvpx-vp9)
    final encoderParts = codec.encoder.split(' ');
    args.addAll(['-c:v', ...encoderParts]);

    // macOS uses VideoToolbox hardware encoders which auto-negotiate
    // profile/level correctly. Do NOT set -profile:v / -level here;
    // explicit Level 5.1 causes VideoToolbox to reject 4K@30fps
    // (exceeds macroblock throughput limit).
    if (!isMacOS && codec == VideoCodec.h264) {
      final (profile, level) = _getH264ProfileAndLevel(resolution);
      args.addAll(['-profile:v', profile, '-level', level]);
    }

    if (codec == VideoCodec.vp9) {
      args.addAll([
        '-b:v',
        '${kbps}k',
        '-crf',
        '30',
        '-row-mt',
        '1',
        '-auto-alt-ref',
        '0',
      ]);
    } else if (codec.usesBitrateControl) {
      args.addAll([
        '-b:v',
        '${kbps}k',
        '-maxrate',
        '${(kbps * 1.5).round()}k',
        '-bufsize',
        '${(kbps * 3).round()}k',
      ]);
    }

    if (codec.usesMovFlags) {
      args.addAll(['-movflags', '+faststart']);
    }

    // Codec tag (e.g. -tag:v avc1 for H.264, -tag:v hvc1 for HEVC on Apple).
    // Returns '' on non-Apple platforms, so the guard handles it safely.
    final tag = codec.codecTag;
    if (tag.isNotEmpty) {
      args.addAll(tag.split(' '));
    }

    if (!videoHasAlpha) {
      args.addAll(['-g', '240']);
    }

    args.add(outputPath);

    LogService.instance.log("[VIDEO] ffmpeg arguments: ${args.join(' ')}");
    LogService.instance.log("[VIDEO] Starting ffmpeg process...");

    final monitor = _EncodeMonitor(
      inputFrames: await _countConcatFrames(listPath),
      inputFps: fps,
    );
    try {
      final run = await FFmpegProcessManager.instance.startProcess(
        ffmpegExe,
        args,
      );
      final proc = run.process!;
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
            monitor.onLine(line);
            final m = RegExp(r'frame=\s*(\d+)').firstMatch(line);
            if (m != null && onProgress != null) {
              final videoFrame = int.tryParse(m.group(1)!);
              if (videoFrame != null) {
                final int outFps = outputFps(fps);
                final int f = (videoFrame * fps) ~/ outFps;
                onProgress(f);
              }
            }
          });

      void cancelRun() => unawaited(run.cancel());
      job.token.addListener(cancelRun);
      final int code;
      try {
        code = await run.exitCode;
      } finally {
        job.token.removeListener(cancelRun);
      }
      LogService.instance.log("[VIDEO] ffmpeg process exited with code: $code");

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

      return monitor.result(exitCode: code, cancelled: run.cancelRequested);
    } catch (e, stackTrace) {
      LogService.instance.log("[VIDEO] ERROR starting ffmpeg process: $e");
      LogService.instance.log("[VIDEO] Stack trace: $stackTrace");
      return monitor.result(exitCode: -1, cancelled: job.isCancelled);
    } finally {
      await _deleteQuietly(listPath);
      LogService.instance.log("[VIDEO] Cleaned up concat list file");
    }
  }
}
