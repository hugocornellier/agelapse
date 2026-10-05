import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/video_codec.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// Playback diagnostics for the in-app video player, written to the app log.
///
/// Added for a report of a black video on iPhone 17 / iOS 27: the player ran
/// normally (clock advancing, no error) but showed no picture, and nothing was
/// logged. These hooks record what was played and, on iOS, whether frames were
/// decoded and actually reached the screen.
class VideoDiagnostics {
  static const _channel = MethodChannel('com.agelapse/video_diagnostics');

  /// Replaces the measured frame check, so integration tests can drive the
  /// platform-view fallback without a real black screen.
  @visibleForTesting
  static FrameCheck Function(FrameCheck measured)? debugFrameCheckOverride;

  static void _log(String message) =>
      LogService.instance.log('[PLAYER] $message');

  /// Logs the file about to be played, the newest video record and, on iOS,
  /// what AVFoundation sees in it. Called before playback, so the existing
  /// file is described before anything can recompile it.
  static Future<void> logVideoOpened({
    required int projectId,
    required File file,
    required VideoCodec codec,
    required String orientation,
  }) async {
    try {
      final stat = await file.stat();
      _log(
        'Opening ${file.path} (${stat.size} bytes, modified '
        '${stat.modified.toIso8601String()}), codec setting ${codec.name}, '
        'orientation $orientation',
      );

      final record = await DB.instance.getNewestVideoByProjectId(projectId);
      if (record == null) {
        _log('No video record for project $projectId');
      } else {
        final created = DateTime.fromMillisecondsSinceEpoch(
          record['timestampCreated'] as int,
        );
        _log(
          'Newest video record: ${record['resolution']}, '
          '${record['photoCount']} photos at ${record['framerate']} fps, '
          'watermark ${record['watermarkEnabled']}, '
          'created ${created.toIso8601String()}',
        );
      }

      if (Platform.isIOS) {
        await _logAssetInfo(file.path);
      }
    } catch (e) {
      _log('Could not describe video file: $e');
    }
  }

  /// Logs what AVFoundation, and so the iOS player, sees in [path]: codec,
  /// size, frame rate, bit depth, range, color tags, transform, and whether
  /// it can play and decode each track.
  static Future<void> _logAssetInfo(String path) async {
    final info = await _channel.invokeMapMethod<String, dynamic>(
      'describeVideo',
      {'path': path},
    );
    _log('AVFoundation: duration ${info?['duration']}s');
    for (final track in (info?['tracks'] as List?) ?? const []) {
      _log(
        'AVFoundation track: ${track['type']} ${track['codec']} '
        '${track['width']}x${track['height']}, ${track['fps']} fps, '
        '${track['bitrate']} bps, depth ${track['depth']}, '
        'fullRange ${track['fullRange']}, primaries ${track['primaries']}, '
        'transfer ${track['transfer']}, matrix ${track['matrix']}, '
        'transform ${track['transform']}, playable ${track['playable']}, '
        'decodable ${track['decodable']}',
      );
    }
  }

  /// Logs what the player reports right after initialize().
  static void logPlayerInitialized(
    VideoPlayerValue value, {
    required VideoViewType viewType,
  }) {
    _log(
      'Player initialized (${viewType.name}): '
      '${value.size.width.toInt()}x${value.size.height.toInt()}, '
      '${value.duration.inMilliseconds}ms, '
      'rotation ${value.rotationCorrection}, '
      'error ${value.errorDescription ?? 'none'}',
    );
  }

  static void logPlayerFailed(Object error) =>
      _log('Player failed to initialize: $error');

  static void logPlaybackError(String? description) =>
      _log('Playback error: ${description ?? 'unknown'}');

  static void logFallbackToPlatformView() =>
      _log('Screen stayed black; switching to the platform-view player');

  /// iOS only. Measures the player's area on screen, then decodes [file] the
  /// way the player's texture does. Returns null where unavailable.
  static Future<FrameCheck?> checkFrames(File file, Rect playerRect) async {
    if (!Platform.isIOS) return null;
    try {
      // Measure first: that is what the user sees at this moment.
      final screen = await _channel
          .invokeMapMethod<String, dynamic>('measureScreenRegion', {
            'left': playerRect.left,
            'top': playerRect.top,
            'width': playerRect.width,
            'height': playerRect.height,
          });
      final decoded = await _channel.invokeMapMethod<String, dynamic>(
        'probeFrames',
        {'path': file.path},
      );
      final check = FrameCheck(
        screenLuma: (screen?['luma'] as num?)?.toDouble() ?? 0,
        screenChroma: (screen?['chroma'] as num?)?.toDouble() ?? 0,
        framesDecoded: (decoded?['framesReceived'] as num?)?.toInt() ?? 0,
        decodedLuma: (decoded?['meanLuma'] as num?)?.toDouble() ?? 0,
      );
      final decodeError = decoded?['error'] as String? ?? '';
      _log(
        'Frame check: screen luma ${check.screenLuma.toStringAsFixed(1)}, '
        'chroma ${check.screenChroma.toStringAsFixed(1)}; decoded '
        '${check.framesDecoded} frames, luma '
        '${check.decodedLuma.toStringAsFixed(1)}, '
        '${decoded?['width']}x${decoded?['height']} ${decoded?['pixelFormat']}, '
        'item status ${decoded?['itemStatus']}, '
        'error ${decodeError.isEmpty ? 'none' : decodeError}; '
        'verdict ${check.verdict.name}',
      );
      final override = debugFrameCheckOverride;
      if (override == null) return check;
      final forced = override(check);
      _log(
        'Frame check overridden for testing: verdict ${forced.verdict.name}',
      );
      return forced;
    } catch (e) {
      _log('Frame check failed: $e');
      return null;
    }
  }

  /// iOS only. Logs each AVPlayerLayer on screen and whether it has a frame.
  static Future<void> logPlayerLayers() async {
    if (!Platform.isIOS) return;
    try {
      final layers = await _channel.invokeListMethod<dynamic>('playerLayers');
      _log('Player layers: $layers');
    } catch (e) {
      _log('Could not list player layers: $e');
    }
  }
}

/// Outcome of comparing the on-screen player area with decoded frames.
enum FrameVerdict {
  /// The player area shows a picture.
  ok,

  /// The screen and the decoded frames are both dark: the video itself is
  /// black or very dark.
  videoIsDark,

  /// Frames decode with a picture but the screen is black: rendering failure.
  notRendered,

  /// AVFoundation produced no frames and the screen is black.
  noFramesDecoded,
}

/// Brightness measurements from [VideoDiagnostics.checkFrames], all 0-255.
class FrameCheck {
  const FrameCheck({
    required this.screenLuma,
    required this.screenChroma,
    required this.framesDecoded,
    required this.decodedLuma,
  });

  /// The player area counts as black below both of these.
  static const double blackScreenLuma = 12;
  static const double blackScreenChroma = 8;

  /// Decoded frames at or above this luma have a visible picture.
  static const double visibleLuma = 24;

  final double screenLuma;
  final double screenChroma;
  final int framesDecoded;
  final double decodedLuma;

  bool get screenIsBlack =>
      screenLuma < blackScreenLuma && screenChroma < blackScreenChroma;

  FrameVerdict get verdict {
    if (!screenIsBlack) return FrameVerdict.ok;
    if (framesDecoded == 0) return FrameVerdict.noFramesDecoded;
    if (decodedLuma >= visibleLuma) return FrameVerdict.notRendered;
    return FrameVerdict.videoIsDark;
  }

  /// Whether the platform-view player, which draws through AVPlayerLayer
  /// instead of a Flutter texture, could show what this player does not.
  bool get shouldFallBackToPlatformView =>
      verdict == FrameVerdict.notRendered ||
      verdict == FrameVerdict.noFramesDecoded;
}
