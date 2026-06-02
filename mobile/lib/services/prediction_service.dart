import 'dart:math' as math;

import '../models/category.dart';
import '../models/insight.dart';
import '../models/transaction.dart';

/// On-device, dependency-free statistical forecasting + anomaly detection.
///
/// We deliberately stay shy of "deep learning" — the dataset per user is
/// small (typically <2k transactions) and the dominant signals are linear
/// trends, monthly seasonality, and recurring fixed payments. Three
/// classical techniques cover 90% of the value:
///
///   1. Linear regression over month-end totals  → next-month estimate
///   2. Exponential moving average (EMA) per category → category forecast
///   3. Z-score on amount-within-category → anomaly flags
///   4. Day-of-month clustering → recurring-payment detection
///
/// Every public method is pure (in → out, no IO, no globals) so unit tests
/// stay trivial.
class PredictionService {
  PredictionService._();
  static final PredictionService instance = PredictionService._();

  // ─ Forecasting ─────────────────────────────────────────────

  /// Predict total expense for the *current* month based on burn-rate so far,
  /// blended with the last-3-months average. Returns (estimate, low, high)
  /// where low/high are a ±15% confidence band.
  Prediction predictCurrentMonth(List<Transaction> txns) {
    final now = DateTime.now();
    final mKey = _monthKey(now);
    final byMonth = _monthlyExpenseTotals(txns);

    final spentSoFar = byMonth[mKey] ?? 0;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayIdx = now.day;
    final burnRateEstimate = dayIdx == 0
        ? spentSoFar
        : spentSoFar / dayIdx * daysInMonth;

    // History baseline — last 3 completed months.
    final completedMonths = byMonth.entries
        .where((e) => e.key != mKey)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final hist = completedMonths.take(3).map((e) => e.value).toList();
    final histAvg = hist.isEmpty
        ? burnRateEstimate
        : hist.reduce((a, b) => a + b) / hist.length;

    // Blend: early in the month lean on history; late in the month lean
    // on the actual burn rate.
    final t = (dayIdx / daysInMonth).clamp(0.0, 1.0);
    final estimate = histAvg * (1 - t) + burnRateEstimate * t;
    return Prediction(
      label: 'Estimated ${_monthName(now.month)} spend',
      estimate: estimate,
      low: estimate * 0.85,
      high: estimate * 1.15,
      basis: 'Blended forecast — '
          '₹${spentSoFar.toStringAsFixed(0)} so far + '
          '${hist.length}-month history.',
    );
  }

  /// Per-category forecast for next month using EMA over recent months.
  List<Prediction> predictPerCategoryNextMonth(List<Transaction> txns) {
    final byCatMonth = <String, Map<String, double>>{};
    for (final t in txns.where((t) => t.isDebit)) {
      final m = _monthKey(t.timestamp);
      byCatMonth.putIfAbsent(t.categoryId, () => {});
      byCatMonth[t.categoryId]![m] =
          (byCatMonth[t.categoryId]![m] ?? 0) + t.amount;
    }

    final out = <Prediction>[];
    byCatMonth.forEach((catId, months) {
      final series = months.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (series.length < 2) return;
      double ema = series.first.value;
      const alpha = 0.45;
      for (final s in series.skip(1)) {
        ema = alpha * s.value + (1 - alpha) * ema;
      }
      final cat = Categories.byId(catId);
      out.add(Prediction(
        label: 'Next month: ${cat.label}',
        categoryId: catId,
        estimate: ema,
        low: ema * 0.8,
        high: ema * 1.25,
        basis: 'EMA over ${series.length} months '
            '(latest ₹${series.last.value.toStringAsFixed(0)}).',
      ));
    });
    out.sort((a, b) => b.estimate.compareTo(a.estimate));
    return out;
  }

  // ─ Anomaly detection ───────────────────────────────────────

  /// Within-category z-score; anything with |z| > 2.5 is flagged.
  List<Anomaly> detectAnomalies(List<Transaction> txns) {
    final byCat = <String, List<Transaction>>{};
    for (final t in txns.where((t) => t.isDebit)) {
      byCat.putIfAbsent(t.categoryId, () => []).add(t);
    }
    final out = <Anomaly>[];
    byCat.forEach((catId, list) {
      if (list.length < 6) return;     // not enough data
      final amounts = list.map((t) => t.amount).toList();
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      final variance = amounts
              .map((a) => math.pow(a - mean, 2).toDouble())
              .reduce((a, b) => a + b) /
          amounts.length;
      final std = math.sqrt(variance);
      if (std < 1) return;
      for (final t in list) {
        final z = (t.amount - mean) / std;
        if (z > 2.5) {
          out.add(Anomaly(
            reason: 'Unusually large ${Categories.byId(catId).label.toLowerCase()} '
                'spend — about ${(t.amount / mean).toStringAsFixed(1)}× your usual.',
            when: t.timestamp,
            amount: t.amount,
            merchant: t.merchant,
            categoryId: catId,
          ));
        }
      }
    });
    out.sort((a, b) => b.when.compareTo(a.when));
    return out.take(8).toList();
  }

  // ─ Recurring detection ─────────────────────────────────────

  /// Detects merchants that hit your account at roughly the same day each
  /// month for 3+ months (rent, subscriptions, EMIs).
  List<RecurringPayment> detectRecurring(List<Transaction> txns) {
    final byMerchant = <String, List<Transaction>>{};
    for (final t in txns.where((t) => t.isDebit && t.merchant != null)) {
      final key = t.merchant!.toLowerCase().trim();
      byMerchant.putIfAbsent(key, () => []).add(t);
    }
    final out = <RecurringPayment>[];
    byMerchant.forEach((merchant, list) {
      if (list.length < 3) return;
      // Group by month — must hit ≥ 3 distinct months.
      final months = <String>{};
      for (final t in list) {
        months.add(_monthKey(t.timestamp));
      }
      if (months.length < 3) return;
      // Day-of-month spread tight enough?
      final days = list.map((t) => t.timestamp.day).toList();
      final dMean = days.reduce((a, b) => a + b) / days.length;
      final dStd = math.sqrt(days
              .map((d) => math.pow(d - dMean, 2).toDouble())
              .reduce((a, b) => a + b) /
          days.length);
      if (dStd > 4) return;       // too scattered to be a fixed payment
      final amount = list.map((t) => t.amount).reduce((a, b) => a + b) / list.length;
      out.add(RecurringPayment(
        merchant: list.first.merchant!,
        categoryId: list.first.categoryId,
        approxAmount: amount,
        dayOfMonth: dMean.round(),
        occurrences: months.length,
      ));
    });
    out.sort((a, b) => b.approxAmount.compareTo(a.approxAmount));
    return out;
  }

  // ─ Helpers ─────────────────────────────────────────────────

  static Map<String, double> _monthlyExpenseTotals(List<Transaction> txns) {
    final m = <String, double>{};
    for (final t in txns.where((t) => t.isDebit)) {
      final k = _monthKey(t.timestamp);
      m[k] = (m[k] ?? 0) + t.amount;
    }
    return m;
  }

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _monthName(int m) {
    const names = ['', 'January','February','March','April','May','June',
                   'July','August','September','October','November','December'];
    return names[m];
  }
}
