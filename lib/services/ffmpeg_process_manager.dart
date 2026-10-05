import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/log_callback.dart';

import 'log_service.dart';

/// Tracks running FFmpeg encodes (FFmpegKit sessions on mobile, ffmpeg
/// processes on desktop) so they can be cancelled and awaited.
///
/// Each encode is an [FFmpegRun] that is registered before FFmpeg starts, so
/// a cancel that arrives while FFmpeg is still launching is applied as soon
/// as there is something to cancel. A run only ever removes itself.
///
/// Usage:
/// ```dart
/// // Mobile:
/// final run = FFmpegProcessManager.instance.startSession(command);
/// // Desktop:
/// final run = await FFmpegProcessManager.instance.startProcess(exe, args);
///
/// final exitCode = await run.exitCode;
/// if (run.cancelRequested) { /* discard the output */ }
///
/// // Cancel everything and wait for FFmpeg to actually exit:
/// await FFmpegProcessManager.instance.killActiveProcess();
/// ```
class FFmpegProcessManager {
  FFmpegProcessManager._internal();

  static final FFmpegProcessManager _instance =
      FFmpegProcessManager._internal();

  /// The singleton instance.
  static FFmpegProcessManager get instance => _instance;

  final Set<FFmpegRun> _runs = {};

  /// Whether any FFmpeg encode is still running.
  bool get hasActiveProcess => _runs.isNotEmpty;

  /// Starts [command] as an FFmpegKit session (mobile).
  ///
  /// Returns as soon as the run is registered; await [FFmpegRun.exitCode]
  /// for completion. [onLog] receives this session's log lines only.
  FFmpegRun startSession(String command, {LogCallback? onLog}) {
    final run = FFmpegRun._(this);
    _runs.add(run);
    LogService.instance.log('FFmpegProcessManager: Starting mobile session');
    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      run._finish(returnCode?.getValue() ?? -1);
    }, onLog).then(
      (session) {
        final sessionId = session.getSessionId();
        if (sessionId != null) run._attachSession(sessionId);
      },
      onError: (Object e) {
        LogService.instance.log(
          'FFmpegProcessManager: Failed to start mobile session: $e',
        );
        run._finish(-1);
      },
    );
    return run;
  }

  /// Starts an ffmpeg process (desktop) and tracks it until it exits.
  ///
  /// The started process is available as [FFmpegRun.process] for reading its
  /// output. Throws if the process cannot be started.
  Future<FFmpegRun> startProcess(
    String executable,
    List<String> arguments,
  ) async {
    final run = FFmpegRun._(this);
    _runs.add(run);
    try {
      final proc = await Process.start(
        executable,
        arguments,
        runInShell: false,
      );
      LogService.instance.log(
        'FFmpegProcessManager: Started desktop process (PID: ${proc.pid})',
      );
      run._attachProcess(proc);
      unawaited(proc.exitCode.then(run._finish));
      return run;
    } catch (_) {
      run._finish(-1);
      rethrow;
    }
  }

  /// Cancels every running FFmpeg encode and returns once all have exited.
  ///
  /// Returns true if anything was running.
  Future<bool> killActiveProcess() async {
    final runs = _runs.toList();
    if (runs.isEmpty) return false;
    LogService.instance.log(
      'FFmpegProcessManager: Cancelling ${runs.length} FFmpeg run(s)',
    );
    await Future.wait(runs.map((run) => run.cancel()));
    LogService.instance.log('FFmpegProcessManager: All FFmpeg runs exited');
    return true;
  }

  /// Forgets all runs without cancelling them. For tests only.
  void clear() => _runs.clear();
}

/// One FFmpeg encode tracked by [FFmpegProcessManager].
class FFmpegRun {
  FFmpegRun._(this._manager);

  final FFmpegProcessManager _manager;
  final Completer<int> _exit = Completer<int>();
  int? _sessionId;
  Process? _process;
  bool _cancelRequested = false;

  /// Completes with FFmpeg's exit code once it has actually exited.
  ///
  /// A cancelled FFmpegKit session exits with 255; a killed desktop process
  /// exits with a non-zero code. A run cancelled after FFmpeg already
  /// finished can still exit with 0, so also check [cancelRequested].
  Future<int> get exitCode => _exit.future;

  /// Whether FFmpeg has exited.
  bool get isFinished => _exit.isCompleted;

  /// Whether cancellation was requested for this run.
  bool get cancelRequested => _cancelRequested;

  /// The desktop process, once started.
  Process? get process => _process;

  /// Requests cancellation and returns once FFmpeg has exited.
  Future<void> cancel() async {
    if (!_cancelRequested) {
      _cancelRequested = true;
      _signalCancel();
      unawaited(_resignalUntilExited());
    }
    await _exit.future;
  }

  /// FFmpegKit marks a session as running just before FFmpeg starts, which
  /// overwrites a cancel that reached it earlier. Repeat the cancel until
  /// FFmpeg has exited.
  Future<void> _resignalUntilExited() async {
    while (!_exit.isCompleted) {
      await Future.any([
        _exit.future,
        Future<void>.delayed(const Duration(milliseconds: 500)),
      ]);
      _signalCancel(quiet: true);
    }
  }

  void _signalCancel({bool quiet = false}) {
    if (_exit.isCompleted) return;
    final sessionId = _sessionId;
    if (sessionId != null) {
      if (!quiet) {
        LogService.instance.log(
          'FFmpegProcessManager: Cancelling mobile FFmpegKit session $sessionId',
        );
      }
      unawaited(
        FFmpegKit.cancel(sessionId).catchError((Object e) {
          LogService.instance.log(
            'FFmpegProcessManager: Cancel of session $sessionId failed: $e',
          );
        }),
      );
    }
    final proc = _process;
    if (proc != null) {
      if (!quiet) {
        LogService.instance.log(
          'FFmpegProcessManager: Killing desktop process (PID: ${proc.pid})',
        );
      }
      proc.kill(ProcessSignal.sigkill);
    }
  }

  void _attachSession(int sessionId) {
    _sessionId = sessionId;
    if (_cancelRequested) _signalCancel();
  }

  void _attachProcess(Process proc) {
    _process = proc;
    if (_cancelRequested) _signalCancel();
  }

  void _finish(int exitCode) {
    if (!_exit.isCompleted) _exit.complete(exitCode);
    _manager._runs.remove(this);
  }
}
