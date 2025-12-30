import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/ffmpeg_process_manager.dart';

/// Unit tests for FFmpegProcessManager.
/// Tests singleton behavior, process registration, and cleanup.
void main() {
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
      // Should not throw when called multiple times
      FFmpegProcessManager.instance.clear();
      FFmpegProcessManager.instance.clear();
      FFmpegProcessManager.instance.clear();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Unregister', () {
    setUp(() {
      FFmpegProcessManager.instance.clear();
    });

    test('unregisterProcess works without active process', () {
      // Should not throw
      FFmpegProcessManager.instance.unregisterProcess();
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });

    test('unregisterSession works without active session', () {
      // Should not throw
      FFmpegProcessManager.instance.unregisterSession();
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });

    test('unregister methods are idempotent', () {
      // Should not throw when called multiple times
      FFmpegProcessManager.instance.unregisterProcess();
      FFmpegProcessManager.instance.unregisterProcess();
      FFmpegProcessManager.instance.unregisterSession();
      FFmpegProcessManager.instance.unregisterSession();

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
      // Should not throw when called repeatedly
      await FFmpegProcessManager.instance.killActiveProcess();
      await FFmpegProcessManager.instance.killActiveProcess();
      await FFmpegProcessManager.instance.killActiveProcess();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager State Transitions', () {
    setUp(() {
      FFmpegProcessManager.instance.clear();
    });

    test('state is consistent after clear and kill sequence', () async {
      FFmpegProcessManager.instance.clear();
      await FFmpegProcessManager.instance.killActiveProcess();
      FFmpegProcessManager.instance.clear();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });

    test('unregister after kill maintains clean state', () async {
      await FFmpegProcessManager.instance.killActiveProcess();
      FFmpegProcessManager.instance.unregisterProcess();
      FFmpegProcessManager.instance.unregisterSession();

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Concurrency', () {
    setUp(() {
      FFmpegProcessManager.instance.clear();
    });

    test('concurrent kills are safe', () async {
      // Simulate concurrent kill attempts
      final futures = [
        FFmpegProcessManager.instance.killActiveProcess(),
        FFmpegProcessManager.instance.killActiveProcess(),
        FFmpegProcessManager.instance.killActiveProcess(),
      ];

      final results = await Future.wait(futures);

      // All should complete without throwing
      expect(results.length, 3);
      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });

  group('FFmpegProcessManager Edge Cases', () {
    test('works correctly after repeated clear/kill cycles', () async {
      for (int i = 0; i < 10; i++) {
        FFmpegProcessManager.instance.clear();
        await FFmpegProcessManager.instance.killActiveProcess();
        FFmpegProcessManager.instance.unregisterProcess();
        FFmpegProcessManager.instance.unregisterSession();
      }

      expect(FFmpegProcessManager.instance.hasActiveProcess, isFalse);
    });
  });
}
