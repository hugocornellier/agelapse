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
  });

  final ReminderPermissionState permission;

  /// Project ids with a reminder registered with the OS right now.
  final List<int> pendingProjectIds;

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

/// The platform calls the scheduler makes, behind an interface so the
/// scheduling decisions can be unit tested without a device.
abstract class ReminderBackend {
  Future<void> initialize();
  Future<String?> localZoneId();
  Future<bool> notificationsAllowed();
  Future<bool> requestNotificationsPermission();
  Future<bool> canScheduleExact();
  Future<bool> requestExactAlarmsPermission();
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime at,
    required bool exact,
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
}

/// The single owner of daily reminder notifications.
///
/// Every reminder is a repeating platform notification (one per project, the
/// project id is the notification id) that fires at the project's
/// [ReminderTime] in the device's zone. Both platforms compute each next
/// fire themselves from the zone name and the wall-clock time, so nothing
/// here has to run for a reminder to repeat.
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
  }) : _activeOverride = active;

  static final ReminderScheduler instance = ReminderScheduler._();

  final ReminderBackend _backend;
  final ReminderStore _store;
  final bool? _activeOverride;

  Future<void>? _ready;
  Future<void> _queue = Future<void>.value();

  bool get _active => _activeOverride ?? (isMobile && !test_config.isTestMode);

  /// Kicks off initialization in the background. Idempotent, never throws.
  /// Other methods wait for it themselves, so calling this is optional; it
  /// only moves the work earlier.
  void start() {
    unawaited(_ensureReady());
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
          await _backend.cancelAll();
          _log(
            'reconcile: reminders are off, cancelled all '
            '(projects=${projects.length})',
          );
          return;
        }

        var scheduled = 0;
        for (final project in projects) {
          try {
            await _scheduleNow(project);
            scheduled++;
          } catch (e) {
            _log('reconcile: project ${project.id} failed: $e');
          }
        }

        final ids = projects.map((p) => p.id).toSet();
        var pending = <int>[];
        try {
          pending = await _backend.pendingIds();
          for (final id in pending.where((id) => !ids.contains(id))) {
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
        await _scheduleNow(project);
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
    return _serialized(() => _cancelQuietly(projectId));
  }

  Future<void> cancelAll() async {
    if (!_active) return;
    await _ensureReady();
    return _serialized(() async {
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
    return ReminderStatus(permission: permission, pendingProjectIds: pending);
  }

  Future<void> _scheduleNow(ReminderProject project) async {
    if (!await _store.notificationsEnabled()) {
      await _cancelQuietly(project.id);
      _log('schedule: reminders are off, cancelled project ${project.id}');
      return;
    }

    final time = await _store.timeFor(project.id);
    final location = await _resolveLocation();
    final at = nextOccurrence(time, location, tz.TZDateTime.now(location));

    var exact = true;
    try {
      exact = await _backend.canScheduleExact();
    } catch (e) {
      _log('exact alarm check failed, assuming exact: $e');
    }

    try {
      await _schedule(project, at, exact: exact);
    } on PlatformException catch (e) {
      if (exact && e.code == 'exact_alarms_not_permitted') {
        _log(
          'schedule: exact alarms not permitted for project ${project.id}, '
          'retrying inexact',
        );
        try {
          await _schedule(project, at, exact: false);
        } catch (e2) {
          throw ReminderException(
            'Could not schedule the reminder: $e2',
            code: e2 is PlatformException ? e2.code : null,
          );
        }
      } else {
        throw ReminderException(
          'Could not schedule the reminder: ${e.message ?? e.code}',
          code: e.code,
        );
      }
    } catch (e) {
      throw ReminderException('Could not schedule the reminder: $e');
    }
  }

  Future<void> _schedule(
    ReminderProject project,
    tz.TZDateTime at, {
    required bool exact,
  }) async {
    await _backend.schedule(
      id: project.id,
      title: 'AgeLapse: ${project.name}',
      body: "${project.name}: Don't forget to take your photo!",
      payload: 'project:${project.id}',
      at: at,
      exact: exact,
    );
    _log(
      'scheduled project ${project.id} at ${at.toIso8601String()} '
      'zone=${at.location.name} mode=${exact ? 'exact' : 'inexact'}',
    );
  }

  Future<void> _cancelQuietly(int projectId) async {
    try {
      await _backend.cancel(projectId);
      _log('cancelled reminder for project $projectId');
    } catch (e) {
      _log('cancel failed for project $projectId: $e');
    }
  }

  /// The device's zone as a [tz.Location], resolved fresh each time so a
  /// timezone change while the app runs is picked up.
  ///
  /// The plugin only sends the platform the location's *name* and the
  /// wall-clock fields; the platform then computes every fire time with its
  /// own zone database. So when the bundled Dart database does not know the
  /// id (it ships without legacy aliases such as `Asia/Calcutta`, which
  /// Android still reports), a fixed-offset location carrying the same name
  /// schedules correctly, because the id came from that same platform.
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
}

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
    matchDateTimeComponents: DateTimeComponents.time,
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
