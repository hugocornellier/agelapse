import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/video_utils.dart';
import 'cancellation_token.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// What happened to a compile request.
enum CompileOutcome {
  /// A new video was encoded, checked, and moved into place.
  published,

  /// Cancelled, or superseded by a newer request, before publishing. The
  /// previous video is untouched.
  cancelled,

  /// FFmpeg failed or the result didn't pass its checks. The previous video
  /// is untouched.
  failed,
}

/// One compile request, as seen by the code that runs it.
class CompileJob {
  CompileJob(this.id, this.projectId, this.reason);

  final int id;
  final int projectId;
  final String reason;

  /// Cancelled when the job is superseded or the app asks to stop. The encode
  /// listens to it to stop FFmpeg.
  final CancellationToken token = CancellationToken();

  bool get isCancelled => token.isCancelled;
}

/// Runs every video compile in the app, one at a time.
///
/// AgeLapse 2.7.0 could start a new encode while a "cancelled" one was still
/// writing the same agelapse.mp4. The two corrupted the file (most frames
/// decoded black), and both were recorded as the current video. Here:
/// - Only one encode runs at a time, app-wide. A new request cancels the
///   running one and waits until its FFmpeg has actually exited.
/// - Only the newest request runs; requests superseded while waiting are
///   dropped.
/// - Encodes write to a private file and only replace the video when they
///   finish cleanly and are still wanted (see [VideoUtils.createTimelapse]).
class VideoCompileCoordinator {
  VideoCompileCoordinator._();

  static final VideoCompileCoordinator instance = VideoCompileCoordinator._();

  /// Bumped when published videos from earlier versions must be rebuilt.
  /// 2: videos from before compiles were serialized may be corrupted.
  static const int _publishVersion = 2;
  static const String publishVersionSetting = 'video_publish_version';

  /// Runs one job. Replaced in tests.
  @visibleForTesting
  Future<CompileOutcome> Function(
    CompileJob job,
    void Function(int frame)? onProgress,
  )
  runJob = VideoUtils.compileForJob;

  int _nextJobId = 0;
  CompileJob? _active;
  final List<CompileJob> _waiting = [];
  Future<void> _tail = Future<void>.value();

  /// Whether a compile is running or waiting to run.
  bool get isBusy => _active != null || _waiting.isNotEmpty;

  /// The project of the running compile, if any.
  int? get activeProjectId => _active?.projectId;

  /// Compiles [projectId]'s video.
  ///
  /// Cancels the running compile and any waiting ones, waits for the running
  /// one to stop, then runs this one unless a newer request superseded it
  /// meanwhile.
  Future<CompileOutcome> compile(
    int projectId, {
    void Function(int frame)? onProgress,
    required String reason,
  }) async {
    final job = CompileJob(++_nextJobId, projectId, reason);
    _cancelOutstanding('superseded by job ${job.id} ($reason)');
    _waiting.add(job);
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      _waiting.remove(job);
      if (job.isCancelled) {
        LogService.instance.log(
          '[COMPILE] Job ${job.id} dropped before starting (project $projectId)',
        );
        return CompileOutcome.cancelled;
      }
      _active = job;
      LogService.instance.log(
        '[COMPILE] Job ${job.id} started: project $projectId, reason: $reason',
      );
      final outcome = await runJob(job, onProgress);
      LogService.instance.log(
        '[COMPILE] Job ${job.id} finished: ${outcome.name}',
      );
      return outcome;
    } catch (e, stackTrace) {
      LogService.instance.log('[COMPILE] Job ${job.id} threw: $e\n$stackTrace');
      return CompileOutcome.failed;
    } finally {
      _waiting.remove(job);
      if (identical(_active, job)) _active = null;
      done.complete();
    }
  }

  /// Cancels the running compile and any waiting ones, and returns once the
  /// running one has stopped (FFmpeg exited, private output discarded).
  Future<void> cancelAll(String reason) async {
    final tail = _tail;
    _cancelOutstanding(reason);
    await tail;
  }

  void _cancelOutstanding(String reason) {
    final active = _active;
    if (active != null && !active.isCancelled) {
      LogService.instance.log('[COMPILE] Cancelling job ${active.id}: $reason');
      active.token.cancel();
    }
    for (final job in _waiting) {
      job.token.cancel();
    }
  }

  /// Startup housekeeping. Run once, before any compile:
  /// - deletes encode output left by compiles that never finished (the app
  ///   was killed or suspended mid-encode);
  /// - once per [_publishVersion], marks every existing video for a rebuild.
  ///   Videos made before compiles were serialized may be corrupted (e.g.
  ///   mostly black) while their records say they are current.
  Future<void> runStartupMaintenance() async {
    try {
      final projects = await DB.instance.getAllProjects();
      for (final project in projects) {
        await VideoUtils.deleteAbandonedOutputs(project['id'] as int);
      }

      final stored = await DB.instance.getSettingValueByTitle(
        publishVersionSetting,
      );
      if ((int.tryParse(stored) ?? 0) >= _publishVersion) return;
      var marked = 0;
      for (final project in projects) {
        final projectId = project['id'] as int;
        if (await DB.instance.getNewestVideoByProjectId(projectId) != null) {
          await DB.instance.setNewVideoNeeded(projectId);
          marked++;
        }
      }
      await DB.instance.setSettingByTitle(
        publishVersionSetting,
        '$_publishVersion',
      );
      LogService.instance.log(
        '[COMPILE] Video publish version $_publishVersion: marked $marked '
        'video(s) for a rebuild',
      );
    } catch (e) {
      LogService.instance.log('[COMPILE] Startup maintenance failed: $e');
    }
  }
}
