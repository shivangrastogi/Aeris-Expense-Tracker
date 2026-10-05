import 'package:shared_preferences/shared_preferences.dart';

import '../core/routes.dart';
import '../models/budget.dart';
import '../models/insight.dart';
import '../models/subscription.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'money_insights.dart';
import 'notification_service.dart';

/// A bill the calendar and reminders know about: a saved subscription, or a
/// payment AERIS spotted repeating every month.
class Bill {
  final String name;
  final double amount;
  final int day; // day of month it's due
  final String categoryId;
  final bool detected; // true = spotted from history, not saved by the user

  const Bill({
    required this.name,
    required this.amount,
    required this.day,
    required this.categoryId,
    this.detected = false,
  });

  /// Next due date on/after [from] (day clamped to short months).
  DateTime nextDue(DateTime from) {
    DateTime due(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, day.clamp(1, last));
    }

    final start = DateTime(from.year, from.month, from.day);
    final thisMonth = due(from.year, from.month);
    return thisMonth.isBefore(start) ? due(from.year, from.month + 1) : thisMonth;
  }

  /// Saved subscriptions plus detected recurring payments not already saved.
  static List<Bill> from(
      List<Subscription> subs, List<RecurringPayment> recurring) {
    final out = [
      for (final s in subs)
        Bill(
            name: s.name,
            amount: s.amount,
            day: s.day,
            categoryId: s.categoryId),
    ];
    // A detected payment is the same bill as a saved one when the names share
    // a word ("Rent" / "Rent · Mr. Sharma", "Airtel postpaid" / "Airtel
    // recharge") or it's the same category at about the same amount.
    Set<String> words(String s) => s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3)
        .toSet();
    bool isSaved(RecurringPayment r) => subs.any((s) =>
        words(s.name).intersection(words(r.merchant)).isNotEmpty ||
        (s.categoryId == r.categoryId &&
            (s.amount - r.approxAmount).abs() <= s.amount * 0.15));
    for (final r in recurring) {
      if (isSaved(r)) continue;
      out.add(Bill(
          name: r.merchant,
          amount: r.approxAmount,
          day: r.dayOfMonth,
          categoryId: r.categoryId,
          detected: true));
    }
    return out;
  }
}

/// Keeps the "smart reminder" notifications in step with the data. Called
/// (debounced) whenever transactions, budgets or subscriptions change, and
/// when reminders are switched on. Everything is scheduled on-device.
class ReminderScheduler {
  ReminderScheduler._();

  static const _dailyId = 1003;
  static const _recapId = 1001;
  static const _reportId = 1004;
  static const _billBase = 2000;
  static const _billMax = 40;

  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool('reminders_on') ?? false;

  static Future<void> refresh({
    required List<Transaction> txns,
    required List<Budget> budgets,
    required List<Bill> bills,
    DateTime? at,
  }) async {
    if (!await enabled()) return;
    final now = at ?? DateTime.now();
    final n = NotificationService.instance;

    // 1 · 9 PM daily spend alert — with today's real numbers when it's still
    // ahead of us; after 9 PM, tomorrow's generic nudge (refreshed on open).
    final nine = DateTime(now.year, now.month, now.day, 21);
    if (now.isBefore(nine)) {
      final safe = SafeSpend.compute(txns, budgets, now);
      final spentToday = txns
          .where((t) =>
              t.isDebit &&
              t.timestamp.year == now.year &&
              t.timestamp.month == now.month &&
              t.timestamp.day == now.day)
          .fold<double>(0, (s, t) => s + t.amount);
      await n.scheduleOnce(
        _dailyId,
        'Today\'s spending',
        safe?.message ?? 'Today: ${formatRupees(spentToday)} spent',
        nine,
        route: AppRoutes.transactions,
      );
    } else {
      await n.scheduleOnce(
        _dailyId,
        'Today\'s spending',
        'See how today went against your daily limit.',
        nine.add(const Duration(days: 1)),
        route: AppRoutes.transactions,
      );
    }

    // 2 · Sunday 7 PM weekly recap, with this week's headline.
    await n.cancel(_recapId);
    final recap = WeeklyRecap.build(txns, now);
    var sunday = DateTime(now.year, now.month, now.day, 19);
    while (sunday.weekday != DateTime.sunday || !sunday.isAfter(now)) {
      sunday = sunday.add(const Duration(days: 1));
    }
    await n.scheduleOnce(
      _recapId,
      'Your week in money',
      recap == null ? 'Open AERIS for your weekly recap.' : recap.change,
      sunday,
      route: AppRoutes.insights,
    );

    // 3 · Bills: a reminder the day BEFORE each is due, 10 AM.
    for (var i = 0; i < _billMax; i++) {
      await n.cancel(_billBase + i);
    }
    final sorted = [...bills]..sort((a, b) => a.nextDue(now).compareTo(b.nextDue(now)));
    for (var i = 0; i < sorted.length && i < _billMax; i++) {
      final b = sorted[i];
      var due = b.nextDue(now);
      var remind = DateTime(due.year, due.month, due.day - 1, 10);
      if (!remind.isAfter(now)) {
        due = b.nextDue(due.add(const Duration(days: 1)));
        remind = DateTime(due.year, due.month, due.day - 1, 10);
      }
      await n.scheduleOnce(
        _billBase + i,
        'Due tomorrow: ${b.name}',
        '${formatRupees(b.amount)}${b.detected ? ' (usual amount)' : ''} · tap to see your bills',
        remind,
        route: AppRoutes.bills,
      );
    }

    // 4 · Report card on the 1st, 10 AM.
    final first = DateTime(now.year, now.month + 1, 1, 10);
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    await n.scheduleOnce(
      _reportId,
      'Your ${months[now.month]} report card is ready',
      'See your grade for budget, savings and habits.',
      first,
      route: AppRoutes.reportCard,
    );
  }

  static Future<void> cancelAll() => NotificationService.instance.cancelAll();
}
