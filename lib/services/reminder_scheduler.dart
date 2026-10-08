import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_time.dart';
import '../utils/platform_utils.dart';
import '../utils/project_utils.dart';
import '../utils/test_mode.dart' as test_config;
import 'database_helper.dart';
import 'log_service.dart';

/// Thrown to callers that show UI (the settings sheet) when the platform
/// refused to schedule a reminder. Internal callers log and carry on.
class ReminderException implements Exception {
  ReminderException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// What the OS currently lets the app do.
class ReminderPermissionState {
  const ReminderPermissionState({
    required this.notificationsAllowed,
    required this.exactAlarms,
  });

  /// Notifications can be shown at all.
  final bool notificationsAllowed;

  /// Android: exact alarms are permitted. Always true elsewhere. When false,
  /// reminders are scheduled inexactly and may arrive a few minutes late.
  final bool exactAlarms;

  static const ReminderPermissionState granted = ReminderPermissionState(
    notificationsAllowed: true,
    exactAlarms: true,
  );
}

/// A snapshot for the Notifications settings section.
class ReminderStatus {
  const ReminderStatus({
    required this.permission,
    required this.pendingProjectIds,
    this.todaySkippedProjectIds = const [],
  });

  final ReminderPermissionState permission;

  /// Project ids with a reminder registered with the OS right now.
  final List<int> pendingProjectIds;

  /// Project ids whose next reminder is tomorrow because today's photo is
  /// already in.
  final List<int> todaySkippedProjectIds;

  static const ReminderStatus inactive = ReminderStatus(
    permission: ReminderPermissionState.granted,
    pendingProjectIds: [],
  );
}

class ReminderProject {
  const ReminderProject(this.id, this.name);

  final int id;
  final String name;
}

/// What a project's reminder should be right now, from
/// [ReminderScheduler._plan].
typedef _ReminderPlan = ({
  ReminderTime time,
  tz.Location location,
  tz.TZDateTime now,
  bool skipToday,
  int days,
  String key,
});

/// The platform calls the scheduler makes, behind an interface so the
/// scheduling decisions can be unit tested without a device.
abstract class ReminderBackend {
  Future<void> initialize();
  Future<String?> localZoneId();
  Future<bool> notificationsAllowed();
  Future<bool> requestNotificationsPermission();
  Future<bool> canScheduleExact();
  Future<bool> requestExactAlarmsPermission();

  /// Schedules a notification at [at], and every day after it at the same
  /// wall-clock time when [repeatDaily] is set.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime at,
    required bool exact,
    required bool repeatDaily,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<int>> pendingIds();
}

/// The settings the scheduler reads, behind an interface for the same reason.
abstract class ReminderStore {
  Future<bool> notificationsEnabled();
  Future<List<ReminderProject>> projects();
  Future<ReminderTime> timeFor(int projectId);

  /// Whether [projectId] has an active photo taken on [now]'s local date.
  Future<bool> photoTakenToday(int projectId, DateTime now);

  /// Project ids whose photos changed, possibly once per photo.
  Stream<int> get photoChanges;
}

/// The single owner of daily reminder notifications.
///
/// A project's reminder fires at its [ReminderTime] in the device's zone. On
/// most days that is one repeating platform notification whose id is the
/// project id. Both platforms compute each next fire themselves from the
/// zone name and the wall-clock time, so nothing here has to run for a
/// reminder to repeat.
///
/// Once today's photo is in and today's reminder has not fired yet (#40),
/// the project gets one-off notifications instead, one a day for the next
/// [skipWindowDays] days starting tomorrow ([oneOffId]). A repeat cannot
/// start on a later day (iOS fires it at the next matching time), so
/// skipping a day takes one-offs. Every photo change, launch and return to
/// the foreground decides again, which brings back the repeat on a day
/// without a photo. The one-offs only run out if the app stays closed for
/// that whole window after a photo day.
///
/// What this class guarantees, and what #36 lacked:
/// - Initialization is self-owned ([start]) and never on the launch path.
/// - [reconcile] on every launch makes the OS match the database, so a
///   schedule call that failed or was lost (update, permission reset,
///   a crash between saving a setting and scheduling) heals on next open.
/// - Nothing reads `tz.local`. The location is resolved on every schedule,
///   and a zone id the bundled database does not know still schedules (see
///   [_resolveLocation]).
/// - No exact-alarm permission means an inexact alarm, not no alarm.
/// - Everything is serialized, logged under `[Reminders]`, and no method
///   throws into a caller except [scheduleProject], which throws
///   [ReminderException] so the settings sheet can show the reason.
///
/// Every method is a no-op on desktop and in test mode.
class ReminderScheduler {
  ReminderScheduler._()
    : this.forTesting(
        backend: _PluginReminderBackend(),
        store: _DbReminderStore(),
      );

  @visibleForTesting
  ReminderScheduler.forTesting({
    required this._backend,
    required this._store,
    bool? active,
    DateTime Function()? clock,
  }) : _activeOverride = active,
       _clock = clock ?? DateTime.now;

  static final ReminderScheduler instance = ReminderScheduler._();

  /// The most days of one-off reminders a project gets while today is
  /// skipped.
  static const int maxSkipWindowDays = 14;

  /// iOS keeps only the 64 soonest pending notifications per app, shared by
  /// every project.
  static const int _pendingLimit = 64;

  static const int _oneOffIdBase = 1000000;
  static const int _oneOffIdStride = 16;

  final ReminderBackend _backend;
  final ReminderStore _store;
  final bool? _activeOverride;
  final DateTime Function() _clock;

  Future<void>? _ready;
  Future<void> _queue = Future<void>.value();
  StreamSubscription<int>? _photoChanges;

  /// Projects with a photo-change run waiting in the queue.
  final Set<int> _photoRunsQueued = {};

  /// Per project, what the last schedule that went through decided, so a
  /// photo change that decides the same (most of an import) makes no
  /// platform calls.
  final Map<int, String> _applied = {};

  bool get _active => _activeOverride ?? (isMobile && !test_config.isTestMode);

  /// Kicks off initialization in the background and starts following photo
  /// changes. Idempotent, never throws. Other methods wait for
  /// initialization themselves, so calling this is optional for them; it
  /// only moves the work earlier.
  void start() {
    unawaited(_ensureReady());
    if (!_active) return;
    _photoChanges ??= _store.photoChanges.listen(_onPhotosChanged);
  }

  /// Days of one-offs per skipping project, so that every project skipping
  /// at once still fits under iOS's limit.
  @visibleForTesting
  static int skipWindowDays(int projectCount) =>
      (_pendingLimit ~/ (projectCount < 1 ? 1 : projectCount)).clamp(
        1,
        maxSkipWindowDays,
      );

  /// The id of [projectId]'s one-off reminder [day] days after the day it
  /// was scheduled (1 is tomorrow). Always above every project id, which the
  /// daily repeat has used as its id since the first release.
  @visibleForTesting
  static int oneOffId(int projectId, int day) =>
      _oneOffIdBase + projectId * _oneOffIdStride + day;

  /// The project a pending notification id belongs to.
  @visibleForTesting
  static int ownerOf(int id) =>
      _isOneOff(id) ? (id - _oneOffIdBase) ~/ _oneOffIdStride : id;

  static bool _isOneOff(int id) => id >= _oneOffIdBase;

  /// Today's photo decides whether today's reminder fires, so a photo change
  /// reschedules its project at once, through the same queue as everything
  /// else: [status], and so the settings sheet, always see it. A change
  /// that arrives while the project's run is still waiting rides along with
  /// it, since the run reads the photos when it starts.
  void _onPhotosChanged(int projectId) {
    if (!_photoRunsQueued.add(projectId)) return;
    unawaited(
      _serialized(() {
        _photoRunsQueued.remove(projectId);
        return _rescheduleAfterPhotoChange(projectId);
      }),
    );
  }

  Future<void> _rescheduleAfterPhotoChange(int projectId) async {
    try {
      await _ensureReady();
      if (!await _store.notificationsEnabled()) return;
      final projects = await _store.projects();
      final project = projects.where((p) => p.id == projectId).firstOrNull;
      if (project == null) return;
      final plan = await _plan(project, projects.length);
      if (_applied[projectId] == plan.key) return;
      await _apply(project, plan, await _pendingOrNull());
    } catch (e) {
      _log('photo change: project $projectId not rescheduled: $e');
    }
  }

  Future<void> _ensureReady() => _ready ??= _init();

  Future<void> _init() async {
    if (!_active) return;
    try {
      final sw = Stopwatch()..start();
      tzdata.initializeTimeZones();
      _log('timezone database ready in ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      _log('timezone database failed to load: $e');
    }
    try {
      await _backend.initialize();
      _log('plugin initialized');
    } catch (e) {
      _log('plugin initialization failed: $e');
    }
  }

  /// Runs [op] after every previously queued operation, so a toggle during a
  /// startup reconcile cannot interleave with it. Errors propagate to the
  /// caller of [op] only; they never poison the queue.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Makes the OS match the database: reminders for every project when
  /// notifications are enabled, none otherwise, and no reminder for a project
  /// that no longer exists. Never throws.
  Future<void> reconcile() async {
    if (!_active) return;
    await _ensureReady();
    return _serialized(() async {
      try {
        final enabled = await _store.notificationsEnabled();
        final projects = await _store.projects();
        if (!enabled) {
          _applied.clear();
          await _backend.cancelAll();
          _log(
            'reconcile: reminders are off, cancelled all '
            '(projects=${projects.length})',
          );
          return;
        }

        final before = await _pendingOrNull();
        var scheduled = 0;
        for (final project in projects) {
          try {
            await _scheduleNow(
              project,
              projectCount: projects.length,
              pending: before,
            );
            scheduled++;
          } catch (e) {
            _log('reconcile: project ${project.id} failed: $e');
          }
        }

        final ids = projects.map((p) => p.id).toSet();
        var pending = <int>[];
        try {
          pending = await _backend.pendingIds();
          for (final id in pending.where((id) => !ids.contains(ownerOf(id)))) {
            await _backend.cancel(id);
            _log('reconcile: cancelled reminder $id, no such project');
          }
        } catch (e) {
          _log('reconcile: pending lookup failed: $e');
        }
        _log(
          'reconcile: projects=${projects.length} scheduled=$scheduled '
          'pending=$pending',
        );
      } catch (e, st) {
        _log('reconcile failed: $e\n$st');
      }
    });
  }

  /// Schedules [projectId]'s reminder, or cancels it when notifications are
  /// off. Throws [ReminderException], and nothing else, when it could not.
  Future<void> scheduleProject(int projectId) async {
    if (!_active) return;
    await _ensureReady();
    return _serialized(() async {
      try {
        final projects = await _store.projects();
        final project = projects.where((p) => p.id == projectId).firstOrNull;
        if (project == null) {
          _log('schedule: project $projectId not found');
          return;
        }
        await _scheduleNow(
          project,
          projectCount: projects.length,
          pending: await _pendingOrNull(),
        );
      } on ReminderException {
        rethrow;
      } catch (e) {
        throw ReminderException('Could not schedule the reminder: $e');
      }
    });
  }

  Future<void> cancelProject(int projectId) async {
    if (!_active) return;
    await _ensureReady();
    return _serialized(
      () async => _cancelQuietly(projectId, pending: await _pendingOrNull()),
    );
  }

  Future<void> cancelAll() async {
    if (!_active) return;
    await _ensureReady();
    return _serialized(() async {
      _applied.clear();
      try {
        await _backend.cancelAll();
        _log('cancelled all reminders');
      } catch (e) {
        _log('cancel all failed: $e');
      }
    });
  }

  /// Checks, and with [request] asks for, what the OS lets the app do. Only
  /// user-driven paths pass `request: true`; startup never prompts.
  Future<ReminderPermissionState> ensurePermissions({
    required bool request,
  }) async {
    if (!_active) return ReminderPermissionState.granted;
    await _ensureReady();

    var allowed = false;
    try {
      allowed = await _backend.notificationsAllowed();
      if (!allowed && request) {
        allowed = await _backend.requestNotificationsPermission();
      }
    } catch (e) {
      _log('notification permission check failed: $e');
    }

    var exact = true;
    try {
      exact = await _backend.canScheduleExact();
      if (!exact && request) {
        exact = await _backend.requestExactAlarmsPermission();
      }
    } catch (e) {
      _log('exact alarm check failed: $e');
    }

    _log('permissions: notifications=$allowed exact=$exact requested=$request');
    return ReminderPermissionState(
      notificationsAllowed: allowed,
      exactAlarms: exact,
    );
  }

  /// For the settings UI. Waits for queued operations so the answer reflects
  /// a reconcile that is still running. Never throws.
  Future<ReminderStatus> status() async {
    if (!_active) return ReminderStatus.inactive;
    await _ensureReady();
    final permission = await ensurePermissions(request: false);
    var pending = <int>[];
    try {
      pending = await _serialized(_backend.pendingIds);
    } catch (e) {
      _log('pending lookup failed: $e');
    }
    final owners = <int>{};
    final repeating = <int>{};
    for (final id in pending) {
      owners.add(ownerOf(id));
      if (!_isOneOff(id)) repeating.add(id);
    }
    return ReminderStatus(
      permission: permission,
      pendingProjectIds: owners.toList(),
      todaySkippedProjectIds: [
        for (final id in owners)
          if (!repeating.contains(id)) id,
      ],
    );
  }

  /// Schedules [project]'s reminder as [_plan] decides, or cancels it when
  /// notifications are off. [pending] is the OS's pending ids, or null when
  /// unknown.
  Future<void> _scheduleNow(
    ReminderProject project, {
    required int projectCount,
    required Set<int>? pending,
  }) async {
    if (!await _store.notificationsEnabled()) {
      await _cancelQuietly(project.id, pending: pending);
      _log('schedule: reminders are off, cancelled project ${project.id}');
      return;
    }
    await _apply(project, await _plan(project, projectCount), pending);
  }

  /// Whether [project] skips today: today's photo is in and today's
  /// reminder has not fired yet. [_ReminderPlan.key] sums up everything the
  /// decision depends on, so an unchanged one can be recognized.
  Future<_ReminderPlan> _plan(ReminderProject project, int projectCount) async {
    final time = await _store.timeFor(project.id);
    final location = await _resolveLocation();
    final clockNow = _clock();
    final now = tz.TZDateTime.from(clockNow, location);
    final todayAt = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    final skipToday =
        !todayAt.isBefore(now) && await _photoTakenToday(project.id, clockNow);
    final days = skipToday ? skipWindowDays(projectCount) : 0;
    return (
      time: time,
      location: location,
      now: now,
      skipToday: skipToday,
      days: days,
      key:
          '${now.year}-${now.month}-${now.day} ${time.encode()} '
          '${location.name} skip=$skipToday days=$days',
    );
  }

  /// Schedules the daily repeat, or the one-offs from tomorrow when [plan]
  /// skips today, and cancels whichever of the two is no longer needed.
  Future<void> _apply(
    ReminderProject project,
    _ReminderPlan plan,
    Set<int>? pending,
  ) async {
    // Forgotten until this run succeeds, so a failure is redone next time.
    _applied.remove(project.id);
    final (:time, :location, :now, :skipToday, :days, :key) = plan;

    var exact = true;
    try {
      exact = await _backend.canScheduleExact();
    } catch (e) {
      _log('exact alarm check failed, assuming exact: $e');
    }

    if (!skipToday) {
      final at = nextOccurrence(time, location, now);
      exact = await _scheduleOne(
        project,
        project.id,
        at,
        exact: exact,
        repeatDaily: true,
      );
      _log(
        'scheduled project ${project.id} at ${at.toIso8601String()} '
        'zone=${at.location.name} mode=${exact ? 'exact' : 'inexact'}',
      );
      await _cancelOneOffs(project.id, fromDay: 1, pending: pending);
      _applied[project.id] = key;
      return;
    }

    for (var day = 1; day <= days; day++) {
      // Through the constructor, like [nextOccurrence], so every day keeps
      // the wall-clock time across a DST change.
      final at = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + day,
        time.hour,
        time.minute,
      );
      exact = await _scheduleOne(
        project,
        oneOffId(project.id, day),
        at,
        exact: exact,
        repeatDaily: false,
      );
    }
    // The repeat goes only once the one-offs are in, so a failure above
    // leaves today's reminder rather than none.
    try {
      await _backend.cancel(project.id);
    } catch (e) {
      _log('cancel failed for project ${project.id}: $e');
    }
    await _cancelOneOffs(project.id, fromDay: days + 1, pending: pending);
    _log(
      'scheduled project ${project.id} daily from tomorrow for $days days at '
      '${time.encode()}, skipping today (photo taken) zone=${location.name} '
      'mode=${exact ? 'exact' : 'inexact'}',
    );
    _applied[project.id] = key;
  }

  /// Schedules one notification, retrying inexact once when the platform
  /// refuses exact alarms. Returns whether it went in exact, so the rest of
  /// a run of one-offs does not ask again.
  Future<bool> _scheduleOne(
    ReminderProject project,
    int id,
    tz.TZDateTime at, {
    required bool exact,
    required bool repeatDaily,
  }) async {
    try {
      await _schedule(project, id, at, exact: exact, repeatDaily: repeatDaily);
      return exact;
    } on PlatformException catch (e) {
      if (exact && e.code == 'exact_alarms_not_permitted') {
        _log(
          'schedule: exact alarms not permitted for project ${project.id}, '
          'retrying inexact',
        );
        try {
          await _schedule(
            project,
            id,
            at,
            exact: false,
            repeatDaily: repeatDaily,
          );
          return false;
        } catch (e2) {
          throw ReminderException(
            'Could not schedule the reminder: $e2',
            code: e2 is PlatformException ? e2.code : null,
          );
        }
      }
      throw ReminderException(
        'Could not schedule the reminder: ${e.message ?? e.code}',
        code: e.code,
      );
    } catch (e) {
      throw ReminderException('Could not schedule the reminder: $e');
    }
  }

  Future<void> _schedule(
    ReminderProject project,
    int id,
    tz.TZDateTime at, {
    required bool exact,
    required bool repeatDaily,
  }) => _backend.schedule(
    id: id,
    title: 'AgeLapse: ${project.name}',
    body: "${project.name}: Don't forget to take your photo!",
    payload: 'project:${project.id}',
    at: at,
    exact: exact,
    repeatDaily: repeatDaily,
  );

  /// A photo check that fails counts as no photo, so the project keeps
  /// today's reminder rather than losing it.
  Future<bool> _photoTakenToday(int projectId, DateTime now) async {
    try {
      return await _store.photoTakenToday(projectId, now);
    } catch (e) {
      _log('photo check failed for project $projectId, not skipping: $e');
      return false;
    }
  }

  /// The pending notification ids, or null when the platform cannot say.
  Future<Set<int>?> _pendingOrNull() async {
    try {
      return (await _backend.pendingIds()).toSet();
    } catch (e) {
      _log('pending lookup failed: $e');
      return null;
    }
  }

  Future<void> _cancelQuietly(
    int projectId, {
    required Set<int>? pending,
  }) async {
    _applied.remove(projectId);
    try {
      await _backend.cancel(projectId);
      _log('cancelled reminder for project $projectId');
    } catch (e) {
      _log('cancel failed for project $projectId: $e');
    }
    await _cancelOneOffs(projectId, fromDay: 1, pending: pending);
  }

  /// Cancels [projectId]'s one-offs from [fromDay] on: the pending ones when
  /// [pending] is known, every possible one otherwise.
  Future<void> _cancelOneOffs(
    int projectId, {
    required int fromDay,
    required Set<int>? pending,
  }) async {
    for (var day = fromDay; day <= maxSkipWindowDays; day++) {
      final id = oneOffId(projectId, day);
      if (pending != null && !pending.contains(id)) continue;
      try {
        await _backend.cancel(id);
      } catch (e) {
        _log('cancel failed for reminder $id: $e');
      }
    }
  }

  /// The device's zone as a [tz.Location], resolved fresh each time so a
  /// timezone change while the app runs is picked up.
  ///
  /// Android computes every fire time from the wall-clock fields and the
  /// location's *name* with its own zone database. iOS takes the instant,
  /// and for the daily repeat keeps only its hour and minute in that zone.
  /// So when the bundled Dart database does not know the id, a fixed-offset
  /// location carrying the same name still schedules the repeat correctly on
  /// both, because the id came from that same platform. Only an iOS one-off
  /// days ahead, across a DST change, can land an hour off until the next
  /// reconcile.
  Future<tz.Location> _resolveLocation() async {
    String? id;
    try {
      id = (await _backend.localZoneId())?.trim();
    } catch (e) {
      _log('zone lookup failed: $e');
    }
    final offset = DateTime.now().timeZoneOffset;
    if (id == null || id.isEmpty) {
      id = offsetZoneId(offset);
      _log('zone id unavailable, using $id');
    }

    try {
      return tz.getLocation(id);
    } catch (_) {
      // LocationNotFoundException, or the database failed to load.
    }
    _log(
      'zone $id is not in the bundled database, scheduling with a fixed '
      '${offsetZoneId(offset)} location named $id',
    );
    return tz.Location(id, [tz.minTime], [0], [
      tz.TimeZone(offset, isDst: false, abbreviation: id),
    ]);
  }

  /// Today at [time] in [location], or tomorrow if that has passed. The day
  /// is advanced through the constructor so the wall-clock time survives a
  /// DST transition (adding 24 hours would not).
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    ReminderTime time,
    tz.Location location,
    tz.TZDateTime now,
  ) {
    final today = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!today.isBefore(now)) return today;
    return tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      time.hour,
      time.minute,
    );
  }

  /// A zone id both platforms accept when the device gives none:
  /// `GMT`, `GMT+05:30`, `GMT-03:30`.
  @visibleForTesting
  static String offsetZoneId(Duration offset) {
    if (offset == Duration.zero) return 'GMT';
    final sign = offset.isNegative ? '-' : '+';
    final magnitude = offset.abs();
    final hours = magnitude.inHours.toString().padLeft(2, '0');
    final minutes = magnitude.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return 'GMT$sign$hours:$minutes';
  }

  void _log(String message) => LogService.instance.log('[Reminders] $message');
}

class _DbReminderStore implements ReminderStore {
  @override
  Future<bool> notificationsEnabled() async =>
      await DB.instance.getSettingValueByTitle('enable_notifications') ==
      'true';

  @override
  Future<List<ReminderProject>> projects() async {
    final rows = await DB.instance.getAllProjects();
    return [
      for (final row in rows)
        ReminderProject(
          row['id'] as int,
          (row['name'] as String?) ?? 'Project',
        ),
    ];
  }

  @override
  Future<ReminderTime> timeFor(int projectId) async => ReminderTime.parse(
    await DB.instance.getSettingValueByTitle(
      'daily_notification_time',
      projectId.toString(),
    ),
  );

  @override
  Future<bool> photoTakenToday(int projectId, DateTime now) =>
      ProjectUtils.photoWasTakenToday(projectId, now: now);

  @override
  Stream<int> get photoChanges => DB.instance.photosChanged;
}

/// The app's real notification backend, for device tests that run the
/// scheduler against the OS (integration_test/reminder_device_test.dart).
@visibleForTesting
ReminderBackend platformReminderBackend() => _PluginReminderBackend();

class _PluginReminderBackend implements ReminderBackend {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // The id predates 2.8.0 and must not change: Android keeps user choices
  // (sound, importance) per channel id. The name is what users see in
  // system settings.
  static const String _channelId = 'daily_notification_channel_id';
  static const String _channelName = 'Daily reminders';
  static const String _channelDescription =
      'Reminders to take your daily photo';

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    if (Platform.isAndroid) {
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked for when the user creates a project or turns
        // reminders on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        // The payload is 'project:<id>'. Nothing routes on it yet.
      },
    );
  }

  @override
  Future<String?> localZoneId() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  @override
  Future<bool> notificationsAllowed() async {
    if (Platform.isAndroid) {
      return await _android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      return (await _ios?.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool> requestNotificationsPermission() async {
    if (Platform.isAndroid) {
      return await _android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<bool> requestExactAlarmsPermission() async {
    if (!Platform.isAndroid) return true;
    return await _android?.requestExactAlarmsPermission() ?? false;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime at,
    required bool exact,
    required bool repeatDaily,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: at,
    payload: payload,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<List<int>> pendingIds() async {
    final requests = await _plugin.pendingNotificationRequests();
    return [for (final request in requests) request.id];
  }
}
