import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local (on-device) reminders — weekly summary, bill-due nudges, overspend
/// alerts. Nothing leaves the phone.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {/* falls back to UTC */}
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'aeris_alerts',
          'AERIS reminders',
          channelDescription: 'Budget, bill and weekly summary reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  Future<void> showNow(int id, String title, String body) async {
    await init();
    await _plugin.show(id, title, body, _details);
  }

  Future<void> scheduleWeeklySummary({int weekday = DateTime.sunday, int hour = 19}) async {
    await init();
    await _plugin.zonedSchedule(
      1001,
      'Your weekly money summary 📊',
      'Open AERIS to see where your money went this week.',
      _nextWeekday(weekday, hour),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// A once-a-day nudge to claim the check-in reward and keep the streak alive.
  /// Repeats daily at [hour] using the time-of-day match.
  Future<void> scheduleDailyCheckin({int hour = 9}) async {
    await init();
    await _plugin.zonedSchedule(
      1002,
      'Your daily AERIS reward 🎁',
      'Check in now to claim today\'s Aura and keep your streak alive!',
      _nextTimeOfDay(hour),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  Future<void> cancelDailyCheckin() => _plugin.cancel(1002);

  Future<void> scheduleBillReminder(
      int index, String merchant, double amount, int dayOfMonth) async {
    await init();
    await _plugin.zonedSchedule(
      2000 + index,
      'Upcoming bill: $merchant',
      '~₹${amount.toStringAsFixed(0)} is usually due around now.',
      _nextDayOfMonth(dayOfMonth.clamp(1, 28), 10),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  tz.TZDateTime _nextWeekday(int weekday, int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  tz.TZDateTime _nextTimeOfDay(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d;
  }

  tz.TZDateTime _nextDayOfMonth(int day, int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, day, hour);
    if (!d.isAfter(now)) d = tz.TZDateTime(tz.local, now.year, now.month + 1, day, hour);
    return d;
  }
}
