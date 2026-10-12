import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/crash_loop_guard.dart';
import 'package:agelapse/services/video_compile_coordinator.dart';
import 'package:agelapse/utils/video_utils.dart';

/// Unit tests for [VideoCompileCoordinator].
///
/// The coordinator exists because 2.7.0 let a new encode start while a
/// "cancelled" one was still writing the same file. These tests pin down its
/// guarantees with a fake job runner: one job at a time, a newer request
/// cancels the running one and only starts after it has stopped, superseded
/// waiting requests are dropped, and cancelAll waits for the stop.
void main() {
  late _FakeRunner runner;
  final coordinator = VideoCompileCoordinator.instance;

  setUp(() {
    runner = _FakeRunner();
    coordinator.runJob = runner.call;
  });

  tearDown(() {
    coordinator.runJob = VideoUtils.compileForJob;
  });

  test(
    'a newer request cancels the running job and starts after it stops',
    () async {
      runner.stopDelay = const Duration(milliseconds: 50);
      final first = coordinator.compile(1, reason: 'first');
      await _until(() => runner.started.contains(1));

      final second = coordinator.compile(2, reason: 'second');
      // The first job must stop completely before the second starts.
      await _until(() => runner.started.contains(2));
      expect(runner.events, ['start 1', 'stop 1', 'start 2']);

      runner.finish(2, CompileOutcome.published);
      expect(await first, CompileOutcome.cancelled);
      expect(await second, CompileOutcome.published);
      expect(coordinator.isBusy, isFalse);
    },
  );

  test(
    'a request superseded while waiting is dropped without running',
    () async {
      final first = coordinator.compile(1, reason: 'first');
      await _until(() => runner.started.contains(1));
      final second = coordinator.compile(2, reason: 'second');
      final third = coordinator.compile(3, reason: 'third');

      await _until(() => runner.started.contains(3));
      runner.finish(3, CompileOutcome.published);

      expect(await first, CompileOutcome.cancelled);
      expect(await second, CompileOutcome.cancelled);
      expect(await third, CompileOutcome.published);
      expect(runner.started, isNot(contains(2)));
    },
  );

  test('cancelAll returns only after the running job has stopped', () async {
    runner.stopDelay = const Duration(milliseconds: 100);
    final job = coordinator.compile(1, reason: 'job');
    await _until(() => runner.started.contains(1));

    await coordinator.cancelAll('test');

    expect(runner.events.last, 'stop 1');
    expect(coordinator.isBusy, isFalse);
    expect(await job, CompileOutcome.cancelled);
  });

  test('cancelAll with nothing running returns immediately', () async {
    await coordinator.cancelAll('test');
    expect(coordinator.isBusy, isFalse);
  });

  test(
    'a job that throws counts as failed and does not block the next',
    () async {
      runner.throwFor.add(1);
      expect(
        await coordinator.compile(1, reason: 'throws'),
        CompileOutcome.failed,
      );

      final next = coordinator.compile(2, reason: 'next');
      await _until(() => runner.started.contains(2));
      runner.finish(2, CompileOutcome.published);
      expect(await next, CompileOutcome.published);
    },
  );

  test('isBusy and activeProjectId track the running job', () async {
    final job = coordinator.compile(7, reason: 'job');
    await _until(() => runner.started.contains(7));
    expect(coordinator.isBusy, isTrue);
    expect(coordinator.activeProjectId, 7);

    runner.finish(7, CompileOutcome.published);
    await job;
    expect(coordinator.isBusy, isFalse);
    expect(coordinator.activeProjectId, isNull);
  });

  group('crash guard', () {
    final original = CrashLoopGuard.instance;
    late _MemoryStore store;

    setUp(() {
      store = _MemoryStore();
      CrashLoopGuard.instance = CrashLoopGuard.forTesting(
        store: store,
        markPhotoFailed: (_, _) async {},
        appVersion: () async => '2.8.0+48',
        active: true,
        guardCompiles: true,
      );
    });

    tearDown(() {
      CrashLoopGuard.instance = original;
    });

    test('a running job is noted, and the note goes when it ends', () async {
      final job = coordinator.compile(7, reason: 'job');
      await _until(() => runner.started.contains(7));
      expect(store.unfinishedCompiles(7), 1);

      runner.finish(7, CompileOutcome.failed);
      expect(await job, CompileOutcome.failed);
      expect(store.unfinishedCompiles(7), 0);
    });

    test('a job dropped before it starts is never noted', () async {
      final first = coordinator.compile(1, reason: 'first');
      await _until(() => runner.started.contains(1));
      final dropped = coordinator.compile(2, reason: 'dropped');
      final last = coordinator.compile(3, reason: 'last');
      await _until(() => runner.started.contains(3));

      expect(store.unfinishedCompiles(2), 0);
      runner.finish(3, CompileOutcome.published);
      expect(await first, CompileOutcome.cancelled);
      expect(await dropped, CompileOutcome.cancelled);
      expect(await last, CompileOutcome.published);
      expect(store.unfinishedCompiles(2), 0);
    });
  });
}

/// Stands in for the crash guard's notes file.
class _MemoryStore implements CrashGuardStore {
  String? contents;

  int unfinishedCompiles(int projectId) {
    if (contents == null) return 0;
    final projects = (jsonDecode(contents!) as Map)['projects'] as Map;
    return (projects['$projectId']?['compilesUnfinished'] as int?) ?? 0;
  }

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async {
    contents = value;
  }
}

/// Stands in for VideoUtils.compileForJob. A job runs until the test
/// finishes it, or until its token is cancelled, after [stopDelay] (FFmpeg
/// takes a moment to stop and finalize).
class _FakeRunner {
  final List<int> started = [];
  final List<String> events = [];
  final Set<int> throwFor = {};
  final Map<int, Completer<CompileOutcome>> _running = {};
  Duration stopDelay = Duration.zero;

  Future<CompileOutcome> call(
    CompileJob job,
    void Function(int frame)? onProgress,
  ) async {
    final id = job.projectId;
    started.add(id);
    events.add('start $id');
    if (throwFor.contains(id)) throw StateError('encode blew up');
    final completer = Completer<CompileOutcome>();
    _running[id] = completer;
    job.token.addListener(() async {
      await Future<void>.delayed(stopDelay);
      if (!completer.isCompleted) completer.complete(CompileOutcome.cancelled);
    });
    final outcome = await completer.future;
    if (outcome == CompileOutcome.cancelled) events.add('stop $id');
    return outcome;
  }

  void finish(int projectId, CompileOutcome outcome) =>
      _running[projectId]!.complete(outcome);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition never became true');
}
