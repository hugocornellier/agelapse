import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/ffmpeg_process_manager.dart';

/// Unit tests for FFmpegProcessManager.
///
/// The process tests use `sleep`/`true` in place of ffmpeg: what matters is
/// that cancelling waits for the process to actually exit, and that a run
/// only ever removes itself from tracking.
void main() {
  final String? noPosixTools = Platform.isWindows
      ? 'Uses POSIX sleep/true'
      : null;

  group('FFmpegProcessManager Singleton', () {
    test('instance returns the same object', () {
      final instance1 = FFmpegProcessManager.instance;
      final instance2 = FFmpegProcessManager.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('FFmpegProcessManager Initial State', () {
    setUp(() {
      // Ensure clean state
      FFmpegProcessManager.instance.clear();
    });

    test('hasActiveProcess returns false initially', () {
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Clear', () {
    test('clear resets state', () {
      FFmpegProcessManager.instance.clear();
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });

    test('clear is idempotent', () {
      FFmpegProcessManager.instance.clear();
      FFmpegProcessManager.instance.clear();
      FFmpegProcessManager.instance.clear();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Kill', () {
    setUp(() {
      FFmpegProcessManager.instance.clear();
    });

    test('killActiveProcess returns false when no process is active', () async {
      final killed = await FFmpegProcessManager.instance.killActiveProcess();
      expect(killed, isFalse);
    });

    test('killActiveProcess is safe to call multiple times', () async {
      await FFmpegProcessManager.instance.killActiveProcess();
      await FFmpegProcessManager.instance.killActiveProcess();
      await FFmpegProcessManager.instance.killActiveProcess();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });

    test('concurrent kills are safe', () async {
      final results = await Future.wait([
        FFmpegProcessManager.instance.killActiveProcess(),
        FFmpegProcessManager.instance.killActiveProcess(),
        FFmpegProcessManager.instance.killActiveProcess(),
      ]);

      expect(results.length, 3);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Runs', () {
    setUp(() {
      FFmpegProcessManager.instance.clear();
    });

    test(
      'killActiveProcess returns only after the process has exited',
      () async {
        final run = await FFmpegProcessManager.instance.startProcess('sleep', [
          '30',
        ]);
        expect(FFmpegProcessManager.instance.hasActiveProcess, isTrue);

        final killed = await FFmpegProcessManager.instance.killActiveProcess();

        expect(killed, isTrue);
        expect(run.isFinished, isTrue);
        expect(run.cancelRequested, isTrue);
        expect(await run.exitCode, isNot(0));
        expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
      },
      skip: noPosixTools,
    );

    test(
      'a cancel requested while the process is starting is applied',
      () async {
        // The run is registered before Process.start resolves.
        final starting = FFmpegProcessManager.instance.startProcess('sleep', [
          '30',
        ]);

        final killed = await FFmpegProcessManager.instance.killActiveProcess();
        final run = await starting;

        expect(killed, isTrue);
        expect(run.isFinished, isTrue);
        expect(run.cancelRequested, isTrue);
        expect(await run.exitCode, isNot(0));
        expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
      },
      skip: noPosixTools,
    );

    test('a finishing run removes only itself', () async {
      final first = await FFmpegProcessManager.instance.startProcess('sleep', [
        '30',
      ]);
      final second = await FFmpegProcessManager.instance.startProcess('sleep', [
        '30',
      ]);

      await first.cancel();

      expect(first.isFinished, isTrue);
      expect(second.isFinished, isFalse);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isTrue);

      await FFmpegProcessManager.instance.killActiveProcess();
      expect(second.isFinished, isTrue);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    }, skip: noPosixTools);

    test('a run that exits normally is not reported as cancelled', () async {
      final run = await FFmpegProcessManager.instance.startProcess('true', []);

      expect(await run.exitCode, 0);
      expect(run.cancelRequested, isFalse);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    }, skip: noPosixTools);

    test('cancelling a finished run is harmless', () async {
      final run = await FFmpegProcessManager.instance.startProcess('true', []);
      await run.exitCode;

      await run.cancel();

      expect(await run.exitCode, 0);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    }, skip: noPosixTools);
  });
}
