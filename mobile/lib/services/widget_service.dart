import 'package:home_widget/home_widget.dart';

import '../utils/formatters.dart';

/// Pushes "budget left" to the Android home-screen widget. All values are
/// computed on-device from already-decrypted data; only the formatted strings
/// are handed to the widget.
class WidgetService {
  WidgetService._();

  static String? _lastSig;

  static Future<void> updateBudgetLeft({
    required double left,
    required double target,
    required String label,
  }) async {
    // Avoid redundant native updates.
    final sig = '$left|$target|$label';
    if (sig == _lastSig) return;
    _lastSig = sig;
    final spent = target - left;
    final pct = target > 0 ? ((spent / target) * 100).clamp(0, 100).round() : 0;
    try {
      await HomeWidget.saveWidgetData<String>('title', 'Budget left · $label');
      await HomeWidget.saveWidgetData<String>(
          'amount', target > 0 ? formatRupees(left) : '—');
      await HomeWidget.saveWidgetData<int>('pct', pct);
      await HomeWidget.saveWidgetData<String>(
          'sub',
          target > 0
              ? 'Spent ${formatRupees(spent)} of ${formatRupees(target)}'
              : 'Set a budget in AERIS');
      await HomeWidget.updateWidget(androidName: 'AerisWidgetProvider');
    } catch (_) {/* widget not added / platform unsupported */}
  }
}
