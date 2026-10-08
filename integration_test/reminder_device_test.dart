import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:agelapse/models/reminder_time.dart';
import 'package:agelapse/services/reminder_scheduler.dart';

/// The reminder scheduler against the device's real notification system:
/// the parts of the device checklist in
/// docs/notification-reminders-fix-plan.md (2.6) that need no person.
/// Permission prompts, force-quit, reboot and a real time zone change stay
/// manual. Skips itself where notifications are not allowed, such as an iOS
/// simulator nobody tapped Allow on.
///
/// Run with: `flutter test integration_test/reminder_device_test.dart -d <device>`
/// On a fresh install, add `--dart-define=REMINDER_TEST_ASK=true` and tap
/// Allow when the permission prompt appears.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Only a run with someone at the device asks; CI never shows a prompt
  // that nobody would answer.
  const ask = bool.fromEnvironment('REMINDER_TEST_ASK');
  final backend = platformReminderBackend();
  var allowed = false;

  setUpAll(() async {
    await backend.initialize();
    allowed = await backend.notificationsAllowed();
    if (!allowed && ask) {
      allowed = await backend.requestNotificationsPermission();
    }
  });

  setUp(() async {
    if (allowed) await backend.cancelAll();
  });

  tearDownAll(() async {
    if (allowed) await backend.cancelAll();
  });

  ReminderScheduler schedulerFor(
    _Store store, {
    DateTime Function()? clock,
    ReminderBackend? via,
  }) => ReminderScheduler.forTesting(
    backend: via ?? backend,
    store: store,
    active: true,
    clock: clock,
  );

  /// The pending ids once they equal [expected], or whatever they are after
  /// three seconds: the platform can finish an add or a removal a moment
  /// after its call returns.
  Future<Set<int>> pendingSoon(Set<int> expected) async {
    var ids = (await backend.pendingIds()).toSet();
    for (var i = 0; i < 30 && !setEquals(ids, expected); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ids = (await backend.pendingIds()).toSet();
    }
    return ids;
  }

  DateTime todayAt(int hour) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour);
  }

  final oneOffs = {
    for (var day = 1; day <= ReminderScheduler.maxSkipWindowDays; day++)
      ReminderScheduler.oneOffId(1, day),
  };

  bool skipUnlessAllowed() {
    if (allowed) return false;
    markTestSkipped('Notifications are not allowed on this device.');
    return true;
  }

  group('Reminders on the device', () {
    testWidgets('turning reminders off and on covers every project', (
      tester,
    ) async {
      if (skipUnlessAllowed()) return;
      final store = _Store([
        const ReminderProject(1, 'One'),
        const ReminderProject(2, 'Two'),
      ]);
      final scheduler = schedulerFor(store);

      await scheduler.reconcile();
      expect(await pendingSoon({1, 2}), {1, 2});

      store.enabled = false;
      await scheduler.reconcile();
      expect(await pendingSoon({}), isEmpty);

      store.enabled = true;
      await scheduler.reconcile();
      expect(await pendingSoon({1, 2}), {1, 2});
    });

    testWidgets('a photo before reminder time skips today until it goes', (
      tester,
    ) async {
      if (skipUnlessAllowed()) return;
      final store = _Store([const ReminderProject(1, 'One')]);
      final scheduler = schedulerFor(store, clock: () => todayAt(10))..start();

      await scheduler.reconcile();
      expect(await pendingSoon({1}), {1});

      store.photoTodayIds.add(1);
      store.changes.add(1);
      final skipping = await scheduler.status();
      expect(await pendingSoon(oneOffs), oneOffs);
      expect(skipping.todaySkippedProjectIds, [1]);

      store.photoTodayIds.clear();
      store.changes.add(1);
      final back = await scheduler.status();
      expect(await pendingSoon({1}), {1});
      expect(back.todaySkippedProjectIds, isEmpty);
    });

    testWidgets('a photo after reminder time keeps the daily repeat', (
      tester,
    ) async {
      if (skipUnlessAllowed()) return;
      final store = _Store([const ReminderProject(1, 'One')], photoToday: {1});
      await schedulerFor(store, clock: () => todayAt(18)).reconcile();
      expect(await pendingSoon({1}), {1});
    });

    for (final zone in ['America/Vancouver', 'Asia/Calcutta']) {
      testWidgets('schedules when the device reports $zone', (tester) async {
        if (skipUnlessAllowed()) return;
        final store = _Store([const ReminderProject(1, 'One')]);
        await schedulerFor(store, via: _ZoneBackend(backend, zone)).reconcile();
        expect(await pendingSoon({1}), {1});
      });
    }

    testWidgets('delivers a reminder at its time', (tester) async {
      if (skipUnlessAllowed()) return;
      final now = DateTime.now();
      var due = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + 1,
      );
      if (due.difference(now) < const Duration(seconds: 30)) {
        due = due.add(const Duration(minutes: 1));
      }
      final store = _Store([const ReminderProject(1, 'One')])
        ..times[1] = ReminderTime(due.hour, due.minute);
      await schedulerFor(store).reconcile();

      await Future<void>.delayed(
        due.difference(DateTime.now()) + const Duration(seconds: 20),
      );
      final delivered = await FlutterLocalNotificationsPlugin()
          .getActiveNotifications();
      expect(delivered.map((n) => n.id), contains(1));
    });
  });
}

class _Store implements ReminderStore {
  _Store(this.projectList, {Set<int>? photoToday})
    : photoTodayIds = photoToday ?? {};

  final List<ReminderProject> projectList;
  final Set<int> photoTodayIds;
  final Map<int, ReminderTime> times = {};
  final StreamController<int> changes = StreamController<int>.broadcast();
  bool enabled = true;

  @override
  Future<bool> notificationsEnabled() async => enabled;

  @override
  Future<List<ReminderProject>> projects() async => projectList;

  @override
  Future<ReminderTime> timeFor(int projectId) async =>
      times[projectId] ?? ReminderTime.defaultTime;

  @override
  Future<bool> photoTakenToday(int projectId, DateTime now) async =>
      photoTodayIds.contains(projectId);

  @override
  Stream<int> get photoChanges => changes.stream;
}

/// The real backend reporting another zone, standing in for a device whose
/// time zone changed.
class _ZoneBackend implements ReminderBackend {
  _ZoneBackend(this._inner, this._zone);

  final ReminderBackend _inner;
  final String _zone;

  @override
  Future<String?> localZoneId() async => _zone;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<bool> notificationsAllowed() => _inner.notificationsAllowed();

  @override
  Future<bool> requestNotificationsPermission() =>
      _inner.requestNotificationsPermission();

  @override
  Future<bool> canScheduleExact() => _inner.canScheduleExact();

  @override
  Future<bool> requestExactAlarmsPermission() =>
      _inner.requestExactAlarmsPermission();

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime at,
    required bool exact,
    required bool repeatDaily,
  }) => _inner.schedule(
    id: id,
    title: title,
    body: body,
    payload: payload,
    at: at,
    exact: exact,
    repeatDaily: repeatDaily,
  );

  @override
  Future<void> cancel(int id) => _inner.cancel(id);

  @override
  Future<void> cancelAll() => _inner.cancelAll();

  @override
  Future<List<int>> pendingIds() => _inner.pendingIds();
}
