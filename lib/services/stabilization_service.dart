import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cancellation_token.dart';
import 'database_helper.dart';
import 'face_stabilizer.dart';
import 'ffmpeg_process_manager.dart';
import 'isolate_manager.dart';
import 'isolate_pool.dart';
import 'log_service.dart';
import 'stabilization_benchmark.dart';
import 'stabilization_progress.dart';
import 'stabilization_settings.dart';
import 'stabilization_state.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import '../utils/video_utils.dart';

/// Central service for managing stabilization and video compilation.
///
/// This service provides:
/// - Instant cancellation (kills isolates and FFmpeg processes immediately)
/// - Stream-based progress updates for reactive UI
/// - Explicit state machine for clear state transitions
/// - Single source of truth for stabilization state
///
/// Usage:
/// ```dart
/// // Subscribe to progress updates
/// StabilizationService.instance.progressStream.listen((progress) {
///   setState(() => _progress = progress);
/// });
///
/// // Start stabilization
/// await StabilizationService.instance.startStabilization(projectId);
///
/// // Cancel instantly
/// await StabilizationService.instance.cancel();
/// ```
class StabilizationService {
  StabilizationService._internal();

  static final StabilizationService _instance =
      StabilizationService._internal();

  /// The singleton instance.
  static StabilizationService get instance => _instance;

  // State management
  final _progressController =
      StreamController<StabilizationProgress>.broadcast();
  StabilizationState _state = StabilizationState.idle;
  CancellationToken? _currentToken;
  int? _currentProjectId;
  FaceStabilizer? _currentStabilizer;
  StabilizationSettings? _currentSettings;

  // Progress tracking
  int _currentPhoto = 0;
  int _totalPhotos = 0;
  int _successfullyStabilized = 0;
  int _stabilizedAtStart = 0;
  String _eta = '';

  // Benchmark tracking
  final StabilizationBenchmark _benchmark = StabilizationBenchmark();

  /// Stream of progress updates. Subscribe to this for reactive UI updates.
  Stream<StabilizationProgress> get progressStream =>
      _progressController.stream;

  /// Current state of the stabilization process.
  StabilizationState get state => _state;

  /// Whether stabilization is currently active.
  bool get isActive => _state.isActive;

  /// Whether a cancellation is in progress.
  bool get isCancelling => _state.isCancelling;

  /// The project ID currently being processed, if any.
  int? get currentProjectId => _currentProjectId;

  /// Callback for when user runs out of space.
  VoidCallback? userRanOutOfSpaceCallback;

  /// Start stabilization for a project.
  ///
  /// If a stabilization is already running, it will be cancelled first.
  /// Returns true if stabilization completed successfully.
  Future<bool> startStabilization(
    int projectId, {
    VoidCallback? onUserRanOutOfSpace,
  }) async {
    // Cancel any existing operation first
    if (_state != StabilizationState.idle &&
        _state != StabilizationState.completed &&
        _state != StabilizationState.cancelled &&
        _state != StabilizationState.error) {
      await cancelAndWait();
    }

    userRanOutOfSpaceCallback = onUserRanOutOfSpace;
    _currentProjectId = projectId;
    _currentToken = CancellationToken();
    _resetCounters();

    final unstabilizedPhotos = await StabUtils.getUnstabilizedPhotos(projectId);
    _totalPhotos = unstabilizedPhotos.length;

    if (_totalPhotos == 0) {
      LogService.instance.log(
        'StabilizationService: No photos to stabilize, checking video',
      );
      final needsVideo = await _checkIfVideoNeeded(projectId);
      if (needsVideo) {
        _state = StabilizationState.compilingVideo;
        await _tryCreateVideo(projectId);
        _emitProgress(StabilizationProgress.completed(projectId: projectId));
        _state = StabilizationState.completed;
        await _cleanup();
      }
      return true;
    }

    // Only emit preparing state if there's actual work to do
    _emitProgress(StabilizationProgress.preparing(projectId: projectId));
    _state = StabilizationState.preparing;

    try {
      await WakelockPlus.enable();

      await IsolatePool.instance.initialize();
      _currentSettings = await StabilizationSettings.load(projectId);
      _currentStabilizer = FaceStabilizer(
        projectId,
        _handleUserRanOutOfSpace,
        settings: _currentSettings,
      );

      final allPhotos = await DB.instance.getPhotosByProjectID(projectId);
      _stabilizedAtStart = await DB.instance.getStabilizedPhotoCountByProjectID(
        projectId,
        _currentSettings!.projectOrientation,
      );

      _state = StabilizationState.stabilizing;
      _emitProgress(
        StabilizationProgress.stabilizing(
          currentPhoto: 0,
          totalPhotos: _totalPhotos,
          progressPercent: 0,
          projectId: projectId,
        ),
      );

      // Stabilize each photo
      final Stopwatch stopwatch = Stopwatch()..start();
      int photosDone = 0;

      for (final photo in unstabilizedPhotos) {
        _currentToken?.throwIfCancelled();

        LogService.instance.log(
          'StabilizationService: Stabilizing photo ${_currentPhoto + 1}/$_totalPhotos',
        );

        final result = await _stabilizePhoto(
          _currentStabilizer!,
          photo,
          _currentToken,
        );

        if (result.cancelled) {
          throw CancelledException('User cancelled');
        }

        if (result.success) {
          _successfullyStabilized++;
          // Add to benchmark
          _benchmark.addResult(
            finalScore: result.finalScore,
            finalEyeDeltaY: result.finalEyeDeltaY,
            finalEyeDistance: result.finalEyeDistance,
            goalEyeDistance: result.goalEyeDistance,
            mode: _currentStabilizer?.stabilizationMode,
          );
        }

        _currentPhoto++;
        photosDone++;

        final avgTimePerPhoto = stopwatch.elapsedMilliseconds / photosDone;
        final remainingPhotos = _totalPhotos - photosDone;
        final estimatedTimeRemaining = avgTimePerPhoto * remainingPhotos;
        _eta = _formatDuration(estimatedTimeRemaining.toInt());

        final totalPhotoCount = allPhotos.length;
        final completed = _stabilizedAtStart + _successfullyStabilized;
        var pct =
            totalPhotoCount > 0 ? ((completed * 100) ~/ totalPhotoCount) : 0;
        if (pct >= 100) pct = 99;
        if (pct < 0) pct = 0;

        _emitProgress(
          StabilizationProgress.stabilizing(
            currentPhoto: _currentPhoto,
            totalPhotos: _totalPhotos,
            progressPercent: pct,
            eta: _eta,
            projectId: projectId,
            lastStabilizedTimestamp: photo['timestamp']?.toString(),
          ),
        );
      }

      stopwatch.stop();

      // Log benchmark summary
      if (_benchmark.count > 0) {
        _benchmark.logSummary();
      }

      // Final check for re-stabilization if settings changed
      _currentToken?.throwIfCancelled();
      await _finalCheck(_currentStabilizer!, projectId);

      // Create video
      _currentToken?.throwIfCancelled();
      await _tryCreateVideo(projectId);

      _emitProgress(StabilizationProgress.completed(projectId: projectId));
      _state = StabilizationState.completed;
      return true;
    } on CancelledException {
      LogService.instance.log('StabilizationService: Cancelled');
      _emitProgress(StabilizationProgress.cancelled(projectId: projectId));
      _state = StabilizationState.cancelled;
      return false;
    } catch (e) {
      LogService.instance.log('StabilizationService: Error - $e');
      _emitProgress(
        StabilizationProgress.error(e.toString(), projectId: projectId),
      );
      _state = StabilizationState.error;
      return false;
    } finally {
      await _cleanup();
    }
  }

  /// Cancel the current operation INSTANTLY.
  ///
  /// This method:
  /// 1. Emits 'cancelling' state immediately for UI feedback
  /// 2. Sets the cancellation token (cooperative cancellation)
  /// 3. Kills all active isolates (instant termination)
  /// 4. Kills any active FFmpeg process (instant termination)
  ///
  /// The method returns immediately - cleanup happens asynchronously.
  Future<void> cancel() async {
    if (_state == StabilizationState.idle ||
        _state == StabilizationState.completed ||
        _state == StabilizationState.cancelled) {
      return;
    }

    LogService.instance.log('StabilizationService: Cancel requested');

    // Emit cancelling state IMMEDIATELY for UI feedback
    if (_state.isVideoPhase) {
      _emitProgress(
        StabilizationProgress.cancellingVideo(projectId: _currentProjectId),
      );
      _state = StabilizationState.cancellingVideo;
    } else {
      _emitProgress(
        StabilizationProgress.cancelling(projectId: _currentProjectId),
      );
      _state = StabilizationState.cancelling;
    }

    // Set token (cooperative cancellation for code that checks it)
    _currentToken?.cancel();

    // Kill everything forcefully (instant cancellation)
    IsolateManager.instance.killAll();
    IsolatePool.instance.killAll();
    await FFmpegProcessManager.instance.killActiveProcess();

    LogService.instance.log('StabilizationService: All processes killed');
  }

  /// Cancel and wait for the operation to fully stop.
  ///
  /// Use this when you need to ensure the operation has completely stopped
  /// before starting a new one (e.g., when restarting after settings change).
  Future<void> cancelAndWait() async {
    await cancel();

    // Wait for state to reach a terminal state (max 2 seconds)
    final stopwatch = Stopwatch()..start();
    while (!_state.isFinished && stopwatch.elapsedMilliseconds < 2000) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Force to cancelled state if still not finished
    if (!_state.isFinished) {
      _state = StabilizationState.cancelled;
      _emitProgress(
        StabilizationProgress.cancelled(projectId: _currentProjectId),
      );
    }
  }

  /// Restart stabilization (cancel current and start fresh).
  Future<bool> restart(
    int projectId, {
    VoidCallback? onUserRanOutOfSpace,
  }) async {
    await cancelAndWait();
    return startStabilization(
      projectId,
      onUserRanOutOfSpace: onUserRanOutOfSpace,
    );
  }

  // ==================== Private Methods ====================

  Future<StabilizationResult> _stabilizePhoto(
    FaceStabilizer stabilizer,
    Map<String, dynamic> photo,
    CancellationToken? token,
  ) async {
    try {
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        photo['timestamp'],
        _currentProjectId!,
        fileExtension: photo['fileExtension'],
      );

      return await stabilizer.stabilize(
        rawPhotoPath,
        token,
        _handleUserRanOutOfSpace,
      );
    } catch (e) {
      if (e is CancelledException) rethrow;
      LogService.instance.log(
        'StabilizationService: Error stabilizing photo - $e',
      );
      return StabilizationResult(success: false);
    }
  }

  Future<void> _finalCheck(FaceStabilizer stabilizer, int projectId) async {
    // Load fresh settings to compare against stored offsets in photos
    // This detects if user changed settings since photos were stabilized
    final freshSettings = await StabilizationSettings.load(projectId);
    final allPhotos = await DB.instance.getStabilizedPhotosByProjectID(
      projectId,
      freshSettings.projectOrientation,
    );

    final columnName = freshSettings.projectOrientation == 'portrait'
        ? "stabilizedPortraitOffsetX"
        : "stabilizedLandscapeOffsetX";
    final currentOffsetX = freshSettings.eyeOffsetX.toString();

    for (var photo in allPhotos) {
      _currentToken?.throwIfCancelled();

      if (photo[columnName] != currentOffsetX) {
        await _reStabilizePhoto(
          stabilizer,
          photo,
          projectId,
          freshSettings.projectOrientation,
        );
      }
    }
  }

  Future<void> _reStabilizePhoto(
    FaceStabilizer stabilizer,
    Map<String, dynamic> photo,
    int projectId,
    String projectOrientation,
  ) async {
    await DB.instance.resetStabilizedColumnByTimestamp(
      projectOrientation,
      photo['timestamp'],
      projectId,
    );

    try {
      final rawPhotoPath =
          '${await DirUtils.getRawPhotoDirPath(projectId)}/${photo['timestamp']}${photo['fileExtension']}';
      final result = await stabilizer.stabilize(
        rawPhotoPath,
        _currentToken,
        _handleUserRanOutOfSpace,
      );

      if (result.success) {
        _successfullyStabilized++;
      }
    } catch (e) {
      if (e is CancelledException) rethrow;
      LogService.instance.log(
        'StabilizationService: Error re-stabilizing photo - $e',
      );
    }
  }

  /// Check if a video needs to be created without actually creating it.
  /// Used to determine if we should show progress UI when no photos need stabilizing.
  Future<bool> _checkIfVideoNeeded(int projectId) async {
    try {
      final newestVideo = await DB.instance.getNewestVideoByProjectId(
        projectId,
      );
      // Use cached settings if available, otherwise load fresh
      final orientation = _currentSettings?.projectOrientation ??
          await SettingsUtil.loadProjectOrientation(projectId.toString());
      final stabPhotoCount = await DB.instance
          .getStabilizedPhotoCountByProjectID(projectId, orientation);

      final videoIsNull = newestVideo == null;
      final settingsHaveChanged = await VideoUtils.videoOutputSettingsChanged(
        projectId,
        newestVideo,
      );
      final newVideoNeededRaw = await DB.instance.getNewVideoNeeded(projectId);
      final newVideoNeeded = newVideoNeededRaw == 1;

      return newVideoNeeded ||
          ((videoIsNull || settingsHaveChanged) && stabPhotoCount > 1);
    } catch (e) {
      LogService.instance.log(
        'StabilizationService: Error checking if video needed - $e',
      );
      return false;
    }
  }

  Future<void> _tryCreateVideo(int projectId) async {
    try {
      _currentToken?.throwIfCancelled();

      // Check if auto-compile is enabled
      final autoCompileEnabled = await SettingsUtil.loadAutoCompileVideo(
        projectId.toString(),
      );

      final newestVideo = await DB.instance.getNewestVideoByProjectId(
        projectId,
      );
      // Use cached settings if available, otherwise load fresh
      final orientation = _currentSettings?.projectOrientation ??
          await SettingsUtil.loadProjectOrientation(projectId.toString());
      final stabPhotoCount = await DB.instance
          .getStabilizedPhotoCountByProjectID(projectId, orientation);

      final videoIsNull = newestVideo == null;
      final settingsHaveChanged = await VideoUtils.videoOutputSettingsChanged(
        projectId,
        newestVideo,
      );
      final newPhotosStabilized = _successfullyStabilized > 0;
      final newVideoNeededRaw = await DB.instance.getNewVideoNeeded(projectId);
      final newVideoNeeded = newVideoNeededRaw == 1;

      // Determine if video compilation is needed
      final shouldCompile = newVideoNeeded ||
          ((videoIsNull || settingsHaveChanged || newPhotosStabilized) &&
              stabPhotoCount > 1);

      // If auto-compile is disabled, mark that new video is needed but skip compilation
      if (!autoCompileEnabled && shouldCompile) {
        LogService.instance.log(
          'StabilizationService: Auto-compile disabled, skipping video compilation',
        );
        // Mark that a new video is needed so user can compile manually
        await DB.instance.setNewVideoNeeded(projectId);
        return;
      }

      if (shouldCompile) {
        _state = StabilizationState.compilingVideo;
        _emitProgress(
          StabilizationProgress.compilingVideo(
            currentFrame: 0,
            totalFrames: stabPhotoCount,
            progressPercent: 0,
            projectId: projectId,
          ),
        );

        _currentToken?.throwIfCancelled();

        // Start ETA tracking for video compilation
        VideoUtils.resetVideoStopwatch(stabPhotoCount);

        final result = await VideoUtils.createTimelapseFromProjectId(
          projectId,
          (currentFrame) {
            final pct = stabPhotoCount > 0
                ? ((currentFrame * 100) ~/ stabPhotoCount)
                : 0;
            final eta = VideoUtils.calculateVideoEta(currentFrame);
            _emitProgress(
              StabilizationProgress.compilingVideo(
                currentFrame: currentFrame,
                totalFrames: stabPhotoCount,
                progressPercent: pct,
                eta: eta,
                projectId: projectId,
              ),
            );
          },
        );

        // Stop ETA tracking
        VideoUtils.stopVideoStopwatch();

        if (newVideoNeeded && result) {
          DB.instance.setNewVideoNotNeeded(projectId);
        }

        LogService.instance.log(
          'StabilizationService: Video creation result - $result',
        );
      }
    } catch (e) {
      if (e is CancelledException) rethrow;
      LogService.instance.log(
        'StabilizationService: Error creating video - $e',
      );
    }
  }

  void _handleUserRanOutOfSpace() {
    LogService.instance.log('StabilizationService: User ran out of space');
    userRanOutOfSpaceCallback?.call();
    cancel();
  }

  void _emitProgress(StabilizationProgress progress) {
    _state = progress.state;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  void _resetCounters() {
    _currentPhoto = 0;
    _totalPhotos = 0;
    _successfullyStabilized = 0;
    _stabilizedAtStart = 0;
    _eta = '';
    _benchmark.reset();
  }

  Future<void> _cleanup() async {
    await _currentStabilizer?.dispose();
    _currentStabilizer = null;
    _currentToken = null;
    _currentSettings = null;
    await WakelockPlus.disable();

    // Reset to idle after a short delay to allow UI to update
    await Future.delayed(const Duration(milliseconds: 100));
    if (_state == StabilizationState.completed ||
        _state == StabilizationState.cancelled ||
        _state == StabilizationState.error) {
      _state = StabilizationState.idle;
      _emitProgress(StabilizationProgress.idle());
    }
  }

  String _formatDuration(int milliseconds) {
    final hours = milliseconds ~/ (1000 * 60 * 60);
    final minutes = (milliseconds % (1000 * 60 * 60)) ~/ (1000 * 60);
    final seconds = (milliseconds % (1000 * 60)) ~/ 1000;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Dispose the service (should rarely be needed).
  void dispose() {
    _progressController.close();
  }
}
