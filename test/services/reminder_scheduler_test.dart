import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:agelapse/models/reminder_time.dart';
import 'package:agelapse/services/reminder_scheduler.dart';

class MockBackend extends Mock implements ReminderBackend {}

class FakeStore implements ReminderStore {
  FakeStore({
    this.enabled = true,
    List<ReminderProject>? projects,
    Map<int, ReminderTime>? times,
  }) : projectList = projects ?? const [],
       timeMap = times ?? const {};

  bool enabled;
  List<ReminderProject> projectList;
  Map<int, ReminderTime> timeMap;

  @override
  Future<bool> notificationsEnabled() async => enabled;

  @override
  Future<List<ReminderProject>> projects() async => projectList;

  @override
  Future<ReminderTime> timeFor(int projectId) async =>
      timeMap[projectId] ?? ReminderTime.defaultTime;
}

/// A backend that answers like a healthy Android 13+ device unless a test
/// overrides a call.
MockBackend healthyBackend({String zoneId = 'America/Halifax'}) {
  final backend = MockBackend();
  when(backend.initialize).thenAnswer((_) async {});
  when(backend.localZoneId).thenAnswer((_) async => zoneId);
  when(backend.notificationsAllowed).thenAnswer((_) async => true);
  when(backend.requestNotificationsPermission).thenAnswer((_) async => true);
  when(backend.canScheduleExact).thenAnswer((_) async => true);
  when(backend.requestExactAlarmsPermission).thenAnswer((_) async => true);
  when(
    () => backend.schedule(
      id: any(named: 'id'),
      title: any(named: 'title'),
      body: any(named: 'body'),
      payload: any(named: 'payload'),
      at: any(named: 'at'),
      exact: any(named: 'exact'),
    ),
  ).thenAnswer((_) async {});
  when(() => backend.cancel(any())).thenAnswer((_) async {});
  when(backend.cancelAll).thenAnswer((_) async {});
  when(backend.pendingIds).thenAnswer((_) async => const []);
  return backend;
}

ReminderScheduler schedulerWith(
  MockBackend backend,
  ReminderStore store, {
  bool active = true,
}) => ReminderScheduler.forTesting(
  backend: backend,
  store: store,
  active: active,
);

void verifyNeverScheduled(MockBackend backend) => verifyNever(
  () => backend.schedule(
    id: any(named: 'id'),
    title: any(named: 'title'),
    body: any(named: 'body'),
    payload: any(named: 'payload'),
    at: any(named: 'at'),
    exact: any(named: 'exact'),
  ),
);

/// Captures every schedule() call as (id, at, exact). Fails when there were
/// none; use [verifyNeverScheduled] for that.
List<({int id, tz.TZDateTime at, bool exact})> captureSchedules(
  MockBackend backend,
) {
  final captured = verify(
    () => backend.schedule(
      id: captureAny(named: 'id'),
      title: captureAny(named: 'title'),
      body: captureAny(named: 'body'),
      payload: captureAny(named: 'payload'),
      at: captureAny(named: 'at'),
      exact: captureAny(named: 'exact'),
    ),
  ).captured;
  final calls = <({int id, tz.TZDateTime at, bool exact})>[];
  for (var i = 0; i < captured.length; i += 6) {
    calls.add((
      id: captured[i] as int,
      at: captured[i + 4] as tz.TZDateTime,
      exact: captured[i + 5] as bool,
    ));
  }
  return calls;
}

const projects = [
  ReminderProject(1, 'Face'),
  ReminderProject(2, 'Cat'),
  ReminderProject(3, 'Pregnancy'),
];

void main() {
  setUpAll(() {
    registerFallbackValue(tz.TZDateTime.utc(2000));
  });

  group('reconcile', () {
    test('schedules every project when reminders are enabled', () async {
      final backend = healthyBackend();
      final store = FakeStore(
        projects: projects,
        times: {2: const ReminderTime(8, 30)},
      );
      await schedulerWith(backend, store).reconcile();

      final calls = captureSchedules(backend);
      expect(calls.map((c) => c.id), [1, 2, 3]);
      expect(calls.every((c) => c.exact), isTrue);
      expect(
        calls.every((c) => c.at.location.name == 'America/Halifax'),
        isTrue,
      );
      expect(calls[0].at.hour, 17);
      expect(calls[1].at.hour, 8);
      expect(calls[1].at.minute, 30);
      verifyNever(backend.cancelAll);
    });

    test('cancels everything when reminders are disabled', () async {
      final backend = healthyBackend();
      final store = FakeStore(enabled: false, projects: projects);
      await schedulerWith(backend, store).reconcile();

      verify(backend.cancelAll).called(1);
      verifyNeverScheduled(backend);
    });

    test('cancels a pending reminder whose project is gone', () async {
      final backend = healthyBackend();
      when(backend.pendingIds).thenAnswer((_) async => [1, 2, 99]);
      final store = FakeStore(projects: projects.take(2).toList());
      await schedulerWith(backend, store).reconcile();

      verify(() => backend.cancel(99)).called(1);
      verifyNever(() => backend.cancel(1));
      verifyNever(() => backend.cancel(2));
    });

    test('carries on past a project the platform refuses', () async {
      final backend = healthyBackend();
      when(
        () => backend.schedule(
          id: 2,
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          at: any(named: 'at'),
          exact: any(named: 'exact'),
        ),
      ).thenThrow(PlatformException(code: 'boom'));
      final store = FakeStore(projects: projects);

      await expectLater(schedulerWith(backend, store).reconcile(), completes);
      expect(captureSchedules(backend).map((c) => c.id), [1, 2, 3]);
    });

    test('survives a store failure', () async {
      final backend = healthyBackend();
      final store = _ThrowingStore();
      await expectLater(schedulerWith(backend, store).reconcile(), completes);
    });

    test('carries on past a project whose settings cannot be read', () async {
      final backend = healthyBackend();
      final store = _TimeThrowsForStore(2, projects: projects);
      await schedulerWith(backend, store).reconcile();
      expect(captureSchedules(backend).map((c) => c.id), [1, 3]);
    });

    test('does nothing when inactive', () async {
      final backend = healthyBackend();
      final store = FakeStore(projects: projects);
      await schedulerWith(backend, store, active: false).reconcile();
      verifyZeroInteractions(backend);
    });
  });

  group('scheduleProject', () {
    test('schedules the project at its time', () async {
      final backend = healthyBackend();
      final store = FakeStore(
        projects: projects,
        times: {3: const ReminderTime(21, 15)},
      );
      await schedulerWith(backend, store).scheduleProject(3);

      final calls = captureSchedules(backend);
      expect(calls.single.id, 3);
      expect(calls.single.at.hour, 21);
      expect(calls.single.at.minute, 15);
    });

    test('cancels instead when reminders are disabled', () async {
      final backend = healthyBackend();
      final store = FakeStore(enabled: false, projects: projects);
      await schedulerWith(backend, store).scheduleProject(1);

      verify(() => backend.cancel(1)).called(1);
      verifyNeverScheduled(backend);
    });

    test('ignores an unknown project', () async {
      final backend = healthyBackend();
      final store = FakeStore(projects: projects);
      await schedulerWith(backend, store).scheduleProject(42);
      verifyNeverScheduled(backend);
    });

    test('uses an inexact alarm when exact alarms are unavailable', () async {
      final backend = healthyBackend();
      when(backend.canScheduleExact).thenAnswer((_) async => false);
      final store = FakeStore(projects: projects);
      await schedulerWith(backend, store).scheduleProject(1);

      expect(captureSchedules(backend).single.exact, isFalse);
    });

    test('retries inexact once when the platform refuses exact', () async {
      final backend = healthyBackend();
      var attempts = 0;
      when(
        () => backend.schedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          at: any(named: 'at'),
          exact: any(named: 'exact'),
        ),
      ).thenAnswer((invocation) async {
        attempts++;
        if (invocation.namedArguments[#exact] == true) {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
      });
      final store = FakeStore(projects: projects);
      await schedulerWith(backend, store).scheduleProject(1);

      expect(attempts, 2);
      expect(captureSchedules(backend).map((c) => c.exact), [true, false]);
    });

    test('throws ReminderException when the platform refuses', () async {
      final backend = healthyBackend();
      when(
        () => backend.schedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          at: any(named: 'at'),
          exact: any(named: 'exact'),
        ),
      ).thenThrow(PlatformException(code: 'error', message: 'no alarms'));
      final store = FakeStore(projects: projects);

      await expectLater(
        schedulerWith(backend, store).scheduleProject(1),
        throwsA(
          isA<ReminderException>()
              .having((e) => e.code, 'code', 'error')
              .having((e) => e.message, 'message', contains('no alarms')),
        ),
      );
    });

    test('wraps a settings read failure in ReminderException', () async {
      final backend = healthyBackend();
      final store = _TimeThrowsForStore(1, projects: projects);
      await expectLater(
        schedulerWith(backend, store).scheduleProject(1),
        throwsA(isA<ReminderException>()),
      );
      verifyNeverScheduled(backend);
    });

    test('keeps working after a failure', () async {
      final backend = healthyBackend();
      final store = FakeStore(projects: projects);
      final scheduler = schedulerWith(backend, store);
      when(
        () => backend.schedule(
          id: 1,
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          at: any(named: 'at'),
          exact: any(named: 'exact'),
        ),
      ).thenThrow(PlatformException(code: 'error'));

      await expectLater(scheduler.scheduleProject(1), throwsA(anything));
      await scheduler.scheduleProject(2);
      expect(captureSchedules(backend).map((c) => c.id), [1, 2]);
    });
  });

  group('zone resolution', () {
    test('uses the bundled database when it knows the zone', () async {
      final backend = healthyBackend(zoneId: 'Asia/Calcutta');
      final store = FakeStore(projects: projects.take(1).toList());
      await schedulerWith(backend, store).scheduleProject(1);

      final at = captureSchedules(backend).single.at;
      expect(at.location.name, 'Asia/Calcutta');
      expect(at.timeZoneOffset, const Duration(hours: 5, minutes: 30));
      expect(at.hour, 17);
    });

    test(
      'schedules with a fixed-offset location for an unknown zone',
      () async {
        final backend = healthyBackend(zoneId: 'Mars/Olympus_Mons');
        final store = FakeStore(
          projects: projects.take(1).toList(),
          times: {1: const ReminderTime(6, 0)},
        );
        await schedulerWith(backend, store).scheduleProject(1);

        final at = captureSchedules(backend).single.at;
        expect(at.location.name, 'Mars/Olympus_Mons');
        expect(at.timeZoneOffset, DateTime.now().timeZoneOffset);
        expect(at.hour, 6);
        expect(at.minute, 0);
      },
    );

    test('falls back to a GMT offset id when the device gives none', () async {
      final backend = healthyBackend(zoneId: '');
      final store = FakeStore(projects: projects.take(1).toList());
      await schedulerWith(backend, store).scheduleProject(1);

      final at = captureSchedules(backend).single.at;
      expect(at.location.name, startsWith('GMT'));
      expect(at.hour, 17);
    });

    test('falls back when the zone lookup throws', () async {
      final backend = healthyBackend();
      when(backend.localZoneId).thenThrow(StateError('no channel'));
      final store = FakeStore(projects: projects.take(1).toList());
      await schedulerWith(backend, store).scheduleProject(1);

      expect(captureSchedules(backend).single.at.hour, 17);
    });
  });

  group('ensurePermissions', () {
    test('reports without prompting when request is false', () async {
      final backend = healthyBackend();
      when(backend.notificationsAllowed).thenAnswer((_) async => false);
      when(backend.canScheduleExact).thenAnswer((_) async => false);
      final state = await schedulerWith(
        backend,
        FakeStore(),
      ).ensurePermissions(request: false);

      expect(state.notificationsAllowed, isFalse);
      expect(state.exactAlarms, isFalse);
      verifyNever(backend.requestNotificationsPermission);
      verifyNever(backend.requestExactAlarmsPermission);
    });

    test('asks only for what is missing when request is true', () async {
      final backend = healthyBackend();
      when(backend.notificationsAllowed).thenAnswer((_) async => false);
      final state = await schedulerWith(
        backend,
        FakeStore(),
      ).ensurePermissions(request: true);

      expect(state.notificationsAllowed, isTrue);
      expect(state.exactAlarms, isTrue);
      verify(backend.requestNotificationsPermission).called(1);
      verifyNever(backend.requestExactAlarmsPermission);
    });

    test('is granted when inactive', () async {
      final backend = healthyBackend();
      final state = await schedulerWith(
        backend,
        FakeStore(),
        active: false,
      ).ensurePermissions(request: true);
      expect(state.notificationsAllowed, isTrue);
      verifyZeroInteractions(backend);
    });
  });

  group('status', () {
    test('reports permissions and pending ids after queued work', () async {
      final backend = healthyBackend();
      when(backend.pendingIds).thenAnswer((_) async => [1, 3]);
      final status = await schedulerWith(
        backend,
        FakeStore(projects: projects),
      ).status();

      expect(status.permission.notificationsAllowed, isTrue);
      expect(status.pendingProjectIds, [1, 3]);
    });
  });

  group('serialization', () {
    test('runs operations in order, one at a time', () async {
      final backend = healthyBackend();
      final gate = Completer<void>();
      final order = <String>[];
      when(backend.cancelAll).thenAnswer((_) async {
        order.add('cancelAll:start');
        await gate.future;
        order.add('cancelAll:end');
      });
      when(
        () => backend.schedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          at: any(named: 'at'),
          exact: any(named: 'exact'),
        ),
      ).thenAnswer((_) async => order.add('schedule'));
      final scheduler = schedulerWith(
        backend,
        FakeStore(projects: projects.take(1).toList()),
      );

      final first = scheduler.cancelAll();
      final second = scheduler.reconcile();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['cancelAll:start']);

      gate.complete();
      await Future.wait([first, second]);
      expect(order, ['cancelAll:start', 'cancelAll:end', 'schedule']);
    });

    test('a failed operation does not block the next one', () async {
      final backend = healthyBackend();
      when(backend.cancelAll).thenThrow(StateError('nope'));
      final scheduler = schedulerWith(
        backend,
        FakeStore(projects: projects.take(1).toList()),
      );

      await scheduler.cancelAll();
      await scheduler.scheduleProject(1);
      expect(captureSchedules(backend).single.id, 1);
    });
  });

  group('nextOccurrence', () {
    late tz.Location newYork;

    setUpAll(() {
      newYork = tz.getLocation('America/New_York');
    });

    test('is today when the time has not passed', () {
      final now = tz.TZDateTime(newYork, 2026, 10, 7, 9, 0);
      final at = ReminderScheduler.nextOccurrence(
        const ReminderTime(17, 0),
        newYork,
        now,
      );
      expect(at, tz.TZDateTime(newYork, 2026, 10, 7, 17, 0));
    });

    test('is tomorrow when the time has passed', () {
      final now = tz.TZDateTime(newYork, 2026, 10, 7, 17, 0, 1);
      final at = ReminderScheduler.nextOccurrence(
        const ReminderTime(17, 0),
        newYork,
        now,
      );
      expect(at, tz.TZDateTime(newYork, 2026, 10, 8, 17, 0));
    });

    test('rolls over the month and the year', () {
      final now = tz.TZDateTime(newYork, 2026, 12, 31, 23, 0);
      final at = ReminderScheduler.nextOccurrence(
        const ReminderTime(8, 0),
        newYork,
        now,
      );
      expect(at, tz.TZDateTime(newYork, 2027, 1, 1, 8, 0));
    });

    test('keeps the wall-clock time across a DST change', () {
      // New York springs forward on 2026-03-08 at 02:00.
      final now = tz.TZDateTime(newYork, 2026, 3, 7, 20, 0);
      final at = ReminderScheduler.nextOccurrence(
        const ReminderTime(17, 0),
        newYork,
        now,
      );
      expect(at.day, 8);
      expect(at.hour, 17);
      expect(at.timeZoneOffset, const Duration(hours: -4));
      expect(now.timeZoneOffset, const Duration(hours: -5));
    });
  });

  group('offsetZoneId', () {
    test('formats offsets the platforms accept', () {
      expect(ReminderScheduler.offsetZoneId(Duration.zero), 'GMT');
      expect(
        ReminderScheduler.offsetZoneId(const Duration(hours: 5, minutes: 30)),
        'GMT+05:30',
      );
      expect(
        ReminderScheduler.offsetZoneId(const Duration(hours: -3, minutes: -30)),
        'GMT-03:30',
      );
      expect(
        ReminderScheduler.offsetZoneId(const Duration(hours: 13)),
        'GMT+13:00',
      );
    });
  });
}

/// A store whose time lookup fails for one project only.
class _TimeThrowsForStore extends FakeStore {
  _TimeThrowsForStore(this.failingProjectId, {required super.projects});

  final int failingProjectId;

  @override
  Future<ReminderTime> timeFor(int projectId) async {
    if (projectId == failingProjectId) throw StateError('db closed');
    return super.timeFor(projectId);
  }
}

class _ThrowingStore implements ReminderStore {
  @override
  Future<bool> notificationsEnabled() async => throw StateError('db closed');

  @override
  Future<List<ReminderProject>> projects() async => throw StateError('db');

  @override
  Future<ReminderTime> timeFor(int projectId) async => throw StateError('db');
}
