import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';

class NotificationUtil {
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> cancelNotification(int projectId) async {
    await _flutterLocalNotificationsPlugin.cancel(id: projectId);
  }

  static Future<void> initializeNotifications() async {
    tz.initializeTimeZones();

    if (defaultTargetPlatform == TargetPlatform.android) {
      var notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
        if (!notificationStatus.isGranted) {
          return;
        }
      }

      var exactAlarmStatus = await Permission.scheduleExactAlarm.status;
      if (!exactAlarmStatus.isGranted) {
        exactAlarmStatus = await Permission.scheduleExactAlarm.request();
        if (!exactAlarmStatus.isGranted) {
          return;
        }
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'daily_notification_channel_id',
        'daily_notification_channel_name',
        importance: Importance.max,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final initializationSettingsDarwin = DarwinInitializationSettings();

    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (notificationResponse) async {
        // maybe do something here in the future?
      },
    );

    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
  }

  static Future<void> showImmediateNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'daily_notification_channel_id',
      'daily_notification_channel_name',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iOSDetails = DarwinNotificationDetails();
    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id: 9999,
      title: 'Test Notification',
      body: 'This is an immediate test notification',
      notificationDetails: platformDetails,
    );
  }

  static Future<void> scheduleDailyNotification(
    int projectId,
    String dailyNotificationTime,
  ) async {
    final now = DateTime.now();
    final int timestamp = int.parse(dailyNotificationTime);
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final TimeOfDay selectedTime = TimeOfDay.fromDateTime(dateTime);

    final String? projectName = await DB.instance.getProjectNameById(projectId);
    LogService.instance.log("projectName => $projectName");

    final tz.TZDateTime scheduledDate = _calculateScheduledDate(
      now,
      selectedTime,
    );

    const androidDetails = AndroidNotificationDetails(
      'daily_notification_channel_id',
      'daily_notification_channel_name',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iOSDetails = DarwinNotificationDetails();
    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: projectId,
      title: 'AgeLapse - $projectName',
      body: '$projectName: Don\'t forget to take your photo!',
      scheduledDate: scheduledDate,
      notificationDetails: platformDetails,
      payload: 'date: ${scheduledDate.toString()}',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _calculateScheduledDate(
    DateTime now,
    TimeOfDay selectedTime,
  ) {
    final tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    return scheduledDate.isBefore(now)
        ? scheduledDate.add(const Duration(days: 1))
        : scheduledDate;
  }

  static DateTime getFivePMLocalTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 17, 0);
  }
}
