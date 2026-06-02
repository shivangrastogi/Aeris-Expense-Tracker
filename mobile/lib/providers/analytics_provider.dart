import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'transactions_provider.dart';

/// The period the analytics + home dashboards are computed over.
class AnalyticsRange {
  final DateTime start;
  final DateTime end; // inclusive (end-of-day)
  final String label;
  const AnalyticsRange(this.start, this.end, this.label);

  static DateTime _eod(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  factory AnalyticsRange.thisMonth() {
    final n = DateTime.now();
    return AnalyticsRange(
        DateTime(n.year, n.month, 1), _eod(n), 'This month');
  }

  factory AnalyticsRange.lastDays(int days, String label) {
    final n = DateTime.now();
    final start =
        DateTime(n.year, n.month, n.day).subtract(Duration(days: days - 1));
    return AnalyticsRange(start, _eod(n), label);
  }

  factory AnalyticsRange.thisYear() {
    final n = DateTime.now();
    return AnalyticsRange(DateTime(n.year, 1, 1), _eod(n), 'This year');
  }

  factory AnalyticsRange.custom(DateTimeRange r) {
    return AnalyticsRange(
      DateTime(r.start.year, r.start.month, r.start.day),
      _eod(r.end),
      '${shortDay(r.start)} – ${shortDay(r.end)}',
    );
  }
}

/// Currently-selected analytics period (shared by Home + Analytics).
final analyticsRangeProvider =
    StateProvider<AnalyticsRange>((_) => AnalyticsRange.thisMonth());

/// Aggregated view over transactions for the selected [AnalyticsRange].
/// (Field names keep the `month*` prefix for compatibility, but they now hold
/// totals for whatever period is selected.)
class AnalyticsSnapshot {
  final double monthIncome;
  final double monthExpense;
  final double monthNet;
  final double dailyAvgExpense;
  final Map<String, double> byCategory;
  final Map<String, double> dailyExpenseSeries; // 'YYYY-MM-DD' → expense
  final Map<String, double> monthlyExpenseSeries; // all-time 'YYYY-MM'
  final Map<String, double> monthlyIncomeSeries;
  final Map<String, double> topMerchants;
  final DateTime start;
  final DateTime end;
  final String label;

  const AnalyticsSnapshot({
    required this.monthIncome,
    required this.monthExpense,
    required this.monthNet,
    required this.dailyAvgExpense,
    required this.byCategory,
    required this.dailyExpenseSeries,
    required this.monthlyExpenseSeries,
    required this.monthlyIncomeSeries,
    required this.topMerchants,
    required this.start,
    required this.end,
    required this.label,
  });

  factory AnalyticsSnapshot.from(List<Transaction> txns, AnalyticsRange range) {
    final start = range.start;
    final end = range.end;
    double inSum = 0, outSum = 0;
    final byCat = <String, double>{};
    final daily = <String, double>{};
    final mExp = <String, double>{};
    final mInc = <String, double>{};
    final merchants = <String, double>{};

    for (final t in txns) {
      final mk = '${t.timestamp.year}-${t.timestamp.month.toString().padLeft(2, '0')}';
      if (t.isCredit) {
        mInc[mk] = (mInc[mk] ?? 0) + t.amount;
      } else {
        mExp[mk] = (mExp[mk] ?? 0) + t.amount;
      }

      // Restrict the dashboard aggregates to the selected range.
      if (t.timestamp.isBefore(start) || t.timestamp.isAfter(end)) continue;
      if (t.isCredit) {
        inSum += t.amount;
        continue;
      }
      outSum += t.amount;
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      final dk = '${t.timestamp.year}-'
          '${t.timestamp.month.toString().padLeft(2, '0')}-'
          '${t.timestamp.day.toString().padLeft(2, '0')}';
      daily[dk] = (daily[dk] ?? 0) + t.amount;
      if (t.merchant != null && t.merchant!.isNotEmpty) {
        merchants[t.merchant!] = (merchants[t.merchant!] ?? 0) + t.amount;
      }
    }

    final now = DateTime.now();
    final effEnd = end.isBefore(now) ? end : now;
    final daysElapsed = effEnd.difference(start).inDays + 1;
    final avg = daysElapsed <= 0 ? 0.0 : outSum / daysElapsed;

    final sortedMerch = merchants.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topMerch = <String, double>{
      for (final e in sortedMerch.take(8)) e.key: e.value
    };

    return AnalyticsSnapshot(
      monthIncome: inSum,
      monthExpense: outSum,
      monthNet: inSum - outSum,
      dailyAvgExpense: avg,
      byCategory: byCat,
      dailyExpenseSeries: daily,
      monthlyExpenseSeries: mExp,
      monthlyIncomeSeries: mInc,
      topMerchants: topMerch,
      start: start,
      end: end,
      label: range.label,
    );
  }
}

final analyticsProvider = Provider<AsyncValue<AnalyticsSnapshot>>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  final tx = ref.watch(transactionsStreamProvider);
  return tx.whenData((txns) => AnalyticsSnapshot.from(txns, range));
});
