import 'dart:isolate';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'transactions_provider.dart';

/// Which clock-relative window a range represents, so it can be re-anchored to
/// "now" later. [custom] windows are absolute and never move.
enum RangeKind { thisMonth, lastMonth, lastDays, thisYear, custom }

/// The period the analytics + home dashboards are computed over.
class AnalyticsRange {
  final DateTime start;
  final DateTime end; // inclusive (end-of-day)
  final String label;
  final RangeKind kind;
  final int days; // only meaningful for RangeKind.lastDays
  const AnalyticsRange(this.start, this.end, this.label,
      {this.kind = RangeKind.custom, this.days = 0});

  static DateTime _eod(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  factory AnalyticsRange.thisMonth() {
    final n = DateTime.now();
    return AnalyticsRange(DateTime(n.year, n.month, 1), _eod(n), 'This month',
        kind: RangeKind.thisMonth);
  }

  factory AnalyticsRange.lastMonth() {
    final n = DateTime.now();
    return AnalyticsRange(DateTime(n.year, n.month - 1, 1),
        DateTime(n.year, n.month, 0, 23, 59, 59), 'Last month',
        kind: RangeKind.lastMonth);
  }

  factory AnalyticsRange.lastDays(int days, String label) {
    final n = DateTime.now();
    final start =
        DateTime(n.year, n.month, n.day).subtract(Duration(days: days - 1));
    return AnalyticsRange(start, _eod(n), label,
        kind: RangeKind.lastDays, days: days);
  }

  factory AnalyticsRange.thisYear() {
    final n = DateTime.now();
    return AnalyticsRange(DateTime(n.year, 1, 1), _eod(n), 'This year',
        kind: RangeKind.thisYear);
  }

  factory AnalyticsRange.custom(DateTimeRange r) {
    return AnalyticsRange(
      DateTime(r.start.year, r.start.month, r.start.day),
      _eod(r.end),
      '${shortDay(r.start)} – ${shortDay(r.end)}',
    );
  }

  /// Re-anchor a clock-relative window to the current time.
  ///
  /// The range object is built once — when the user picks it, or at boot for
  /// the default "This month" — but the process routinely outlives the day (and
  /// the month) it was built in, because backgrounding an Android app doesn't
  /// kill it. Without this, `end` stays pinned at boot-day 23:59:59 and every
  /// transaction added afterwards falls outside the window, so it shows up in
  /// Activity but never lands in any dashboard total.
  AnalyticsRange resolved() => switch (kind) {
        RangeKind.thisMonth => AnalyticsRange.thisMonth(),
        RangeKind.lastMonth => AnalyticsRange.lastMonth(),
        RangeKind.lastDays => AnalyticsRange.lastDays(days, label),
        RangeKind.thisYear => AnalyticsRange.thisYear(),
        RangeKind.custom => this,
      };
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
  final Map<String, int> countByCategory; // # of debit txns per category
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
    required this.countByCategory,
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
    final countByCat = <String, int>{};
    final daily = <String, double>{};
    final mExp = <String, double>{};
    final mInc = <String, double>{};
    final merchants = <String, double>{};

    for (final t in txns) {
      final mk =
          '${t.timestamp.year}-${t.timestamp.month.toString().padLeft(2, '0')}';
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
      countByCat[t.categoryId] = (countByCat[t.categoryId] ?? 0) + 1;
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
      countByCategory: countByCat,
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

/// Aggregated dashboard view over the selected [AnalyticsRange].
///
/// The O(n) aggregation is kept off the UI isolate: anything but a tiny ledger
/// is computed in a background isolate ([Isolate.run]), and the last good
/// snapshot is served *while* the next one computes (stale-while-revalidate) so
/// dashboard cards never flash a skeleton on a benign Firestore re-emit.
/// Results are memoised on a cheap content signature, so identical re-emits
/// (cache→server hand-off, reconnects) cost nothing.
final analyticsProvider =
    NotifierProvider<AnalyticsNotifier, AsyncValue<AnalyticsSnapshot>>(
        AnalyticsNotifier.new);

class AnalyticsNotifier extends Notifier<AsyncValue<AnalyticsSnapshot>> {
  // Bumps on every (re)build; an in-flight isolate result carrying a stale
  // token is discarded so a slow compute can never clobber a newer one.
  int _token = 0;

  @override
  AsyncValue<AnalyticsSnapshot> build() {
    // `.resolved()` re-anchors relative windows ("This month", "Last 7 days")
    // to the current clock on every rebuild — the stored range object was built
    // when it was picked, which may have been days ago.
    final range = ref.watch(analyticsRangeProvider).resolved();
    final tx = ref.watch(transactionsStreamProvider);

    return tx.when(
      error: (e, st) => AsyncValue.error(e, st),
      loading: () {
        final c = _analyticsCache;
        return c != null
            ? AsyncValue.data(c.snapshot)
            : const AsyncValue.loading();
      },
      data: (txns) {
        final sig = _signature(txns, range);
        final cached = _analyticsCache;
        if (cached != null && cached.sig == sig) {
          return AsyncValue.data(cached.snapshot);
        }
        // Recompute off-thread; keep serving the last snapshot meanwhile so the
        // dashboard doesn't flash while the new figures land a few ms later.
        final token = ++_token;
        _recompute(txns, range, sig, token);
        return cached != null
            ? AsyncValue.data(cached.snapshot)
            : const AsyncValue.loading();
      },
    );
  }

  Future<void> _recompute(List<Transaction> txns, AnalyticsRange range,
      String sig, int token) async {
    // Big ledgers → background isolate; small ones → next microtask (off the
    // current build, but not worth an isolate spawn).
    final snap = txns.length >= 400
        ? await Isolate.run(() => AnalyticsSnapshot.from(txns, range))
        : await Future(() => AnalyticsSnapshot.from(txns, range));
    if (token != _token) return; // superseded by a newer build
    _analyticsCache = (sig: sig, snapshot: snap);
    state = AsyncValue.data(snap);
  }
}

/// Last computed snapshot + the signature it was built from. A module-level
/// cache (rather than a provider) so it can be safely written during the
/// analytics provider's own build.
({String sig, AnalyticsSnapshot snapshot})? _analyticsCache;

/// A cheap fingerprint of the inputs: count + range + a running fold of each
/// transaction's id/amount/timestamp/direction/category. Cheaper than building
/// the snapshot's string-keyed maps, and changes whenever an item is added,
/// removed or edited.
///
/// Direction and category are part of the fold because the snapshot buckets on
/// both: recategorizing a transaction (or flipping debit↔credit) leaves the id,
/// amount, timestamp and count untouched, so without them the memoised snapshot
/// would be served forever and the category rings would never move.
String _signature(List<Transaction> txns, AnalyticsRange range) {
  var h = 17;
  for (final t in txns) {
    h = 0x1fffffff & (h * 31 + t.id.hashCode);
    h = 0x1fffffff & (h * 31 + t.amount.hashCode);
    h = 0x1fffffff & (h * 31 + t.timestamp.millisecondsSinceEpoch);
    h = 0x1fffffff & (h * 31 + t.direction.index);
    h = 0x1fffffff & (h * 31 + t.categoryId.hashCode);
  }
  return '${txns.length}|${range.start}|${range.end}|${range.label}|$h';
}
