import 'package:home_widget/home_widget.dart';

import '../utils/formatters.dart';

/// Pushes all home-screen widget data to Android. Every value is computed
/// on-device from already-decrypted data; only the formatted strings are
/// handed to the widgets. Drives all AERIS widget providers.
class WidgetService {
  WidgetService._();

  static String? _lastSig;

  /// Comprehensive push for every widget (budget, streak, spend, today,
  /// village). Call from the app once data is available.
  static Future<void> pushAll({
    required double spent,
    required double budget,
    required String label,
    required int streak,
    required double todaySpend,
    required int aura,
    required int townLevel,
    String? firstName,
    List<bool>? week,
    int todayIdx = -1,
  }) async {
    final left = budget - spent;
    final pct = budget > 0 ? ((spent / budget) * 100).clamp(0, 100).round() : 0;
    final greeting = (firstName != null && firstName.trim().isNotEmpty)
        ? 'Hi, ${firstName.trim()}!'
        : '';
    // The real Sun→Sat week as a "1,0,1,…" string so the native widget can
    // light up actual check-in days (today stays empty until checked in)
    // instead of just filling the first N dots.
    final weekStr =
        (week ?? const <bool>[]).map((d) => d ? '1' : '0').join(',');

    // Avoid redundant native updates.
    final sig =
        '$spent|$budget|$label|$streak|$todaySpend|$aura|$townLevel|$greeting|$weekStr|$todayIdx';
    if (sig == _lastSig) return;
    _lastSig = sig;

    String auraStr = aura.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

    try {
      // Streak (combined + mini)
      await HomeWidget.saveWidgetData<String>(
          'streak_text', streak > 0 ? '$streak day streak' : '0 day streak');
      await HomeWidget.saveWidgetData<String>(
          'streak_sub',
          streak > 0
              ? 'Keep going, check in today!'
              : 'Start your streak today');
      await HomeWidget.saveWidgetData<String>(
          'streak_num', '$streak day${streak == 1 ? '' : 's'}');
      await HomeWidget.saveWidgetData<int>('streak_count', streak);
      await HomeWidget.saveWidgetData<String>('streak_greeting', greeting);
      // Per-day week state + today's column so dots track the real calendar.
      await HomeWidget.saveWidgetData<String>('streak_week', weekStr);
      await HomeWidget.saveWidgetData<int>('streak_today', todayIdx);

      // Budget (combined + budget widget)
      await HomeWidget.saveWidgetData<String>('title', 'Budget left · $label');
      await HomeWidget.saveWidgetData<String>(
          'amount', budget > 0 ? formatRupees(left) : '—');
      await HomeWidget.saveWidgetData<int>('pct', pct);
      await HomeWidget.saveWidgetData<String>(
          'sub',
          budget > 0
              ? 'Spent ${formatRupees(spent)} of ${formatRupees(budget)}'
              : 'Set a budget in AERIS');
      // Budget ring widget (glass card + drawn circular ring).
      await HomeWidget.saveWidgetData<String>('ring_left_text',
          budget > 0 ? formatRupees(left.abs(), compact: true) : '—');
      await HomeWidget.saveWidgetData<bool>('ring_is_over', left < 0);

      // Month spend widget
      await HomeWidget.saveWidgetData<String>(
          'spent_text', formatRupees(spent, compact: true));
      await HomeWidget.saveWidgetData<String>('spent_sub',
          budget > 0 ? 'of ${formatRupees(budget, compact: true)} budget' : '');

      // Today widget
      await HomeWidget.saveWidgetData<String>(
          'today_text', formatRupees(todaySpend, compact: true));

      // Village widget
      await HomeWidget.saveWidgetData<String>('village_lvl', 'Lv $townLevel');
      await HomeWidget.saveWidgetData<String>('village_aura', auraStr);

      // Refresh every provider.
      for (final name in const [
        'AerisWidgetProvider',
        'AerisStreakWidgetProvider',
        'AerisBudgetWidgetProvider',
        'AerisSpentWidgetProvider',
        'AerisTodayWidgetProvider',
        'AerisStreakMiniWidgetProvider',
        'AerisVillageWidgetProvider',
      ]) {
        await HomeWidget.updateWidget(androidName: name);
      }
    } catch (_) {/* widget not added / platform unsupported */}
  }
}
