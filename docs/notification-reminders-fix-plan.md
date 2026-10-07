# Daily reminder notifications: fix plan for #36 (and the bugs around it)

Status: implemented in the #36 fix commit (2026-10-07), unit tested, device checklist in 2.6 still to run. Written 2026-10-07 against `main` at 2.8.0+48.
Packages in the lockfile: flutter_local_notifications 22.3.1, timezone 0.11.1,
flutter_timezone 5.1.1, permission_handler 12.0.3. The notification code is
byte-for-byte the same as the 2.6.0 release the reporter used (only formatting
changed), so everything below applies to 2.6.0, 2.7.0 and current `main`.

## Part 1: What is actually broken

### 1.1 The reported bug (#36)

`NotificationUtil.scheduleDailyNotification` builds the fire time with
`tz.TZDateTime(tz.local, ...)` (`lib/utils/notification_util.dart:143`).
`tz.local` is `late Location _local;` in timezone 0.11.1 (`src/env.dart:15`).
It is only assigned by `initializeDatabase()` (sets UTC) or `setLocalLocation()`.
Both run only inside `NotificationUtil.initializeNotifications()`, and that is
called from exactly one place: `CreateProjectSheet._createProject`
(`lib/widgets/create_project_sheet.dart:289`). The startup path in
`lib/main.dart:162` initializes the plugin but never touches the timezone
database.

So in any process other than the one that created the project:

- Changing the reminder time (`settings_sheet.dart:1071`) throws
  `LateInitializationError` before `zonedSchedule` is reached.
- Turning the toggle off runs `cancelAll()` (works), turning it back on throws
  (nothing rescheduled).
- The error is invisible: `_scheduleDailyNotification` (`settings_sheet.dart:1075`)
  does not await the call, there is no try/catch, and nothing is logged.

This reproduces every step of the report:

| Reporter said | What happened |
|---|---|
| Got the 5 pm reminder, changed it to 9 pm, 9 pm never came | New process, time change threw, old 5 pm schedule was replaced by nothing (the DB row changed, the alarm did not) |
| Toggled off and on, set it back to 5 pm, nothing | Off cancelled the alarm; on and the time change both threw |
| Reinstalled, still nothing | Installing the APK over the existing app keeps app data (it is an update, `MY_PACKAGE_REPLACED`). The plugin re-creates alarms from its own cache on that broadcast, but the cache was emptied by `cancelAll()`. Toggling on threw again |
| Clearing data fixed it | Fresh onboarding goes through project creation, the only path that initializes timezones |
| "If I set the time after I receive a notification, it stops" | Any time change in a later process breaks it; the notification is a coincidence |

iOS has the same Dart code path, so it is affected the same way.

### 1.2 A second, independent bug: unknown zone ids

`initializeNotifications` imports `package:timezone/data/latest.dart`, then does
`tz.getLocation(timezoneInfo.identifier)`. `latest.dart` omits the legacy
aliases that `latest_all.dart` carries. Checked against the shipped data files:

| Zone id | latest | latest_all |
|---|---|---|
| `Asia/Calcutta` | missing | present |
| `US/Eastern` | missing | present |
| `Asia/Kolkata`, `America/Halifax`, `Etc/GMT+5` | present | present |

Android reports `ZoneId.systemDefault().id` (flutter_timezone), and plenty of
devices still report legacy ids (`Asia/Calcutta` on many Indian devices is the
common case). For those users `getLocation` throws `LocationNotFoundException`
inside `_createProject`'s try/catch, so the reminder is never scheduled, on
the very first launch, with one log line and no UI.

### 1.3 Smaller bugs in the same code

1. Toggle off cancels every project's reminder (`cancelAll`), toggle on
   reschedules only the open project (`settings_sheet.dart:2040-2043`). With
   two projects, one reminder is lost until that project's time is re-saved.
2. Nothing reconciles on launch. If any schedule call ever failed, or the
   plugin cache was emptied, nothing repairs it until the user touches the
   setting again (which, today, also fails).
3. Two separate plugin initializations: `main.dart:162` and
   `NotificationUtil.initializeNotifications`. The plugin is a singleton, so the
   second `initialize()` overrides the first callback. Only the second creates
   the Android channel and the timezone state.
4. Android permission flow is all-or-nothing: if notification permission or
   the exact-alarm permission is not granted, `initializeNotifications` returns
   early (`notification_util.dart:26-35`) *before* `initialize()` and the
   timezone setup, so a later schedule attempt throws instead of scheduling an
   inexact alarm or a muted notification.
5. `getSettingValueByTitle` (`database_helper.dart:641`) special-cases
   `"not_set"`, but the default is `"not set"`. Dead branch. A project whose
   `daily_notification_time` is still `"not set"` would hit
   `int.parse("not set")` in `scheduleDailyNotification`.
6. The reminder time is stored as an epoch-millisecond instant of "today at
   HH:MM" and decoded with the device's current zone. Move to a different
   timezone and the decoded HH:MM shifts by the offset difference.
7. The scheduled zone name is baked into the alarm (`timeZoneName`). After the
   user travels, the reminder keeps firing at HH:MM in the old zone until
   something reschedules it. Today, nothing does.
8. `_scheduleDailyNotification` is fire-and-forget, so even once the throw is
   fixed, a `PlatformException` (for example `exact_alarms_not_permitted`)
   would still be silent.
9. `_selectTime` (`settings_sheet.dart:1071`) schedules a reminder whether or
   not notifications are enabled. A user with the toggle off who changes the
   time gets a daily reminder anyway (in the process that created the project;
   in any other process it throws, see 1.1).

### 1.4 What is fine and should stay

- `zonedSchedule` with `matchDateTimeComponents: time` is the right primitive
  for a daily reminder. Both platforms compute every next fire themselves
  (Android: `getNextFireDateMatchingDateTimeComponents`, iOS:
  `UNCalendarNotificationTrigger repeats:YES`) from the zone name and the
  wall-clock time. The Dart-side date arithmetic only has to carry those two.
- Android re-creates alarms after reboot and app updates from the plugin's
  SharedPreferences cache (`ScheduledNotificationBootReceiver`). iOS keeps
  pending requests across reboots and updates.
- Scheduling the same id again replaces the previous alarm/request on both
  platforms, so rescheduling is idempotent.
- Manifest: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`,
  `RECEIVE_BOOT_COMPLETED`, the two receivers. Nothing to add.
- Desktop never runs this code: `_initializeApp` is mobile-only and the
  Notifications section is `isMobile`-gated.

## Part 2: Recommendation

Replace the scattered calls with one owner, `ReminderScheduler`, that is
initialized once at startup, never throws into callers, reconciles the
platform's pending reminders against the database on every launch, and degrades
instead of giving up (unknown zone id, no exact-alarm permission, no
notification permission).

### 2.1 Design

```
lib/services/reminder_scheduler.dart      new, single owner of reminders
lib/models/reminder_time.dart             new, HH:MM value type with legacy parsing
lib/utils/notification_util.dart          removed (or a thin facade for one release)
lib/main.dart                             one init call, one reconcile call
lib/widgets/create_project_sheet.dart     ask permission, schedule the new project
lib/widgets/settings_sheet.dart           await, catch, report; toggle affects all projects
lib/utils/project_utils.dart              deleteProject cancels through the scheduler
lib/services/database_helper.dart         remove the dead "not_set" branch
```

`ReminderScheduler` (singleton, mobile-only, every public method is a no-op on
desktop and in `isTestMode`):

| Method | Does |
|---|---|
| `start()` | Called once from `main` on mobile, not awaited. Stores its own `_ready` future: `tz.initializeTimeZones()` from `latest_all`, create the Android channel (id unchanged, name "Daily reminders"), `plugin.initialize()` with the tap callback and, on iOS, no permission request. Every other method awaits `_ready` first. Catches and logs everything; never throws, never prompts. Nothing about reminders sits on the launch critical path. |
| `ensurePermissions({required bool request})` | Uses the plugin's own API, no permission_handler: Android `requestNotificationsPermission()` / `areNotificationsEnabled()`, `canScheduleExactNotifications()` and (Android 12 only, once) `requestExactAlarmsPermission()`; iOS `requestPermissions(alert, sound)` / `checkPermissions()`. Returns `ReminderPermissionState` (granted / denied / exactUnavailable). Never throws. |
| `reconcile()` | Awaits `_ready`. Reads `enable_notifications` inside the queued operation. If false: `cancelAll()`. Else: `scheduleProject(id)` for every project in `getAllProjects()`, then cancels any pending id that is not a project (leftover from a failed delete). Ends with one summary log line. All operations are serialized through an internal future chain so a toggle during startup cannot interleave. |
| `scheduleProject(int id)` | No-op (and cancels the id) when `enable_notifications` is false, which fixes 1.3 item 9. Reads the project's time (default 17:00 via `ReminderTime`), resolves the zone *now* (2.2), checks `canScheduleExactNotifications()` and picks `exactAllowWhileIdle` or `inexactAllowWhileIdle`; also catches `exact_alarms_not_permitted` and retries inexact once. Payload = project id (for a future tap handler). Logs the outcome with the next fire time. Throws a typed `ReminderException` only to callers that show UI (settings sheet); `reconcile` catches and logs. |
| `cancelProject(int id)` / `cancelAll()` | Thin wrappers, logged, never throw. |
| `status()` | For the settings UI: permission state, exact-alarm availability, pending project ids. |

All public methods are no-ops on desktop and when `test_config.isTestMode` is
set, so the call sites lose their own `isTestMode` checks.

Permission prompts only happen from user-driven paths (project creation,
toggle on). `start()` and `reconcile()` never prompt, so startup stays silent.
On iOS the first-launch prompt therefore moves from app start to project
creation, which is where the user is told about reminders anyway. Only alert
and sound are requested; the app never sets a badge.

### 2.2 Timezone resolution (the root cause, done properly)

```
start():            tz.initializeTimeZones()        // latest_all, once per process

_resolveLocation(): // called on every schedule, never cached
  id = FlutterTimezone.getLocalTimezone().identifier
       (throws or empty → id = 'GMT±HH:MM' from DateTime.now().timeZoneOffset)
  try    return tz.getLocation(id)
  catch  return Location(id, [minTime], [0],
                  [TimeZone(DateTime.now().timeZoneOffset,
                            isDst: false, abbreviation: id)])
  log "[Reminders] zone=$id known=${found in Dart db}"

scheduleProject():  TZDateTime(location, today, hour, minute)  // explicit location
```

`tz.local` is never read. The `late` global that caused #36 stops being part
of the design instead of being initialized earlier. (`initializeTimeZones()`
still sets it to UTC as a side effect, so any stray reader would get UTC, not
a throw.) Resolving the zone on every schedule means a device whose timezone
changed while the app was running still schedules in the new zone.

Why the synthetic fallback is safe: the plugin serializes a `TZDateTime` as
`{timeZoneName: location.name, scheduledDateTime: 'YYYY-MM-DDTHH:MM:SS'}`
(`tz_datetime_mapper.dart`). Android then does
`ZonedDateTime.of(LocalDateTime.parse(..), ZoneId.of(timeZoneName))` and iOS
`[NSTimeZone timeZoneWithName:]` + date components. Both use the platform's
own zone database, and the id came from that same platform, so it resolves
there even when the Dart database lacks it. The only thing the Dart `Location`
contributes is the name and the wall-clock fields. The Dart-side instant is
only used by `validateDateIsInTheFuture`, which is skipped when
`matchDateTimeComponents` is set. Verified with a scratch script against the
project's resolved packages: a synthetic `Asia/Calcutta` location and the real
`Asia/Kolkata` one produce byte-identical maps apart from the name, and the
same instant (see 3.1).

`GMT±HH:MM` is accepted by Java's `ZoneId.of` (prefixed offset id). iOS
treats an unknown name as nil and falls back to the device zone, which is the
right behaviour for a daily reminder anyway.

`latest_all` costs about 190 KB more data than `latest` and parses in about
10 ms on this machine (so tens of milliseconds on a phone, off the critical
path); irrelevant next to a 282 MB APK, and it removes the legacy-alias
failure for a large group of users.

### 2.3 Reminder time storage

`ReminderTime(hour, minute)`:

- `parse(String)`: `"HH:MM"` (new), a pure integer (legacy epoch ms, decoded
  with the current zone exactly as today), `"not set"`/anything else → 17:00.
- `encode()`: `"HH:MM"`.
- `defaultTime` = 17:00 (replaces `getFivePMLocalTime`; keep that function
  as a one-line wrapper if the existing signature tests should stay).

New writes use `"HH:MM"`. No migration: reads accept both forms forever. This
fixes 1.3 item 6 without touching existing rows. The settings sheet's
`_initializeData` and `_selectTime` use the same type.

### 2.4 Call sites

- `main.dart`: delete the local `initializeNotifications()` and its
  `Future.wait` slot. After `runApp` (mobile branch):
  `ReminderScheduler.instance.start(); unawaited(ReminderScheduler.instance.reconcile());`
  Nothing awaits either, so the first frame is unaffected even if a platform
  channel is slow. The DB is already created by then.
- `create_project_sheet.dart`: save the default time with
  `ReminderTime.defaultTime.encode()`, then
  `await ensurePermissions(request: true)`, then `await scheduleProject(id)`,
  inside the existing try/catch. Remove the direct `initializeNotifications`
  call.
- `settings_sheet.dart`:
  - Toggle on: save, `ensurePermissions(request: true)`, `reconcile()` (all
    projects). If the state is denied, keep the toggle on (the setting is the
    user's intent) but show a SnackBar "Notifications are off for AgeLapse in
    system settings" with an "Open settings" action (`openAppSettings()`).
  - Toggle off: save, `cancelAll()`.
  - Time change: save, `await scheduleProject(widget.projectId)`; on
    `ReminderException` show a SnackBar with the message.
  - All three awaited inside try/catch; nothing fire-and-forget.
  - A one-line status under the toggle from `status()`: "Next reminder: 5:00 PM"
    or "Notifications are blocked in system settings" or "Exact timing
    unavailable, reminders may arrive a few minutes late".
- `project_utils.deleteProject`: `cancelProject(projectId)` (already in the
  right place, just routed through the scheduler and wrapped in try/catch so a
  plugin error can never abort a deletion that already committed).
- `database_helper.dart`: delete the `"not_set"` branch in
  `getSettingValueByTitle` and `getNotifDefault`; defaults live in
  `ReminderTime`.

### 2.5 Logging (so the next report comes with evidence)

Every schedule/cancel logs `[Reminders] <action> project=<id> time=<HH:MM>
zone=<id> mode=<exact|inexact> next=<ISO>` or the failure. `reconcile()` ends
with `[Reminders] pending=[ids] enabled=<bool> projects=<n>`. These show up in
Info → Export Logs, which is what #42 and #15 are missing today.

### 2.6 Tests

Unit (pure, no platform channels):

- `ReminderTime.parse` for `"17:00"`, a legacy epoch-ms string, `"not set"`,
  garbage, and `encode` round trip.
- `ReminderScheduler` with an injected `ReminderBackend` interface (schedule,
  cancel, cancelAll, pending, permissions, zone id) mocked with mocktail:
  - reconcile with enabled=true and 3 projects schedules 3 ids;
  - reconcile with enabled=false cancels all and schedules none;
  - `exact_alarms_not_permitted` on the first call retries inexact once;
  - an unknown zone id produces a `Location` with the same name and the
    current offset, and the scheduled `TZDateTime.location.name` equals the id;
  - a backend throw inside reconcile is logged and does not propagate;
  - two overlapping `reconcile()`/`cancelAll()` calls run in order.
- Replace the signature-only assertions in
  `test/utils/notification_util_test.dart` with the above.

Device checks before release (Android 13+ device, ideally a Samsung, and an
iPhone):

1. Fresh install, create a project: `adb shell dumpsys alarm | grep -A3
   com.hugocornellier.agelapse` shows one `RTC_WAKEUP` alarm at today's or
   tomorrow's 17:00.
2. Force-stop, relaunch, set the time to now + 2 min: the notification arrives;
   `dumpsys alarm` shows the new trigger.
3. Toggle off → no alarm; toggle on → alarms for every project.
4. Create a second project, toggle off and on: two alarms.
5. Reboot: both alarms are back (plugin boot receiver).
6. `adb install -r` the same APK: both alarms are back after launch
   (reconcile), even after a toggle-off/on cycle emptied the plugin cache
   before the update.
7. Revoke notification permission in system settings, reopen: the status line
   says so, toggling on shows the SnackBar with the settings action.
8. Change the device timezone, relaunch: `dumpsys alarm` shows the trigger
   moved to 17:00 in the new zone.
9. iOS: steps 2, 3, 4 and 8 using a 2-minute-ahead time; confirm the first
   permission prompt now appears at project creation.

### 2.7 Release

- Ship in 2.8.0. README unreleased section, under a "Bug fixes" heading:
  "Daily reminders stopped working after the first launch (changing the time
  or re-enabling them silently failed). Reminders are now rescheduled on every
  launch, work in time zones the app did not know about, and the Notifications
  settings show why a reminder cannot be delivered."
- Reply on #36 after release: explain the cause in two sentences, note that
  reminders now survive reinstalls and timezone changes, and ask them to
  confirm on 2.8.0.

### 2.8 Out of scope, but the design leaves room

- #40 (skip the reminder when today's photo exists): `reconcile()` is the one
  place that decides what gets scheduled; swapping the repeating trigger for
  one-shot reminders over the next 14 days, cancelled by `addPhoto`, is a
  change inside the scheduler only.
- Tapping a reminder could open that project's camera tab
  (`onDidReceiveNotificationResponse` payload = project id).
- `USE_EXACT_ALARM` is fine for a sideloaded app; it would be rejected on
  Google Play for a non-alarm app. Note it if Play distribution ever comes up.

## Part 3: Critical analysis of the plan

Written after Part 2, with the plan revised in place where the analysis
changed it (3.2 lists every change). Everything in 3.1 was checked by
reading the shipped package sources or by running a scratch script against
the project's resolved packages (`.dart_tool/package_config.json`, timezone
0.11.1). Nothing in the repo or on GitHub was changed.

### 3.1 Claims that were verified

| Claim | Evidence |
|---|---|
| `tz.local` throws before init | `late Location _local;` in `timezone-0.11.1/lib/src/env.dart:15`; scratch run: reading it throws `LateError` |
| `initializeTimeZones()` alone would not have fixed the hour | `initializeDatabase` ends with `setLocalLocation(_utc)` (`env.dart:56`); scratch run: `tz.local` is `Etc/UTC` after init. Without `setLocalLocation(real zone)` a 17:00 reminder would be scheduled at 17:00 UTC |
| `latest.dart` lacks legacy aliases | `grep -c` on the shipped `.tzf` files: `Asia/Calcutta` and `US/Eastern` are 0 in `latest.tzf`, 1 in `latest_all.tzf`; scratch run: `getLocation('Asia/Calcutta')` throws `LocationNotFoundException` under `latest`, resolves under `latest_all` |
| Android can report legacy ids | flutter_timezone 5.1.1 returns `ZoneId.systemDefault().id` / `TimeZone.getDefault().id` unchanged |
| The platform only receives zone name + wall clock | `tz_datetime_mapper.dart`: `{timeZoneName: location.name, scheduledDateTime: 'YYYY-MM-DDTHH:MM:SS', ...}`; Android `zonedScheduleNotification` rebuilds the instant with `ZoneId.of(timeZoneName)`; iOS `buildUserNotificationCalendarTrigger` uses `timeZoneWithName:` + H/M/S components |
| A synthetic `Location` is equivalent for scheduling | Scratch run: synthetic `Asia/Calcutta` (+05:30, one zone) and real `Asia/Kolkata` give identical maps apart from the name and the same `millisecondsSinceEpoch`. `TimeZone` takes a `Duration` in 0.11.1 (plan corrected) |
| Repeats are computed by the platform, not Dart | Android `getNextFireDateMatchingDateTimeComponents` recomputes the next fire in `ZoneId.of(timeZoneName)` at schedule time and after each fire (`scheduleNextNotification`); iOS uses `repeats:YES` |
| `validateDateIsInTheFuture` is skipped for repeating schedules | `helpers.dart:12` returns early when `matchDateTimeComponents != null` |
| Rescheduling the same id is a replace, not a duplicate | Android: same `PendingIntent` request code (`getBroadcastPendingIntent(context, id, ..)`) plus `saveScheduledNotification` keyed by id; iOS: same request identifier |
| Android recreates alarms after reboot and app update, from its own cache | `ScheduledNotificationBootReceiver` handles `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, quickboot; `cancelAll` empties that cache (`saveScheduledNotifications(.., new ArrayList)`) |
| `exact_alarms_not_permitted` is a plugin error, not a crash | `checkCanScheduleExactAlarms` throws `ExactAlarmPermissionException` → `result.error("exact_alarms_not_permitted")` |
| The legacy time format shifts after travel | Scratch run: the instant for 17:00 Halifax decodes as 17:00 under `TZ=America/Halifax` in both DST phases, and as 13:00 under `TZ=America/Vancouver` |
| Desktop never reaches this code | `_main` takes the `isDesktop` branch before `_initializeApp`; the Notifications section is `isMobile`-gated |
| The reporter's code was this code | `git diff agelapse-v2.6.0 HEAD -- lib/utils/notification_util.dart` is whitespace only; main.dart, create_project_sheet.dart and the settings toggle are unchanged in substance |
| The plugin is a singleton | `factory FlutterLocalNotificationsPlugin() => _instance;` so the two `initialize()` calls today act on one object |

### 3.2 What the analysis changed in the plan

1. **Nothing on the launch path.** The first draft awaited `initialize()`
   inside `_initializeApp`'s `Future.wait`. A slow or hung platform channel
   would then delay the first frame for a feature that cannot matter until
   seconds later. Now `start()` is fire-and-forget and the scheduler awaits
   its own `_ready` future internally.
2. **`tz.local` is gone from the design.** The first draft re-initialized the
   global earlier. A global `late` is the kind of thing that breaks again the
   next time someone adds a code path. Passing the `Location` explicitly makes
   the failure mode impossible rather than less likely.
3. **Zone resolved per schedule, not cached at init.** A user who changes the
   device timezone (or lands after a flight with automatic timezone on) while
   the app process is alive would otherwise schedule in the stale zone.
4. **Fallback for a missing zone id, not only an unknown one.**
   `FlutterTimezone.getLocalTimezone()` can throw or return an empty string on
   odd builds; `GMT±HH:MM` from the current offset is accepted by Java and
   degrades to the device zone on iOS.
5. **Plugin permission API instead of permission_handler.** The plugin already
   exposes `requestNotificationsPermission`, `areNotificationsEnabled`,
   `canScheduleExactNotifications`, `requestExactAlarmsPermission`
   (Android) and `requestPermissions`/`checkPermissions` (iOS). One
   dependency fewer in this path, and the checks line up exactly with what
   `zonedSchedule` will do.
6. **Check exact-alarm availability before scheduling, and still catch.** The
   first draft only caught the exception. Checking first also feeds the status
   line.
7. **`scheduleProject` respects the global toggle** (bug 1.3.9, found during
   the analysis: changing the time with the toggle off schedules anyway).
8. **Reconcile also cancels pending ids that are not projects.** Belt and
   braces for a project deletion whose cancel step failed.
9. **Android channel name** becomes "Daily reminders": the current
   `daily_notification_channel_name` is user-visible in system settings. The
   id stays, so existing channels are renamed in place.
10. **iOS requests alert and sound only.** Badge was never used.
11. **Payload carries the project id** so a tap handler later costs nothing.
12. **`TimeZone(Duration, ...)`**, not milliseconds (compile error in the first
    snippet).

### 3.3 Edge cases, with verdicts

Legend: handled = the plan covers it; accepted = known, small, left alone;
later = out of scope, noted.

**Timezone and time**

- Legacy zone id (`Asia/Calcutta`, `US/Eastern`): handled by `latest_all`
  plus the synthetic fallback.
- Zone id missing or empty: handled by the `GMT±HH:MM` fallback.
- Device timezone changes while the app runs: handled (resolve per schedule;
  every launch reconciles).
- Device timezone changes while the app is closed: the alarm keeps firing at
  HH:MM in the old zone until the next launch, then reconcile re-pins it.
  Accepted; the only alternative is a background job for a minutes-wide
  error that self-heals on open.
- DST transitions: handled by the platforms (they compute every next fire in
  the named zone). A reminder set inside a spring-forward gap (for example
  02:30) fires once at the adjusted time on that day. Accepted.
- Reminder time equals the current minute: Android fires within seconds
  (`while (nextFireDate.isBefore(now))` leaves "now"); iOS likewise. Accepted,
  same as today.
- Legacy epoch-ms values: handled by `ReminderTime.parse` (decoded exactly
  as today, then written back as `HH:MM` the next time the user picks a time).
  A user who already moved timezones keeps the shifted hour until they
  re-pick it. Accepted; a one-time silent "correction" would guess wrong as
  often as right.
- `"not set"` or garbage in the row: handled (17:00).
- Half-hour and negative offsets (St. John's, Kolkata): verified through the
  mapper in the scratch run.

**Permissions**

- Android 13+ notification permission denied: alarms are still scheduled
  (AlarmManager does not need `POST_NOTIFICATIONS`), the posted notification
  is dropped by the OS, the settings status line says so, toggle-on shows the
  SnackBar with "Open settings". When the user grants it in system settings,
  the next fire shows without any app action. Handled.
- Android "ask twice then permanently denied": the second request returns
  denied without a dialog; the SnackBar path covers it. Handled.
- Exact alarms: Android 12 pre-grants `SCHEDULE_EXACT_ALARM` (revocable);
  Android 13+ honours `USE_EXACT_ALARM`, which the manifest declares, so
  `canScheduleExactAlarms()` is true without a prompt. If revoked on 12, the
  user-driven paths ask once via the system page, then fall back to inexact.
  Handled. (`USE_EXACT_ALARM` would be a Play policy problem for a non-alarm
  app; AgeLapse is sideloaded. Later.)
- Inexact fallback timing: `setAndAllowWhileIdle` can be late by minutes, in
  Doze potentially until the next maintenance window. Accepted as better than
  no reminder, and logged so a report can be diagnosed.
- iOS permission denied: requests are still added; iOS does not deliver. The
  status line and SnackBar cover it. Handled.
- iOS prompt timing moves from first launch to project creation. The dialog
  appears over the create sheet because `_createProject` awaits before
  navigating. Existing installs already have a determination, so no second
  prompt. Handled; deliberate.
- Android 11+ permission auto-reset / app hibernation after months unused:
  revokes `POST_NOTIFICATIONS` and force-stops the app, which also drops its
  alarms. Reconcile on the next launch restores the alarms; the permission
  needs the user again (status line). Accepted; nothing an app can do.
- Samsung "sleeping / deep sleeping apps": can suppress alarms for apps the
  user has not opened in a while. Not a code matter; worth one line in the
  reply on #36 as a thing to check if it ever recurs.

**Platform lifecycle**

- App killed between saving the time and `zonedSchedule` completing: the
  row is right, the alarm is wrong; reconcile at next launch fixes it.
  Handled; this is the reason reconcile is the backbone rather than a nicety.
- Reboot: plugin recreates alarms from its cache. If the fire time passed
  while the phone was off, the plugin schedules the stored (past) time, so the
  reminder fires right after boot, once, then resumes daily. Accepted.
- App update (`MY_PACKAGE_REPLACED`): plugin recreates from cache
  immediately; our reconcile at next launch replaces them with the current
  settings. Between the two, the old alarms behave as before. Handled.
- Install-over-existing (what the reporter called "reinstall"): same as an
  update. Handled. True uninstall + install: alarms and plugin cache gone;
  onboarding creates a project and schedules; reconcile covers a restored
  DB too (Android Auto Backup is on by default for this manifest, but its
  25 MB quota makes a successful restore unlikely for anyone with photos).
- "Clear data": force-stops the app (alarms dropped) and wipes the plugin
  cache and DB. Fresh state; handled.
- Launched by tapping the reminder: reconcile reschedules the same id; the
  Android loop lands on tomorrow because now ≥ today's time. No double fire,
  because the alarm is a replace. Handled.
- Reconcile on resume: not in the plan. It would only help the "timezone
  changed while closed" case a few minutes sooner than the next launch, and
  every resume would cost N channel calls. Later, if ever.

**Multiple projects and data**

- Toggle on with N projects: reconcile schedules all N (fixes 1.3.1).
- Toggle off: `cancelAll`, which on Android also clears delivered
  notifications. The app posts nothing else, so that is fine. Handled.
- Two projects at the same minute: two notifications, as today. Grouping
  them is a UX improvement for later.
- Deleted project: `deleteProject` cancels the id; reconcile sweeps strays.
  Handled.
- Zero projects: reconcile logs and does nothing. Handled.
- Notification id = project id: SQLite autoincrement, far below 2^31. The
  unused `showImmediateNotification` (id 9999) is deleted, removing the only
  collision candidate.
- Project created in test mode: scheduler is a no-op in test mode, so
  integration tests keep running without prompts. Handled.

**Concurrency**

- Toggle on/off/on quickly: the settings write happens before each operation
  is enqueued, every operation re-reads `enable_notifications` when it runs,
  and operations run in order. Final state matches the last write. Handled.
- Reconcile at startup racing a toggle-off: the toggle's write lands, the
  queued reconcile reads false and cancels. Handled.
- Two settings sheets (phone rotated, dialog reopened): same queue. Handled.

**UI**

- The toggle is global but lives in each project's settings. The plan keeps
  the semantics; the label "Enable notifications" could become "Enable daily
  reminders (all projects)" for one line of code. Optional.
- Status line goes stale if reconcile finishes after the sheet opened. It is
  refreshed after the user's own actions, which is when they look. Accepted.
- Failure messages are English like the rest of the settings UI. Accepted.

**Release and migration**

- Users whose reminders were silently dead for months will get reminders
  again after updating, without touching anything. That is the fix working,
  but it must be in the changelog so it is not reported as a regression.
- Users who turned the toggle off stay off (reconcile cancels). Handled.
- No DB migration. `ReminderTime.parse` reads both formats forever.
- `test/utils/notification_util_test.dart` (signature-only assertions on
  `NotificationUtil`) must be rewritten alongside the removal.

### 3.4 Risks in the plan itself

- **Behavioural surface.** This touches first launch, project creation,
  settings and deletion. All new code paths are wrapped so they cannot throw
  into those flows; the worst case is "no reminder", which is where we are
  now. The device checklist in 2.6 is the real gate; unit tests cover the
  decisions, not the platforms.
- **Reliance on plugin internals for the fallback.** The synthetic location
  depends on the plugin sending the zone *name* and the platform resolving it.
  That is the plugin's documented contract (`zonedSchedule` with a
  `TZDateTime`), the id comes from the platform itself, and a unit test asserts
  `location.name == id`. flutter_local_notifications is pinned at `^22.3.1`;
  a major bump should re-run 2.6.
- **The fallback hides a real problem by design.** If the Dart database
  lacks a zone, we log it and carry on instead of surfacing it. That is the
  right trade for a reminder, but the log line is what makes it diagnosable,
  so it should not be dropped during implementation.
- **Scope.** The core fix is 2.1, 2.2, 2.4 and the logging. The two pieces
  that can be cut without weakening it are the `HH:MM` storage change (2.3)
  and the status line in settings. Everything else is needed for the bug not
  to come back in a different shape.
- **`latest_all` size.** About 190 KB of extra data in the Dart snapshot.
  Not a concern at the current APK size; noted because it is a one-way door
  nobody will revisit.

### 3.5 Alternatives considered

- **Minimal patch:** call `initializeTimeZones()` + `setLocalLocation` at
  startup and await the schedule call. Fixes the throw. Leaves legacy zone
  ids failing (1.2), the toggle losing other projects (1.3.1), no recovery
  for anyone already in the broken state (1.3.2) and silent failures (1.3.8).
  Users like the reporter would still have to toggle to recover. Rejected.
- **Synthetic location only, drop the Dart timezone database.** Smaller and
  fewer moving parts; the fallback already proves it works for this plugin.
  Rejected as the primary path because it is unconventional enough to be
  "fixed" by a future reader, and because Dart-side instants would be
  fixed-offset, which is a trap if #40 ever computes multi-day instants in
  Dart. Kept as the fallback.
- **Store a schedule fingerprint and skip reconcile when nothing changed.**
  Saves N cheap channel calls per launch at the cost of a new setting and a
  new way to be wrong. Rejected; rescheduling is idempotent.
- **A background job (WorkManager / BGTask) to re-check daily.** Not needed;
  both platforms already repeat reliably, and it adds permissions and
  battery cost. Rejected.
- **Per-project enable toggle.** Reasonable, separate feature. Later.

### 3.6 Not verified, and how to close each

- Whether iOS delivers pending requests that were added *before*
  authorization was granted. The plan does not depend on it: user-driven
  paths request first and schedule second, and every launch reschedules.
  Close with device check 9 (deny, then allow in Settings, then relaunch).
- Whether `[NSTimeZone timeZoneWithName:@"GMT+05:30"]` resolves. If not, iOS
  uses the device zone, which is the intended result. No action.
- Exact behaviour of Samsung's sleeping-apps policy on the S25 Ultra. Device
  check on a Samsung if one is available; otherwise ask the reporter once
  2.8.0 is out.
- Parse time of `latest_all` on a low-end phone (10 ms on this Mac). It runs
  off the critical path either way; a `Stopwatch` log line in `start()`
  turns this into a measurement on the next exported log.

### 3.7 The reporter's story, replayed against the new design

1. Creates a project: permission prompt, reminder at 17:00 scheduled, log
   line with zone and next fire time.
2. Gets the 17:00 reminder, opens the app (new process), sets 21:00: row
   saved as `21:00`, `scheduleProject` resolves the zone, schedules, logs.
   The 21:00 reminder arrives.
3. Toggles off: `cancelAll`. Toggles on: permissions already granted,
   `reconcile` schedules every project. Sets 17:00: rescheduled.
4. Installs the APK over the app: plugin recreates from cache; next launch
   reconciles. Reminders continue.
5. Still broken? Info → Export Logs now contains `[Reminders] ...` lines
   with the zone, mode, next fire time and any platform error, which is the
   information this issue has been missing for five months.

### 3.8 Suggested commit order

1. `ReminderTime` + tests (pure, no behaviour change yet).
2. `ReminderScheduler` + `ReminderBackend` + tests, with `NotificationUtil`
   delegating to it (no call-site changes yet; the throw is already gone at
   this point because the scheduler never reads `tz.local`).
3. Call sites: main, create sheet, settings sheet, deleteProject; delete
   `NotificationUtil` and the old main.dart init; rewrite the signature test.
4. Settings status line and SnackBars.
5. README changelog line.
6. Device checklist (2.6) on Android 13+ and iOS before tagging 2.8.0.
