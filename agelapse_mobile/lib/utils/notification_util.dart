import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/database_helper.dart';

class NotificationUtil {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> cancelNotification(int projectId) async {
    await _flutterLocalNotificationsPlugin.cancel(projectId);
  }

  static Future<void> initializeNotifications() async {
    tz.initializeTimeZones();

    if (defaultTargetPlatform == TargetPlatform.android) {
      var notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
        if (!notificationStatus.isGranted) {
          print('Notification permission denied');
          return;
        }
      }

      var exactAlarmStatus = await Permission.scheduleExactAlarm.status;
      if (!exactAlarmStatus.isGranted) {
        exactAlarmStatus = await Permission.scheduleExactAlarm.request();
        if (!exactAlarmStatus.isGranted) {
          print('Exact alarms permission denied');
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
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    const initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    final initializationSettingsDarwin = DarwinInitializationSettings();

    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (notificationResponse) async {
        // Handle notification response
      },
    );

    // Set the local time zone
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    print("Local timezone set to ${timeZoneName}");
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
      9999,
      'Test Notification',
      'This is an immediate test notification',
      platformDetails,
    );

    print("Immediate notification triggered");
  }

  static Future<void> scheduleDailyNotification(int projectId, String dailyNotificationTime) async {
    print("Schedule daily notif call made.");

    final now = DateTime.now();
    final int timestamp = int.parse(dailyNotificationTime);
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final TimeOfDay selectedTime = TimeOfDay.fromDateTime(dateTime);

    final String? projectName = await DB.instance.getProjectNameById(projectId);
    print("projectName => ${projectName}");

    final tz.TZDateTime scheduledDate = _calculateScheduledDate(now, selectedTime);

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
      projectId,
      'AgeLapse - ${projectName}',
      '${projectName}: Don\'t forget to take your photo!',
      scheduledDate,
      platformDetails,
      payload: 'date: ${scheduledDate.toString()}',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    print("zonedSchedule call made...");

    final List<PendingNotificationRequest> pendingNotifications =
    await _flutterLocalNotificationsPlugin.pendingNotificationRequests();

    pendingNotifications.forEach((notification) {
      print('ID: ${notification.id}');
      print('Title: ${notification.title}');
      print('Body: ${notification.body}');
      print('Payload: ${notification.payload}');
      print('-----------------------');
    });
  }

  static tz.TZDateTime _calculateScheduledDate(DateTime now, TimeOfDay selectedTime) {
    final tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    return scheduledDate.isBefore(now) ? scheduledDate.add(const Duration(days: 1)) : scheduledDate;
  }

  static DateTime getFivePMLocalTime() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      17,
      0,
    );
  }
}
