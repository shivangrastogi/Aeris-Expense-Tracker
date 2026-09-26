import '../models/transaction.dart';

/// Pure checks run while entering a transaction — kept free of Flutter so
/// they're easy to unit test.
class EntryChecks {
  EntryChecks._();

  /// An existing transaction that looks like the same payment as the one
  /// being entered: same direction and amount, and either within
  /// [window] of it, or the same merchant on the same day. Catches the common
  /// "SMS already imported it, then I added it by hand" case.
  static Transaction? likelyDuplicate(
    Iterable<Transaction> existing, {
    required double amount,
    required TxnDirection direction,
    required DateTime when,
    String? merchant,
    String? excludeId,
    Duration window = const Duration(minutes: 15),
  }) {
    final m = merchant?.trim().toLowerCase() ?? '';
    Transaction? best;
    for (final t in existing) {
      if (t.id == excludeId) continue;
      if (t.direction != direction) continue;
      if ((t.amount - amount).abs() >= 0.01) continue;
      final close = t.timestamp.difference(when).abs() <= window;
      final sameMerchantDay = m.isNotEmpty &&
          (t.merchant?.trim().toLowerCase() ?? '') == m &&
          _sameDay(t.timestamp, when);
      if (!close && !sameMerchantDay) continue;
      if (best == null ||
          t.timestamp.difference(when).abs() <
              best.timestamp.difference(when).abs()) {
        best = t;
      }
    }
    return best;
  }

  /// Median amount of recent [direction] transactions in [categoryId], or
  /// null when there's too little history (< [minSamples]) to judge.
  static double? typicalAmount(
    Iterable<Transaction> existing, {
    required String categoryId,
    required TxnDirection direction,
    String? excludeId,
    int minSamples = 5,
    Duration lookback = const Duration(days: 180),
  }) {
    final since = DateTime.now().subtract(lookback);
    final xs = [
      for (final t in existing)
        if (t.id != excludeId &&
            t.categoryId == categoryId &&
            t.direction == direction &&
            t.timestamp.isAfter(since) &&
            t.amount > 0)
          t.amount,
    ]..sort();
    if (xs.length < minSamples) return null;
    final mid = xs.length ~/ 2;
    return xs.length.isOdd ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2;
  }

  /// True when [amount] is so far above [typical] it's probably a typo
  /// (an extra zero or two). Small amounts never trigger.
  static bool isUnusuallyLarge(double amount, double? typical,
          {double factor = 10, double floor = 1000}) =>
      typical != null && amount >= floor && amount >= typical * factor;

  /// Distinct recent payees for one-tap refill, newest first.
  static List<Transaction> recentTemplates(
    Iterable<Transaction> existing, {
    required TxnDirection direction,
    int limit = 6,
  }) {
    final sorted = existing
        .where((t) =>
            t.direction == direction &&
            (t.merchant?.trim().isNotEmpty ?? false) &&
            t.amount > 0)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final seen = <String>{};
    final out = <Transaction>[];
    for (final t in sorted) {
      if (seen.add(t.merchant!.trim().toLowerCase())) out.add(t);
      if (out.length == limit) break;
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
