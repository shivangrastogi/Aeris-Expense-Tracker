import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../providers/transactions_provider.dart';
import '../utils/formatters.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startRaw = today.subtract(const Duration(days: _weeks * 7 - 1));
    // Snap the window start back to a Monday so columns are whole weeks.
    final firstMonday =
        startRaw.subtract(Duration(days: startRaw.weekday - 1));

    final daily = <DateTime, double>{};
    for (final t in txns) {
      if (!t.isDebit) continue;
      final d = DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      if (d.isBefore(firstMonday) || d.isAfter(today)) continue;
      daily[d] = (daily[d] ?? 0) + t.amount;
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
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
          : AerisColors.seed.withValues(alpha: a);
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
            borderRadius: BorderRadius.circular(3),
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
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending heatmap',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Last $_weeks weeks · tap a day',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
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
                Text('Less',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                for (final r in const [0.0, 0.3, 0.5, 0.75, 1.0])
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: levelColor(r == 0.0 ? 0 : r),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 6),
                Text('More',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDay(
      BuildContext context, DateTime day, double total, List<Transaction> txns) {
    final items = txns
        .where((t) =>
            t.isDebit &&
            t.timestamp.year == day.year &&
            t.timestamp.month == day.month &&
            t.timestamp.day == day.day)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${day.day}/${day.month}/${day.year}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(
                total > 0 ? formatRupees(total) : '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AerisColors.debit),
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Text('No spending on this day.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [for (final t in items) TransactionTile(txn: t)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
