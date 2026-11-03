import 'package:home_widget/home_widget.dart';

import '../models/transaction.dart';
import '../utils/formatters.dart';

/// Raw numbers behind the home-screen widgets for one moment in time.
///
/// Widgets get RAW values plus the day/month they belong to — never
/// pre-formatted strings — so the native side (WidgetData.kt) can roll them
/// over at midnight / on the 1st by itself, and the background SMS isolate
/// can add a payment without the app being open.
class WidgetSnapshot {
  final double monthSpent; // current calendar month, net of refunds
  final double todaySpent; // today, net of refunds
  final String monthKey; // yyyy-MM the totals belong to
  final String dayKey; // yyyy-MM-dd

  const WidgetSnapshot(this.monthSpent, this.todaySpent, this.monthKey, this.dayKey);

  /// Always the CALENDAR month and today — independent of whatever date range
  /// the Analytics screen happens to be showing.
  factory WidgetSnapshot.compute(Iterable<Transaction> txns, DateTime now) {
    double month = 0, today = 0;
    for (final t in txns) {
      if (t.isInternal) continue; // own-account transfer / share payback
      final ts = t.timestamp;
      if (ts.year != now.year || ts.month != now.month) continue;
      final double v;
      if (t.isRefund) {
        v = -t.spendAmount;
      } else if (t.isCredit) {
        continue;
      } else {
        v = t.spendAmount;
      }
      month += v;
      if (ts.day == now.day) today += v;
    }
    return WidgetSnapshot(
        month < 0 ? 0 : month, today < 0 ? 0 : today, monthKeyOf(now), dayKeyOf(now));
  }

  static String monthKeyOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String dayKeyOf(DateTime d) => '${monthKeyOf(d)}-${d.day.toString().padLeft(2, '0')}';
}

/// Pushes widget data to Android and refreshes every AERIS widget. The
/// native providers read it through WidgetData.kt (one model, one formatter,
/// date rollover, day/night colours).
class WidgetService {
  WidgetService._();

  static const providers = [
    'AerisWidgetProvider',
    'AerisStreakWidgetProvider',
    'AerisBudgetWidgetProvider',
    'AerisSpentWidgetProvider',
    'AerisTodayWidgetProvider',
    'AerisStreakMiniWidgetProvider',
    'AerisVillageWidgetProvider',
  ];

  static String? _lastSig;

  /// Full push from the app (all data decrypted and in memory).
  static Future<void> pushAll({
    required WidgetSnapshot snap,
    required double budget,
    required int streak,
    required String? lastCheckinDay,
    required Iterable<String> checkinDays, // recent yyyy-MM-dd keys
    required int aura,
    required int townLevel,
    String? firstName,
  }) async {
    final c = kCurrency;
    final days = checkinDays.toList()..sort();
    final recent = days.length > 14 ? days.sublist(days.length - 14) : days;
    final data = <String, Object>{
      'w_v': 2,
      'w_month': snap.monthKey,
      'w_spent': snap.monthSpent.toStringAsFixed(2),
      'w_day': snap.dayKey,
      'w_today': snap.todaySpent.toStringAsFixed(2),
      'w_budget': budget.toStringAsFixed(2),
      'w_streak': streak,
      'w_last_checkin': lastCheckinDay ?? '',
      'w_checkins': recent.join(','),
      'w_aura': aura,
      'w_town': townLevel,
      'w_name': (firstName ?? '').trim(),
      'w_cur_symbol': c.symbol,
      'w_cur_rate': c.rate.toString(),
      'w_cur_indian': c.indian,
      'w_hidden': kAmountsHidden,
    };
    final sig = data.values.join('|');
    if (sig == _lastSig) return; // nothing changed — skip the native round trip
    _lastSig = sig;
    try {
      for (final e in data.entries) {
        await _save(e.key, e.value);
      }
      await _save('w_updated', DateTime.now().millisecondsSinceEpoch.toString());
      await refresh();
    } catch (_) {/* no widget placed / platform without widgets */}
  }

  /// From the background SMS isolate: add one saved transaction to the
  /// stored totals (rolling them over first if the day/month changed), so
  /// widgets move the moment a bank SMS lands — app open or not.
  static Future<void> recordInBackground(Transaction t) async {
    if (!t.isSpend && !t.isRefund) return; // only spending moves the spend widgets
    try {
      final now = DateTime.now();
      final ts = t.timestamp;
      if (ts.year != now.year || ts.month != now.month) return; // old SMS
      final month = WidgetSnapshot.monthKeyOf(now);
      final day = WidgetSnapshot.dayKeyOf(now);
      final delta = t.isRefund ? -t.spendAmount : t.spendAmount;

      var spent = double.tryParse(await HomeWidget.getWidgetData<String>('w_spent') ?? '') ?? 0;
      var today = double.tryParse(await HomeWidget.getWidgetData<String>('w_today') ?? '') ?? 0;
      if (await HomeWidget.getWidgetData<String>('w_month') != month) spent = 0;
      if (await HomeWidget.getWidgetData<String>('w_day') != day) today = 0;

      spent = (spent + delta).clamp(0, double.infinity).toDouble();
      if (WidgetSnapshot.dayKeyOf(ts) == day) {
        today = (today + delta).clamp(0, double.infinity).toDouble();
      }
      await _save('w_month', month);
      await _save('w_spent', spent.toStringAsFixed(2));
      await _save('w_day', day);
      await _save('w_today', today.toStringAsFixed(2));
      await _save('w_updated', now.millisecondsSinceEpoch.toString());
      _lastSig = null; // next foreground push must rewrite the exact totals
      await refresh();
    } catch (_) {}
  }

  /// From the background refresh (widget_background.dart): exact month /
  /// today totals ([snap]; null when the data couldn't be read, which keeps
  /// the stored ones) and the streak. Budget, name and currency only change
  /// in the app, so they stay as its last [pushAll] left them.
  static Future<void> pushFromBackground({
    required WidgetSnapshot? snap,
    required int streak,
    required String? lastCheckinDay,
    required Iterable<String> checkinDays,
  }) async {
    final days = checkinDays.toList()..sort();
    final recent = days.length > 14 ? days.sublist(days.length - 14) : days;
    try {
      if (snap != null) {
        await _save('w_month', snap.monthKey);
        await _save('w_spent', snap.monthSpent.toStringAsFixed(2));
        await _save('w_day', snap.dayKey);
        await _save('w_today', snap.todaySpent.toStringAsFixed(2));
      }
      await _save('w_streak', streak);
      await _save('w_last_checkin', lastCheckinDay ?? '');
      await _save('w_checkins', recent.join(','));
      await _save('w_updated', DateTime.now().millisecondsSinceEpoch.toString());
      await refresh();
    } catch (_) {}
  }

  static Future<void> refresh() async {
    for (final name in providers) {
      await HomeWidget.updateWidget(androidName: name);
    }
  }

  static Future<void> _save(String key, Object v) => switch (v) {
        final int i => HomeWidget.saveWidgetData<int>(key, i),
        final bool b => HomeWidget.saveWidgetData<bool>(key, b),
        _ => HomeWidget.saveWidgetData<String>(key, v.toString()),
      };
}
