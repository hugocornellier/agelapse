import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

class NotificationUtil {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initializeNotifications() async {
    tz.initializeTimeZones();

    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initializationSettingsDarwin = DarwinInitializationSettings(
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        // Handle notification tapped logic here
      },
    );

    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (notificationResponse) async {
        // Handle notification tapped logic here
      },
    );

    final timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
  }

  static Future<void> scheduleDailyNotification(int projectId, String dailyNotificationTime) async {
    print("Schedule daily notif call made.");

    final now = DateTime.now();
    final int timestamp = int.parse(dailyNotificationTime);
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final TimeOfDay selectedTime = TimeOfDay.fromDateTime(dateTime);

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
      'AgeLapse',
      'Don\'t forget to take your photo!',
      scheduledDate,
      platformDetails,
      payload: 'Daily Notification Payload',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
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
    tz.initializeTimeZones();
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
