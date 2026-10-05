import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cancellation_token.dart';
import 'database_helper.dart';
import 'face_stabilizer.dart';
import 'isolate_manager.dart';
import 'isolate_pool.dart';
import 'log_service.dart';
import 'ordered_reveal_gate.dart';
import 'stabilization_benchmark.dart';
import 'stabilization_progress.dart';
import 'stabilization_settings.dart';
import 'stabilization_state.dart';
import 'video_compile_coordinator.dart';
import '../models/video_background.dart';
import '../models/video_codec.dart';
import '../utils/dir_utils.dart';
import '../utils/platform_utils.dart';
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

  /// Monotonic generation counter identifying the current run.
  ///
  /// Bumped at the start of every [startStabilization]. Late callbacks from
  /// prior runs (e.g. [_cleanup] resuming after an async dispose) compare
  /// against this before mutating shared state so they can't clobber a
  /// newer run's fields.
  int _currentGen = 0;

  /// The latest run, so a new run or [cancelAndWait] can wait for it to end.
  Completer<bool>? _activeRun;

  /// How long to wait for a cancelled run or encode to stop before moving
  /// on. Encodes never overlap regardless: [VideoCompileCoordinator] only
  /// starts one after the previous FFmpeg has exited.
  static const Duration _stopTimeout = Duration(seconds: 30);

  bool _isCurrent(int gen) => gen == _currentGen;

  /// Emits [progress] only while [gen] is the current run, so a superseded
  /// run can't overwrite the state of the run that replaced it.
  void _emitIfCurrent(int gen, StabilizationProgress progress) {
    if (_isCurrent(gen)) _emitProgress(progress);
  }

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
  /// If a stabilization is already running, it is cancelled and awaited
  /// first, including its video encode. Returns true if stabilization
  /// completed successfully.
  Future<bool> startStabilization(
    int projectId, {
    VoidCallback? onUserRanOutOfSpace,
  }) async {
    // Claim the newest generation before any await: of several concurrent
    // callers, only the last one goes on to run. A prior run's [_cleanup]
    // that is still parked on an async await compares against this before
    // touching shared state.
    final myGen = ++_currentGen;
    final previousRun = _activeRun;
    final run = Completer<bool>();
    _activeRun = run;
    try {
      // Stop a previous run that is still going, including its encode, and
      // wait for it to end before touching shared state. (A finished run is
      // left alone, so e.g. a manual compile isn't cancelled by an idle
      // check.)
      if (previousRun != null && !previousRun.isCompleted) {
        await _stopRun(previousRun.future, 'new run for project $projectId');
      }
      if (!_isCurrent(myGen)) {
        run.complete(false);
        return false;
      }
      final result = await _runStabilization(
        myGen,
        projectId,
        onUserRanOutOfSpace,
      );
      run.complete(result);
      return result;
    } catch (_) {
      if (!run.isCompleted) run.complete(false);
      rethrow;
    }
  }

  Future<bool> _runStabilization(
    int myGen,
    int projectId,
    VoidCallback? onUserRanOutOfSpace,
  ) async {
    userRanOutOfSpaceCallback = onUserRanOutOfSpace;
    _currentProjectId = projectId;
    _currentToken = CancellationToken();
    _resetCounters();
    FaceStabilizer? stabilizer;

    try {
      final unstabilizedPhotos = await StabUtils.getUnstabilizedPhotos(
        projectId,
      );
      _totalPhotos = unstabilizedPhotos.length;

      if (_totalPhotos == 0) {
        LogService.instance.log(
          'StabilizationService: No photos to stabilize, checking video',
        );

        // Check auto-compile setting BEFORE emitting any progress UI
        final autoCompileEnabled = await SettingsUtil.loadAutoCompileVideo(
          projectId.toString(),
        );

        final needsVideo = await _checkIfVideoNeeded(projectId);

        // If video needed but auto-compile disabled, set flag and exit cleanly
        if (needsVideo && !autoCompileEnabled) {
          LogService.instance.log(
            'StabilizationService: Video needed but auto-compile disabled, setting flag only',
          );
          await DB.instance.setNewVideoNeeded(projectId);
          _emitIfCurrent(
            myGen,
            StabilizationProgress.completed(projectId: projectId),
          );
          return true;
        }

        if (needsVideo) {
          // Get frame count for progress indicator
          final orientation = await SettingsUtil.loadProjectOrientation(
            projectId.toString(),
          );
          final stabPhotoCount = await DB.instance
              .getStabilizedPhotoCountByProjectID(projectId, orientation);

          LogService.instance.log(
            'StabilizationService: Video needed, emitting compilingVideo state with $stabPhotoCount frames',
          );
          // Emit initial progress so UI shows "Compiling video..." immediately
          _emitIfCurrent(
            myGen,
            StabilizationProgress.compilingVideo(
              currentFrame: 0,
              totalFrames: stabPhotoCount,
              progressPercent: 0.0,
              projectId: projectId,
            ),
          );
          final videoResult = await _tryCreateVideo(myGen, projectId);
          if (!videoResult.succeeded) {
            _emitIfCurrent(
              myGen,
              StabilizationProgress.error(
                'Video compilation failed: ${videoResult.errorMessage}',
                projectId: projectId,
              ),
            );
            return false;
          }
          _emitIfCurrent(
            myGen,
            StabilizationProgress.completed(projectId: projectId),
          );
        }
        return true;
      }

      // Only emit preparing state if there's actual work to do
      _emitIfCurrent(
        myGen,
        StabilizationProgress.preparing(projectId: projectId),
      );

      await WakelockPlus.enable();

      await IsolatePool.instance.initialize();
      _currentSettings = await StabilizationSettings.load(projectId);
      stabilizer = FaceStabilizer(
        projectId,
        _handleUserRanOutOfSpace,
        settings: _currentSettings,
      );
      _currentStabilizer = stabilizer;

      final allPhotos = await DB.instance.getPhotosByProjectID(projectId);
      _stabilizedAtStart = await DB.instance.getStabilizedPhotoCountByProjectID(
        projectId,
        _currentSettings!.projectOrientation,
      );

      _emitIfCurrent(
        myGen,
        StabilizationProgress.stabilizing(
          currentPhoto: 0,
          totalPhotos: _totalPhotos,
          progressPercent: 0.0,
          projectId: projectId,
        ),
      );

      // Stabilize each photo
      final Stopwatch stopwatch = Stopwatch()..start();
      final progressState = _ProgressState(
        photosDone: 0,
        totalPhotoCount: allPhotos.length,
      );

      await _stabilizeBatch(
        unstabilizedPhotos,
        stopwatch,
        progressState,
        projectId,
      );

      // Re-check for photos added during stabilization (e.g., user took a photo)
      const maxRecheckPasses = 3;
      for (int pass = 0; pass < maxRecheckPasses; pass++) {
        _currentToken?.throwIfCancelled();
        final newPhotos = await StabUtils.getUnstabilizedPhotos(projectId);
        if (newPhotos.isEmpty) break;

        _totalPhotos += newPhotos.length;
        final freshAllPhotos = await DB.instance.getPhotosByProjectID(
          projectId,
        );
        progressState.totalPhotoCount = freshAllPhotos.length;

        LogService.instance.log(
          'StabilizationService: Found ${newPhotos.length} new photos on re-check pass ${pass + 1}',
        );

        await _stabilizeBatch(newPhotos, stopwatch, progressState, projectId);
      }

      stopwatch.stop();

      // Final check for re-stabilization if settings changed
      _currentToken?.throwIfCancelled();
      await _finalCheck(stabilizer, projectId);

      // Create video
      _currentToken?.throwIfCancelled();
      final videoResult = await _tryCreateVideo(myGen, projectId);

      if (!videoResult.succeeded) {
        _emitIfCurrent(
          myGen,
          StabilizationProgress.error(
            'Video compilation failed: ${videoResult.errorMessage}',
            projectId: projectId,
          ),
        );
        return false;
      }

      _emitIfCurrent(
        myGen,
        StabilizationProgress.completed(projectId: projectId),
      );
      return true;
    } on CancelledException {
      LogService.instance.log('StabilizationService: Cancelled');
      _emitIfCurrent(
        myGen,
        StabilizationProgress.cancelled(projectId: projectId),
      );
      return false;
    } catch (e) {
      LogService.instance.log('StabilizationService: Error: $e');
      _emitIfCurrent(
        myGen,
        StabilizationProgress.error(e.toString(), projectId: projectId),
      );
      return false;
    } finally {
      await _cleanup(myGen, stabilizer);
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
  /// The method returns immediately; cleanup happens asynchronously.
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
    // The coordinator cancels the running compile, whose token stops its
    // FFmpeg run. Not awaited here; cancelAndWait waits for it.
    unawaited(
      VideoCompileCoordinator.instance.cancelAll('stabilization cancelled'),
    );

    LogService.instance.log(
      'StabilizationService: Cancellation requested for all work',
    );
  }

  /// Cancel and wait for the operation to fully stop, including any video
  /// encode (also a manual compile started outside the service).
  ///
  /// Use this when you need to ensure the operation has completely stopped
  /// before starting a new one or changing files it reads (e.g., when
  /// restarting after a settings change, or deleting a project).
  Future<void> cancelAndWait() async {
    final run = _activeRun?.future;
    await cancel();
    await _waitForStop(run, 'stabilization cancelled');

    // Force to cancelled state if still not finished
    if (!_state.isFinished) {
      _state = StabilizationState.cancelled;
      _emitProgress(
        StabilizationProgress.cancelled(projectId: _currentProjectId),
      );
    }
  }

  /// Cancels [run] and waits for it to end, before a new run starts.
  Future<void> _stopRun(Future<bool> run, String reason) async {
    await cancel();
    await _waitForStop(run, reason);
  }

  /// Waits for the running encode and for [run] to finish, up to
  /// [_stopTimeout] each, so the UI can't be blocked forever.
  Future<void> _waitForStop(Future<bool>? run, String reason) async {
    await VideoCompileCoordinator.instance
        .cancelAll(reason)
        .timeout(
          _stopTimeout,
          onTimeout: () => LogService.instance.log(
            'StabilizationService: Video encode still stopping after '
            '${_stopTimeout.inSeconds}s',
          ),
        );
    if (run == null) return;
    await run.timeout(
      _stopTimeout,
      onTimeout: () {
        LogService.instance.log(
          'StabilizationService: Previous run still stopping after '
          '${_stopTimeout.inSeconds}s',
        );
        return false;
      },
    );
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
    final timestamp = photo['timestamp']?.toString();
    try {
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
            photo['timestamp'],
            _currentProjectId!,
            fileExtension: photo['fileExtension'],
          );

      final result = await stabilizer.stabilize(
        rawPhotoPath,
        token,
        _handleUserRanOutOfSpace,
        knownFingerprint: photo['fingerprint'] as String?,
      );

      // Increment stabAttempts only on a non-cancelled returned failure.
      // - Success: the counter is reset by setPhotoStabilized inside the
      //   save path, so pre-incrementing would be a no-op.
      // - Cancelled: must NOT count against the 5-attempt cap. Otherwise a
      //   user who cancels and retries the same batch five times would
      //   permanently lock the in-flight photo out of stabilization until
      //   manually reset.
      // - Thrown exception: handled by the catch block below, which marks
      //   stabFailed=1: that already excludes the photo from
      //   getUnstabilizedPhotos regardless of the counter.
      if (!result.success && !result.cancelled && timestamp != null) {
        try {
          await DB.instance.incrementPhotoStabAttempts(
            timestamp: timestamp,
            projectId: _currentProjectId!,
          );
        } catch (e) {
          LogService.instance.log(
            '[STAB] incrementPhotoStabAttempts threw: $e',
          );
        }
      }

      return result;
    } catch (e, stackTrace) {
      if (e is CancelledException) rethrow;
      LogService.instance.log(
        '[STAB_ERROR] projectId=$_currentProjectId photo=$timestamp phase=_stabilizePhoto error=${e.runtimeType}: $e\n$stackTrace',
      );
      if (_currentProjectId != null && timestamp != null) {
        try {
          await DB.instance.setPhotoStabFailed(timestamp, _currentProjectId!);
        } catch (markErr) {
          LogService.instance.log(
            '[STAB_ERROR] Failed to mark photo stabFailed in service: $markErr',
          );
        }
      }
      return StabilizationResult(success: false);
    }
  }

  Future<void> _stabilizeBatch(
    List<Map<String, dynamic>> photos,
    Stopwatch stopwatch,
    _ProgressState progressState,
    int projectId,
  ) async {
    FaceStabilizer.resetCacheCounters();

    // Gate that releases per-photo reveal notifications to the gallery in
    // strict timestamp order, even though the fast path below finishes photos
    // out of order. One gate per batch; [photos] is already ascending by
    // timestamp (StabUtils.getUnstabilizedPhotos orders by timestamp ASC).
    final gate = OrderedRevealGate([
      for (final photo in photos) photo['timestamp'].toString(),
    ]);

    // Phase 1: parallel transform-cache fast path. Cache-hit renders don't
    // touch per-photo FaceStabilizer state (detection is bypassed), so we can
    // run several at once and saturate the warp isolate pool. Anything that
    // misses falls through to the serial slow path in phase 2.
    final List<Map<String, dynamic>> remaining = await _runFastPathPhase(
      photos,
      stopwatch,
      progressState,
      projectId,
      gate,
    );

    // Phase 2: serial slow path for misses; detection mutates shared state,
    // so this must stay sequential.
    for (final photo in remaining) {
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
        _recordPhotoSuccess(result);
      }

      _advanceProgress(photo, stopwatch, progressState, projectId, gate);
    }

    final totalPhotos = photos.length;
    final hits = FaceStabilizer.cacheHits;
    final misses = FaceStabilizer.cacheMisses;
    final sentinelHits = FaceStabilizer.noFacesSentinelHits;
    final savedSec = FaceStabilizer.estimatedTimeSavedMs ~/ 1000;
    final pct = totalPhotos > 0 ? (hits * 100 ~/ totalPhotos) : 0;
    LogService.instance.log(
      '[cache] run summary: $hits/$totalPhotos hits ($pct%),'
      ' $misses misses, $sentinelHits no_faces sentinels, saved ~${savedSec}s',
    );
  }

  Future<List<Map<String, dynamic>>> _runFastPathPhase(
    List<Map<String, dynamic>> photos,
    Stopwatch stopwatch,
    _ProgressState progressState,
    int projectId,
    OrderedRevealGate gate,
  ) async {
    final workerCount = _fastPathWorkerCount(photos.length);
    if (workerCount <= 1) {
      return photos;
    }

    // Track misses by original index so phase 2 processes them in the caller's
    // order (the timelapse's natural timestamp order) instead of whatever
    // non-deterministic order the workers produced.
    final missedByIndex = List<Map<String, dynamic>?>.filled(
      photos.length,
      null,
      growable: false,
    );
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        _currentToken?.throwIfCancelled();
        // nextIndex++ is atomic across workers in Dart's single-threaded
        // event loop; the two statements run uninterrupted before any await.
        final i = nextIndex;
        if (i >= photos.length) return;
        nextIndex++;

        final photo = photos[i];
        final hit = await _tryFastPathForPhoto(photo);
        if (hit != null && hit.success) {
          _recordPhotoSuccess(hit);
          _advanceProgress(photo, stopwatch, progressState, projectId, gate);
        } else {
          missedByIndex[i] = photo;
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return [for (final photo in missedByIndex) ?photo];
  }

  Future<StabilizationResult?> _tryFastPathForPhoto(
    Map<String, dynamic> photo,
  ) async {
    final timestamp = photo['timestamp']?.toString();
    try {
      final rawPhotoPath =
          await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
            photo['timestamp'],
            _currentProjectId!,
            fileExtension: photo['fileExtension'],
          );
      return await _currentStabilizer!.tryTransformCacheFastPath(
        rawPhotoPath,
        _currentToken,
        knownFingerprint: photo['fingerprint'] as String?,
      );
    } on CancelledException {
      rethrow;
    } catch (e, stackTrace) {
      // Swallow errors; the photo will fall through to the serial slow path
      // where exceptions are logged and stabFailed is set as appropriate.
      LogService.instance.log(
        '[STAB] fast path error for timestamp=$timestamp: ${e.runtimeType}: $e\n$stackTrace',
      );
      return null;
    }
  }

  void _recordPhotoSuccess(StabilizationResult result) {
    _successfullyStabilized++;
    _benchmark.addResult(
      finalScore: result.finalScore,
      finalEyeDeltaY: result.finalEyeDeltaY,
      finalEyeDistance: result.finalEyeDistance,
      goalEyeDistance: result.goalEyeDistance,
    );
  }

  void _advanceProgress(
    Map<String, dynamic> photo,
    Stopwatch stopwatch,
    _ProgressState progressState,
    int projectId,
    OrderedRevealGate gate,
  ) {
    _currentPhoto++;
    progressState.photosDone++;

    final avgTimePerPhoto = progressState.photosDone > 0
        ? stopwatch.elapsedMilliseconds / progressState.photosDone
        : 0;
    final remainingPhotos = _totalPhotos - progressState.photosDone;
    final estimatedTimeRemaining = avgTimePerPhoto * remainingPhotos;
    _eta = _formatDuration(estimatedTimeRemaining.toInt());

    final completed = _stabilizedAtStart + _successfullyStabilized;
    var pct = progressState.totalPhotoCount > 0
        ? (completed * 100.0 / progressState.totalPhotoCount)
        : 0.0;
    if (pct >= 100) pct = 99.9;
    if (pct < 0) pct = 0.0;

    // Hand the finished photo to the reveal gate. It returns the timestamps
    // that may now be shown, in ascending order: this photo plus any earlier
    // ones that finished first and were buffered waiting for it. The gate keeps
    // the gallery filling oldest->newest even though the parallel fast path
    // finishes photos out of order.
    final timestamp = photo['timestamp']?.toString();
    final released = timestamp == null
        ? const <String>[]
        : gate.complete(timestamp);

    if (released.isEmpty) {
      // Buffered behind an earlier photo that hasn't finished yet. Advance the
      // bar/ETA/counter immediately (work happened) but reveal nothing now; the
      // reveal fires later, in order, once the earlier photo lands.
      _emitProgress(
        StabilizationProgress.stabilizing(
          currentPhoto: _currentPhoto,
          totalPhotos: _totalPhotos,
          progressPercent: pct,
          eta: _eta,
          projectId: projectId,
        ),
      );
      return;
    }

    // Emit one reveal per released timestamp, in order. Each carries the live
    // bar/ETA too, so no separate work-progress tick is needed in this branch.
    for (final revealTimestamp in released) {
      _emitProgress(
        StabilizationProgress.stabilizing(
          currentPhoto: _currentPhoto,
          totalPhotos: _totalPhotos,
          progressPercent: pct,
          eta: _eta,
          projectId: projectId,
          lastStabilizedTimestamp: revealTimestamp,
        ),
      );
    }
  }

  /// Worker count for the parallel transform-cache fast path. Capped at the
  /// isolate pool's worker count so warp dispatches don't queue up waiting
  /// for free isolates. Mobile stays serial to avoid contention on a smaller
  /// CPU/memory budget.
  int _fastPathWorkerCount(int photoCount) {
    if (photoCount <= 1) return photoCount;
    if (!isDesktop) return 1;
    return math.min(photoCount, IsolatePool.workerCount);
  }

  Future<void> _finalCheck(FaceStabilizer stabilizer, int projectId) async {
    // Load fresh settings to compare against stored offsets in photos
    // This detects if user changed settings since photos were stabilized
    final freshSettings = await StabilizationSettings.load(projectId);
    final currentOffsetX = freshSettings.eyeOffsetX.toString();

    final photosNeedingRestab = await DB.instance
        .getPhotosNeedingRestabilization(
          projectId,
          freshSettings.projectOrientation,
          currentOffsetX,
        );

    for (var photo in photosNeedingRestab) {
      _currentToken?.throwIfCancelled();

      await _reStabilizePhoto(
        stabilizer,
        photo,
        projectId,
        freshSettings.projectOrientation,
      );
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
        knownFingerprint: photo['fingerprint'] as String?,
      );

      if (result.success) {
        _successfullyStabilized++;
      }
    } catch (e) {
      if (e is CancelledException) rethrow;
      LogService.instance.log(
        'StabilizationService: Error re-stabilizing photo: $e',
      );
    }
  }

  /// Load all video configuration values needed to decide whether to compile.
  Future<_VideoConfig> _loadVideoConfig(int projectId) async {
    final newestVideo = await DB.instance.getNewestVideoByProjectId(projectId);
    // Use cached settings if available, otherwise load fresh
    final orientation =
        _currentSettings?.projectOrientation ??
        await SettingsUtil.loadProjectOrientation(projectId.toString());
    final stabPhotoCount = await DB.instance.getStabilizedPhotoCountByProjectID(
      projectId,
      orientation,
    );

    // Check if video FILE actually exists on disk (not just DB record)
    // Load settings fresh from DB to get correct file extension
    final projectIdStr = projectId.toString();
    final bgColor = await SettingsUtil.loadBackgroundColor(projectIdStr);
    final isTransparent = SettingsUtil.isTransparent(bgColor);
    final videoBg = isTransparent
        ? await SettingsUtil.loadVideoBackground(projectIdStr)
        : VideoBackground.solidColor(bgColor);
    final videoHasAlpha = isTransparent && videoBg.keepTransparent;
    final userCodec = await SettingsUtil.loadVideoCodec(projectIdStr);
    final effectiveCodec = videoHasAlpha
        ? VideoCodec.defaultCodec(isTransparentVideo: true)
        : userCodec;

    final videoPath = await DirUtils.getVideoOutputPath(
      projectId,
      orientation,
      codec: effectiveCodec,
    );
    final videoFileExists = await File(videoPath).exists();

    final videoIsNull = newestVideo == null || !videoFileExists;
    final settingsHaveChanged = await VideoUtils.videoOutputSettingsChanged(
      projectId,
      newestVideo,
    );
    final newVideoNeededRaw = await DB.instance.getNewVideoNeeded(projectId);
    // A counter (see DB.setNewVideoNeeded): any non-zero value means needed.
    final newVideoNeeded = (newVideoNeededRaw ?? 0) != 0;

    return _VideoConfig(
      newestVideo: newestVideo,
      stabPhotoCount: stabPhotoCount,
      isTransparent: isTransparent,
      effectiveCodec: effectiveCodec,
      videoFileExists: videoFileExists,
      videoIsNull: videoIsNull,
      settingsHaveChanged: settingsHaveChanged,
      newVideoNeeded: newVideoNeeded,
    );
  }

  /// Check if a video needs to be created without actually creating it.
  /// Used to determine if we should show progress UI when no photos need stabilizing.
  Future<bool> _checkIfVideoNeeded(int projectId) async {
    try {
      final cfg = await _loadVideoConfig(projectId);

      final result =
          cfg.newVideoNeeded ||
          ((cfg.videoIsNull || cfg.settingsHaveChanged) &&
              cfg.stabPhotoCount > 1);

      LogService.instance.log(
        'StabilizationService: _checkIfVideoNeeded: '
        'newestVideo=${cfg.newestVideo != null}, videoFileExists=${cfg.videoFileExists}, '
        'videoIsNull=${cfg.videoIsNull}, settingsChanged=${cfg.settingsHaveChanged}, '
        'newVideoNeeded=${cfg.newVideoNeeded}, stabPhotoCount=${cfg.stabPhotoCount}, '
        'isTransparent=${cfg.isTransparent}, codec=${cfg.effectiveCodec.name}, result=$result',
      );

      return result;
    } catch (e) {
      LogService.instance.log(
        'StabilizationService: Error checking if video needed: $e',
      );
      return false;
    }
  }

  Future<_VideoCompileResult> _tryCreateVideo(int gen, int projectId) async {
    try {
      // A superseded run must never start a compile: it would cancel the
      // current run's.
      if (!_isCurrent(gen)) throw const CancelledException();
      _currentToken?.throwIfCancelled();

      // Check if auto-compile is enabled
      final autoCompileEnabled = await SettingsUtil.loadAutoCompileVideo(
        projectId.toString(),
      );

      final cfg = await _loadVideoConfig(projectId);

      final newPhotosStabilized = _successfullyStabilized > 0;

      // Determine if video compilation is needed
      final shouldCompile =
          cfg.newVideoNeeded ||
          ((cfg.videoIsNull ||
                  cfg.settingsHaveChanged ||
                  newPhotosStabilized) &&
              cfg.stabPhotoCount > 1);

      LogService.instance.log(
        'StabilizationService: _tryCreateVideo: '
        'videoFileExists=${cfg.videoFileExists}, videoIsNull=${cfg.videoIsNull}, '
        'settingsChanged=${cfg.settingsHaveChanged}, newPhotosStabilized=$newPhotosStabilized, '
        'newVideoNeeded=${cfg.newVideoNeeded}, shouldCompile=$shouldCompile',
      );

      // If auto-compile is disabled, mark that new video is needed but skip compilation
      if (!autoCompileEnabled && shouldCompile) {
        LogService.instance.log(
          'StabilizationService: Auto-compile disabled, skipping video compilation',
        );
        // Mark that a new video is needed so user can compile manually
        await DB.instance.setNewVideoNeeded(projectId);
        return _VideoCompileResult.success();
      }

      if (shouldCompile) {
        _emitIfCurrent(
          gen,
          StabilizationProgress.compilingVideo(
            currentFrame: 0,
            totalFrames: cfg.stabPhotoCount,
            progressPercent: 0.0,
            projectId: projectId,
          ),
        );

        _currentToken?.throwIfCancelled();
        if (!_isCurrent(gen)) throw const CancelledException();

        // Start ETA tracking for video compilation
        VideoUtils.resetVideoStopwatch(cfg.stabPhotoCount);

        final outcome = await VideoUtils.compileVideo(projectId, (
          currentFrame,
        ) {
          if (!_isCurrent(gen)) return;
          final pct = cfg.stabPhotoCount > 0
              ? (currentFrame * 100.0 / cfg.stabPhotoCount)
              : 0.0;
          final eta = VideoUtils.calculateVideoEta(currentFrame);
          _emitProgress(
            StabilizationProgress.compilingVideo(
              currentFrame: currentFrame,
              totalFrames: cfg.stabPhotoCount,
              progressPercent: pct,
              eta: eta,
              projectId: projectId,
            ),
          );
        }, reason: 'stabilization run for project $projectId');

        // Stop ETA tracking
        VideoUtils.stopVideoStopwatch();

        LogService.instance.log(
          'StabilizationService: Video creation result: ${outcome.name}',
        );
        // The compile clears the "new video needed" flag itself when it
        // publishes (only if nothing requested another rebuild meanwhile).
        switch (outcome) {
          case CompileOutcome.published:
            break;
          case CompileOutcome.cancelled:
            throw const CancelledException('Video compile was cancelled');
          case CompileOutcome.failed:
            return _VideoCompileResult.failed('the video could not be encoded');
        }
      }

      return _VideoCompileResult.success();
    } catch (e) {
      if (e is CancelledException) rethrow;
      LogService.instance.log('StabilizationService: Error creating video: $e');
      return _VideoCompileResult.failed(e.toString());
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
      LogService.instance.log(
        'StabilizationService: Emitting progress state=${progress.state.name}',
      );
      _progressController.add(progress);
    } else {
      LogService.instance.log(
        'StabilizationService: WARNING: progressController is closed, cannot emit ${progress.state.name}',
      );
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

  /// Release resources held by the run identified by [myGen].
  ///
  /// Each call captures its run's generation at [startStabilization] entry
  /// and passes it here. The checks against [_currentGen] make this safe to
  /// resume after async awaits: if a newer run has taken over, we bail out
  /// instead of clobbering its fresh [_currentStabilizer] / [_currentToken] /
  /// [_currentSettings], or emitting a stale [StabilizationProgress.idle].
  Future<void> _cleanup(int myGen, FaceStabilizer? stabilizer) async {
    // This run's own stabilizer; never a newer run's.
    await stabilizer?.dispose();
    if (myGen != _currentGen) return;
    _currentStabilizer = null;
    _currentToken = null;
    _currentSettings = null;
    await WakelockPlus.disable();
    if (myGen != _currentGen) return;

    // Reset to idle after a short delay to allow UI to update
    await Future.delayed(const Duration(milliseconds: 100));
    if (myGen != _currentGen) return;
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

/// Holds all video configuration values loaded from the DB and settings.
/// Used to avoid duplicating the loading logic between [StabilizationService._checkIfVideoNeeded]
/// and [StabilizationService._tryCreateVideo].
class _VideoConfig {
  const _VideoConfig({
    required this.newestVideo,
    required this.stabPhotoCount,
    required this.isTransparent,
    required this.effectiveCodec,
    required this.videoFileExists,
    required this.videoIsNull,
    required this.settingsHaveChanged,
    required this.newVideoNeeded,
  });

  final Map<String, dynamic>? newestVideo;
  final int stabPhotoCount;
  final bool isTransparent;
  final VideoCodec effectiveCodec;
  final bool videoFileExists;
  final bool videoIsNull;
  final bool settingsHaveChanged;
  final bool newVideoNeeded;
}

class _VideoCompileResult {
  final bool succeeded;
  final String? errorMessage;

  _VideoCompileResult._(this.succeeded, this.errorMessage);

  factory _VideoCompileResult.success() => _VideoCompileResult._(true, null);
  factory _VideoCompileResult.failed(String msg) =>
      _VideoCompileResult._(false, msg);
}

/// Mutable holder for progress tracking across multiple stabilization batches.
class _ProgressState {
  int photosDone;
  int totalPhotoCount;

  _ProgressState({required this.photosDone, required this.totalPhotoCount});
}
