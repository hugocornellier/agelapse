import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/cancellation_token.dart';
import 'package:agelapse/services/crash_loop_guard.dart';

/// Unit tests for [CrashLoopGuard].
///
/// Work that kills the app (a native crash, or the OS killing it for memory)
/// used to restart on every launch, because it still counted as unfinished
/// (#15, #42). The guard notes work before it starts and acts on notes still
/// there at the next launch. A crash is simulated by copying the notes at the
/// moment the work is in flight ([_Storage.afterCrash]) and starting a new
/// guard from the copy, the way a new app process would: the old guard's
/// work never finishes and its notes are never cleaned up.
void main() {
  group('compiles', () {
    test('a compile that finishes leaves no note', () async {
      final storage = _Storage();
      final guard = _launch(storage);

      expect(await guard.runCompile(1, () async => 'published'), 'published');

      expect(storage.projects, isEmpty);
      expect(await _launch(storage).isAutoCompilePaused(1), isFalse);
    });

    test('after one unfinished compile, the next launch tries again', () async {
      final storage = await _compileCrash(_Storage(), projectId: 1);

      expect(await _launch(storage).isAutoCompilePaused(1), isFalse);
    });

    test(
      'after two unfinished compiles in a row, auto-compile is paused',
      () async {
        var storage = await _compileCrash(_Storage(), projectId: 1);
        storage = await _compileCrash(storage, projectId: 1);

        final guard = _launch(storage);
        expect(await guard.isAutoCompilePaused(1), isTrue);
        expect(await guard.isAutoCompilePaused(2), isFalse);
      },
    );

    test('a compile that finishes resumes auto-compile', () async {
      var storage = await _compileCrash(_Storage(), projectId: 1);
      storage = await _compileCrash(storage, projectId: 1);
      final guard = _launch(storage);
      expect(await guard.isAutoCompilePaused(1), isTrue);

      // The user taps Compile Video, and this time the app survives.
      await guard.runCompile(1, () async => 'failed');

      expect(await guard.isAutoCompilePaused(1), isFalse);
      expect(await _launch(storage).isAutoCompilePaused(1), isFalse);
    });

    test('a compile that throws still counts as finished', () async {
      final storage = _Storage();
      final guard = _launch(storage);

      await expectLater(
        guard.runCompile<String>(1, () async => throw StateError('boom')),
        throwsStateError,
      );

      expect(storage.projects, isEmpty);
    });

    test('a paused project crashing again stays paused', () async {
      var storage = await _compileCrash(_Storage(), projectId: 1);
      storage = await _compileCrash(storage, projectId: 1);
      storage = await _compileCrash(storage, projectId: 1);

      expect(await _launch(storage).isAutoCompilePaused(1), isTrue);
    });

    test('an app update gives auto-compile a fresh start', () async {
      var storage = await _compileCrash(_Storage(), projectId: 1);
      storage = await _compileCrash(storage, projectId: 1);
      expect(await _launch(storage).isAutoCompilePaused(1), isTrue);

      // Updated: not paused, and its count starts over.
      expect(
        await _launch(storage, version: '2.8.1+49').isAutoCompilePaused(1),
        isFalse,
      );
      storage = await _compileCrash(storage, projectId: 1, version: '2.8.1+49');
      expect(
        await _launch(storage, version: '2.8.1+49').isAutoCompilePaused(1),
        isFalse,
      );
    });

    test('compiles are not guarded where FFmpeg is its own process', () async {
      var storage = await _compileCrash(
        _Storage(),
        projectId: 1,
        guardCompiles: false,
      );
      storage = await _compileCrash(
        storage,
        projectId: 1,
        guardCompiles: false,
      );

      expect(storage.projects, isEmpty);
      expect(
        await _launch(storage, guardCompiles: false).isAutoCompilePaused(1),
        isFalse,
      );
    });
  });

  group('photos', () {
    test('a photo that settles leaves no note', () async {
      final storage = _Storage();
      final guard = _launch(storage);

      final result = await guard.runPhoto(
        1,
        'a',
        () async => true,
        settled: (_) => true,
      );

      expect(result, isTrue);
      expect(storage.projects, isEmpty);
    });

    test('the note is saved before the photo starts', () async {
      final storage = _Storage();
      final guard = _launch(storage);
      Object? inFlightWhenStarted;

      await guard.runPhoto(1, 'a', () async {
        inFlightWhenStarted = storage.projects['1']?['photosInFlight'];
        return true;
      }, settled: (_) => true);

      expect(inFlightWhenStarted, ['a']);
    });

    test(
      'the first death makes a photo run alone, the second marks it failed',
      () async {
        final failed = <String>[];
        var storage = await _photoCrash(
          _Storage(),
          projectId: 1,
          photos: ['a'],
        );

        final second = _launch(storage, failed: failed);
        expect(await second.mustStabilizeAlone(1, 'a'), isTrue);
        expect(await second.mustStabilizeAlone(1, 'b'), isFalse);
        expect(failed, isEmpty);

        storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
        await _launch(storage, failed: failed).start();
        expect(failed, ['1:a']);
      },
    );

    test(
      'a photo marked failed is not marked again on later launches',
      () async {
        final failed = <String>[];
        var storage = await _photoCrash(
          _Storage(),
          projectId: 1,
          photos: ['a'],
        );
        storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
        await _launch(storage, failed: failed).start();
        expect(failed, ['1:a']);

        // Say the user retries it later: it must not be re-marked at launch.
        await _launch(storage, failed: failed).start();
        await _launch(storage, failed: failed).start();
        expect(failed, ['1:a']);
      },
    );

    test(
      'a photo retried after being marked failed is marked again after one more death',
      () async {
        final failed = <String>[];
        var storage = await _photoCrash(
          _Storage(),
          projectId: 1,
          photos: ['a'],
        );
        storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
        await _launch(storage, failed: failed).start();

        expect(await _launch(storage).mustStabilizeAlone(1, 'a'), isTrue);
        storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
        await _launch(storage, failed: failed).start();
        expect(failed, ['1:a', '1:a']);
      },
    );

    test('a photo that settles after a death is cleared', () async {
      final storage = await _photoCrash(
        _Storage(),
        projectId: 1,
        photos: ['a'],
      );
      final guard = _launch(storage);

      await guard.runPhoto(1, 'a', () async => true, settled: (_) => true);

      expect(await guard.mustStabilizeAlone(1, 'a'), isFalse);
      expect(storage.projects, isEmpty);
    });

    test('a photo that does not settle keeps its death', () async {
      final failed = <String>[];
      var storage = await _photoCrash(_Storage(), projectId: 1, photos: ['a']);
      final guard = _launch(storage, failed: failed);

      // Cancelled, or left to a later step.
      await guard.runPhoto(1, 'a', () async => false, settled: (ok) => ok);
      expect(await guard.mustStabilizeAlone(1, 'a'), isTrue);

      storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
      await _launch(storage, failed: failed).start();
      expect(failed, ['1:a']);
    });

    test(
      'a CancelledException keeps the death, any other exception settles',
      () async {
        final storage = await _photoCrash(
          _Storage(),
          projectId: 1,
          photos: ['a'],
        );
        final guard = _launch(storage);

        await expectLater(
          guard.runPhoto<bool>(
            1,
            'a',
            () async => throw const CancelledException(),
            settled: (_) => true,
          ),
          throwsA(isA<CancelledException>()),
        );
        expect(await guard.mustStabilizeAlone(1, 'a'), isTrue);

        await expectLater(
          guard.runPhoto<bool>(
            1,
            'a',
            () async => throw StateError('decode failed'),
            settled: (_) => true,
          ),
          throwsStateError,
        );
        expect(await guard.mustStabilizeAlone(1, 'a'), isFalse);
      },
    );

    test(
      'every photo in flight when the app died gets a death, none is failed yet',
      () async {
        final failed = <String>[];
        final storage = await _photoCrash(
          _Storage(),
          projectId: 1,
          photos: ['a', 'b', 'c'],
        );

        final guard = _launch(storage, failed: failed);
        for (final photo in ['a', 'b', 'c']) {
          expect(await guard.mustStabilizeAlone(1, photo), isTrue);
        }
        expect(failed, isEmpty);
      },
    );

    test('a photo in two runs at once stays noted until both end', () async {
      final storage = _Storage();
      final guard = _launch(storage);
      final first = Completer<bool>();
      final second = Completer<bool>();
      final firstRun = guard.runPhoto(
        1,
        'a',
        () => first.future,
        settled: (_) => true,
      );
      final secondStarted = Completer<void>();
      unawaited(
        guard.runPhoto(1, 'a', () {
          secondStarted.complete();
          return second.future;
        }, settled: (_) => true),
      );
      await secondStarted.future;

      first.complete(true);
      await firstRun;

      final next = _launch(storage.afterCrash());
      expect(await next.mustStabilizeAlone(1, 'a'), isTrue);
    });

    test('photos without a timestamp run unguarded', () async {
      final storage = _Storage();
      final guard = _launch(storage);

      final result = await guard.runPhoto(
        1,
        null,
        () async => 'done',
        settled: (_) => true,
      );

      expect(result, 'done');
      expect(storage.writes, 0);
      expect(await guard.mustStabilizeAlone(1, null), isFalse);
    });
  });

  group('robustness', () {
    test('unreadable notes are ignored and replaced', () async {
      final storage = _Storage('{not json');
      final guard = _launch(storage);

      await guard.start();
      expect(await guard.isAutoCompilePaused(1), isFalse);
      await guard.runPhoto(1, 'a', () async => true, settled: (_) => true);
      expect(jsonDecode(storage.contents!), isA<Map<String, dynamic>>());
    });

    test('malformed entries are skipped, valid ones kept', () async {
      final storage = _Storage(
        jsonEncode({
          'version': 1,
          'projects': {
            'nope': {'compilesUnfinished': 5},
            '2': 'not a map',
            '3': {
              'compilesUnfinished': 'two',
              'photosInFlight': ['a', 7],
              'photoDeaths': {'b': 'x'},
            },
          },
        }),
      );
      final guard = _launch(storage);

      expect(await guard.isAutoCompilePaused(3), isFalse);
      expect(await guard.mustStabilizeAlone(3, 'a'), isTrue);
      expect(await guard.mustStabilizeAlone(3, 'b'), isFalse);
    });

    test('a store that fails never breaks the work', () async {
      final storage = _Storage()
        ..failReads = true
        ..failWrites = true;
      final guard = _launch(storage);

      expect(await guard.runCompile(1, () async => 'published'), 'published');
      expect(
        await guard.runPhoto(1, 'a', () async => 1, settled: (_) => true),
        1,
      );
      expect(await guard.isAutoCompilePaused(1), isFalse);
    });

    test('a failure to mark a photo does not stop the launch', () async {
      var storage = await _photoCrash(_Storage(), projectId: 1, photos: ['a']);
      storage = await _photoCrash(storage, projectId: 1, photos: ['a']);
      final guard = CrashLoopGuard.forTesting(
        store: storage,
        markPhotoFailed: (_, _) async => throw StateError('db closed'),
        appVersion: () async => _version,
        active: true,
        guardCompiles: true,
      );

      await guard.start();
      expect(
        await guard.runPhoto(1, 'b', () async => 1, settled: (_) => true),
        1,
      );
    });

    test('an inactive guard runs work without notes', () async {
      final storage = _Storage();
      final guard = CrashLoopGuard.forTesting(
        store: storage,
        markPhotoFailed: (_, _) async {},
        appVersion: () async => _version,
        active: false,
      );

      await guard.runCompile(1, () async => 1);
      await guard.runPhoto(1, 'a', () async => 1, settled: (_) => true);

      expect(storage.writes, 0);
      expect(await guard.isAutoCompilePaused(1), isFalse);
      expect(await guard.mustStabilizeAlone(1, 'a'), isFalse);
    });

    test('writes made while another is in progress are combined', () async {
      final storage = _Storage();
      final guard = _launch(storage);
      await guard.start();
      final gate = Completer<void>();
      storage.writeGate = gate.future;

      final notedAtStart = <String, Object?>{};
      final runs = [
        for (final photo in ['a', 'b', 'c'])
          guard.runPhoto(1, photo, () async {
            notedAtStart[photo] = storage.projects['1']?['photosInFlight'];
            return true;
          }, settled: (_) => true),
      ];
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait(runs);

      // Three starts and three ends; starts made during the held write share
      // the next one.
      expect(storage.writes, lessThan(6));
      for (final photo in ['a', 'b', 'c']) {
        expect(
          notedAtStart[photo],
          contains(photo),
          reason: '$photo started before its note was saved',
        );
      }
      expect(storage.projects, isEmpty);
    });

    test('notes from other projects are kept', () async {
      var storage = await _compileCrash(_Storage(), projectId: 1);
      storage = await _compileCrash(storage, projectId: 1);
      storage = await _photoCrash(storage, projectId: 2, photos: ['a']);

      final guard = _launch(storage);
      await guard.runPhoto(2, 'a', () async => true, settled: (_) => true);

      expect(await guard.isAutoCompilePaused(1), isTrue);
      expect(await _launch(storage).isAutoCompilePaused(1), isTrue);
    });
  });
}

const String _version = '2.8.0+48';

CrashLoopGuard _launch(
  _Storage storage, {
  String version = _version,
  List<String>? failed,
  bool guardCompiles = true,
}) => CrashLoopGuard.forTesting(
  store: storage,
  markPhotoFailed: (projectId, timestamp) async {
    failed?.add('$projectId:$timestamp');
  },
  appVersion: () async => version,
  active: true,
  guardCompiles: guardCompiles,
);

/// Launches the app on [storage], starts a compile of [projectId], and kills
/// the app while it runs. Returns what the next launch finds.
Future<_Storage> _compileCrash(
  _Storage storage, {
  required int projectId,
  String version = _version,
  bool guardCompiles = true,
}) async {
  final guard = _launch(
    storage,
    version: version,
    guardCompiles: guardCompiles,
  );
  final started = Completer<void>();
  unawaited(
    guard.runCompile(projectId, () {
      started.complete();
      return Completer<void>().future;
    }),
  );
  await started.future;
  return storage.afterCrash();
}

/// Launches the app on [storage], starts stabilizing [photos] at once, and
/// kills the app while they run. Returns what the next launch finds.
Future<_Storage> _photoCrash(
  _Storage storage, {
  required int projectId,
  required List<String> photos,
}) async {
  final guard = _launch(storage);
  for (final photo in photos) {
    final started = Completer<void>();
    unawaited(
      guard.runPhoto(projectId, photo, () {
        started.complete();
        return Completer<bool>().future;
      }, settled: (_) => true),
    );
    await started.future;
  }
  return storage.afterCrash();
}

/// Stands in for the notes file.
class _Storage implements CrashGuardStore {
  _Storage([this.contents]);

  String? contents;
  int writes = 0;
  bool failReads = false;
  bool failWrites = false;

  /// When set, writes wait for it.
  Future<void>? writeGate;

  /// The saved notes per project id.
  Map<String, dynamic> get projects => contents == null
      ? const {}
      : (jsonDecode(contents!) as Map<String, dynamic>)['projects']
            as Map<String, dynamic>;

  @override
  Future<String?> read() async {
    if (failReads) throw const FileSystemException('read failed');
    return contents;
  }

  @override
  Future<void> write(String value) async {
    if (failWrites) throw const FileSystemException('write failed');
    await writeGate;
    writes++;
    contents = value;
  }

  /// What a new app process finds if this one dies right now.
  _Storage afterCrash() => _Storage(contents);
}
