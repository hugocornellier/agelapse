import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';

import 'log_service.dart';

/// Manages active FFmpeg processes and provides instant kill capability.
///
/// This singleton tracks FFmpeg processes on desktop (via Process) and
/// FFmpegKit sessions on mobile, allowing them to be terminated instantly
/// when cancellation is requested.
///
/// Usage:
/// ```dart
/// // Desktop:
/// final proc = await Process.start('ffmpeg', args);
/// FFmpegProcessManager.instance.registerProcess(proc);
///
/// // Mobile:
/// final session = await FFmpegKit.execute(command);
/// FFmpegProcessManager.instance.registerSession(session);
///
/// // Cancel:
/// await FFmpegProcessManager.instance.killActiveProcess();
/// ```
class FFmpegProcessManager {
  FFmpegProcessManager._internal();

  static final FFmpegProcessManager _instance =
      FFmpegProcessManager._internal();

  /// The singleton instance.
  static FFmpegProcessManager get instance => _instance;

  /// Currently active desktop FFmpeg process.
  Process? _activeProcess;

  /// Currently active mobile FFmpeg session.
  FFmpegSession? _activeSession;

  /// Whether there's an active process or session.
  bool get hasActiveProcess => _activeProcess != null || _activeSession != null;

  /// Register a desktop FFmpeg process for tracking.
  ///
  /// Call this immediately after starting an FFmpeg process.
  void registerProcess(Process proc) {
    _activeProcess = proc;
    LogService.instance.log(
      'FFmpegProcessManager: Registered desktop process (PID: ${proc.pid})',
    );
  }

  /// Register a mobile FFmpeg session for tracking.
  ///
  /// Call this immediately after starting an FFmpegKit session.
  void registerSession(FFmpegSession session) {
    _activeSession = session;
    LogService.instance.log('FFmpegProcessManager: Registered mobile session');
  }

  /// Kill the active FFmpeg process or session instantly.
  ///
  /// On desktop, sends SIGKILL to terminate the process immediately.
  /// On mobile, cancels all active FFmpegKit sessions.
  ///
  /// Returns true if a process was killed, false if no process was active.
  Future<bool> killActiveProcess() async {
    bool killed = false;

    // Kill desktop process
    if (_activeProcess != null) {
      final pid = _activeProcess!.pid;
      LogService.instance.log(
        'FFmpegProcessManager: Killing desktop process (PID: $pid)',
      );
      try {
        // Use SIGKILL for instant termination
        final result = _activeProcess!.kill(ProcessSignal.sigkill);
        if (result) {
          LogService.instance.log(
            'FFmpegProcessManager: Desktop process killed successfully',
          );
          killed = true;
        } else {
          // Process may have already exited
          LogService.instance.log(
            'FFmpegProcessManager: Desktop process already terminated',
          );
        }
      } catch (e) {
        LogService.instance.log(
          'FFmpegProcessManager: Error killing desktop process: $e',
        );
      }
      _activeProcess = null;
    }

    // Cancel mobile session
    if (_activeSession != null) {
      LogService.instance.log(
        'FFmpegProcessManager: Cancelling mobile FFmpegKit session',
      );
      try {
        // Cancel all running FFmpegKit sessions
        await FFmpegKit.cancel();
        LogService.instance.log(
          'FFmpegProcessManager: Mobile session cancelled successfully',
        );
        killed = true;
      } catch (e) {
        LogService.instance.log(
          'FFmpegProcessManager: Error cancelling mobile session: $e',
        );
      }
      _activeSession = null;
    }

    return killed;
  }

  /// Clear references without killing processes.
  ///
  /// Use this only for cleanup when you're sure processes are already dead.
  void clear() {
    _activeProcess = null;
    _activeSession = null;
  }

  /// Unregister the desktop process (after it completes normally).
  void unregisterProcess() {
    _activeProcess = null;
  }

  /// Unregister the mobile session (after it completes normally).
  void unregisterSession() {
    _activeSession = null;
    LogService.instance.log(
      'FFmpegProcessManager: Mobile session unregistered',
    );
  }
}
