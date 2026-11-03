import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../providers/transactions_provider.dart';
import '../utils/formatters.dart';
import 'ds.dart';
import 'transaction_tile.dart';

/// A GitHub-contributions-style calendar of daily spend over the last ~18
/// weeks: each cell is a day, its colour intensity scales with how much was
/// spent that day. Tap a day to see that day's transactions. Fully on-device
/// from the existing transaction stream.
class SpendingHeatmap extends ConsumerWidget {
  const SpendingHeatmap({super.key});

  static const _weeks = 18;
  static const _cell = 14.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns =
        ref.watch(transactionsStreamProvider).asData?.value ?? const <Transaction>[];
    final tk = context.tk;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startRaw = today.subtract(const Duration(days: _weeks * 7 - 1));
    // Snap the window start back to a Monday so columns are whole weeks.
    final firstMonday =
        startRaw.subtract(Duration(days: startRaw.weekday - 1));

    final daily = <DateTime, double>{};
    for (final t in txns) {
      if (!t.isSpend) continue;
      final d = DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      if (d.isBefore(firstMonday) || d.isAfter(today)) continue;
      daily[d] = (daily[d] ?? 0) + t.spendAmount;
    }
    final maxV =
        daily.values.isEmpty ? 0.0 : daily.values.reduce((a, b) => a > b ? a : b);

    Color levelColor(double r) {
      final a = r <= 0
          ? null
          : r < 0.25
              ? 0.30
              : r < 0.5
                  ? 0.50
                  : r < 0.75
                      ? 0.75
                      : 1.0;
      return a == null
          ? tk.track
          : tk.acc.withValues(alpha: a);
    }

    Color cellColor(double v) =>
        levelColor(maxV <= 0 ? 0 : (v / maxV));

    final totalDays = today.difference(firstMonday).inDays + 1;
    final numWeeks = (totalDays / 7).ceil();

    Widget dayCell(DateTime d) {
      final future = d.isAfter(today);
      final v = daily[d] ?? 0;
      return GestureDetector(
        onTap: future ? null : () => _showDay(context, d, v, txns),
        child: Container(
          width: _cell,
          height: _cell,
          margin: const EdgeInsets.only(bottom: _gap),
          decoration: BoxDecoration(
            color: future ? Colors.transparent : cellColor(v),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    final columns = <Widget>[
      for (var w = 0; w < numWeeks; w++)
        Padding(
          padding: const EdgeInsets.only(right: _gap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var dow = 0; dow < 7; dow++)
                dayCell(firstMonday.add(Duration(days: w * 7 + dow))),
            ],
          ),
        ),
    ];

    final weekdayLabels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 7; i++)
          Container(
            height: _cell,
            margin: const EdgeInsets.only(bottom: _gap),
            alignment: Alignment.centerLeft,
            child: Text(
              i == 0 ? 'Mon' : i == 2 ? 'Wed' : i == 4 ? 'Fri' : '',
              style: TextStyle(fontSize: 10, color: tk.t2),
            ),
          ),
      ],
    );

    return AerisCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Spending heatmap'),
          const SizedBox(height: 2),
          Text('Last $_weeks weeks · tap a day',
              style: Ts.label.copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              weekdayLabels,
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true, // newest weeks shown first
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: columns),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less', style: TextStyle(fontSize: 11, color: tk.t2)),
              const SizedBox(width: 6),
              for (final r in const [0.0, 0.3, 0.5, 0.75, 1.0])
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: levelColor(r == 0.0 ? 0 : r),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 6),
              Text('More', style: TextStyle(fontSize: 11, color: tk.t2)),
            ],
          ),
        ],
      ),
    );
  }

  void _showDay(
      BuildContext context, DateTime day, double total, List<Transaction> txns) {
    final items = txns
        .where((t) =>
            t.isSpend &&
            t.timestamp.year == day.year &&
            t.timestamp.month == day.month &&
            t.timestamp.day == day.day)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    showDsSheet<void>(
      context,
      title: '${weekdays[day.weekday - 1]}, ${shortDate(day)}',
      subtitle: total > 0
          ? 'Spent ${signedMoney(total, credit: false)}'
          : 'No spending on this day.',
      scrollControlled: true,
      builder: (_) => items.isEmpty
          ? const SizedBox(height: 8)
          : SingleChildScrollView(
              child: ListGroup(children: [
                for (final t in items) TransactionTile(txn: t, showDate: false)
              ]),
            ),
    );
  }
}
