import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class ReminderController {
  ReminderController._();

  static final _notifications = FlutterLocalNotificationsPlugin();
  static Future<void>? _initialization;
  static const _notificationId = 2100;

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(timezoneInfo.identifier));
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  static Future<bool> scheduleDaily({
    required int hour,
    required int minute,
  }) async {
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    final iosGranted = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    if (androidGranted == false || iosGranted == false) return false;

    final now = timezone.TZDateTime.now(timezone.local);
    var scheduled = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: _notificationId,
      title: 'Waktunya menulis diary',
      body: 'Luangkan waktu sejenak untuk mencatat harimu.',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'diary_daily_reminder',
          'Pengingat diary',
          channelDescription: 'Pengingat harian untuk menulis diary.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  static Future<void> cancel() async {
    await initialize();
    await _notifications.cancel(id: _notificationId);
  }
}
