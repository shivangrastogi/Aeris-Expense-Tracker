import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../providers/transactions_provider.dart';
import '../utils/formatters.dart';

/// Angel One–style continuous chart: pinch-zoom, pan, and a crosshair
/// trackball that follows your finger. Toggles between daily spend and
/// running balance over a selectable date range.
class TrendChart extends ConsumerStatefulWidget {
  const TrendChart({super.key});

  @override
  ConsumerState<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends ConsumerState<TrendChart> {
  int _rangeDays = 90;
  bool _balance = false; // false = daily spend, true = cumulative net flow

  late final ZoomPanBehavior _zoom = ZoomPanBehavior(
    enablePinching: true,
    enablePanning: true,
    enableDoubleTapZooming: true,
    zoomMode: ZoomMode.x,
  );
  late final TrackballBehavior _trackball = TrackballBehavior(
    enable: true,
    activationMode: ActivationMode.singleTap,
    lineType: TrackballLineType.vertical,
    lineColor: Colors.grey,
    lineDashArray: const [4, 4],
  );

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final data = _series(txns, _rangeDays, _balance);
    final color = _balance ? AerisColors.seed : AerisColors.debit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_balance ? 'Cumulative net flow' : 'Daily spend trend',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                ),
                // Spend / Net toggle. "Net" is cumulative (credits − debits)
                // over the window, not a real account balance (we don't have
                // your opening balance), so it's labelled honestly.
                ToggleButtons(
                  isSelected: [!_balance, _balance],
                  onPressed: (i) => setState(() => _balance = i == 1),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 30, minWidth: 64),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  selectedColor: Theme.of(context).colorScheme.onPrimary,
                  fillColor: Theme.of(context).colorScheme.primary,
                  children: const [Text('Spend'), Text('Net')],
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Pinch to zoom · drag to pan · tap & hold for values',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 6),
            // Range selector
            Wrap(
              spacing: 6,
              children: [
                for (final r in const [
                  (30, '1M'),
                  (90, '3M'),
                  (180, '6M'),
                  (365, '1Y'),
                ])
                  ChoiceChip(
                    label: Text(r.$2),
                    selected: _rangeDays == r.$1,
                    onSelected: (_) => setState(() => _rangeDays = r.$1),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 240,
              child: data.isEmpty
                  ? const Center(child: Text('No data in this range yet.'))
                  : SfCartesianChart(
                      margin: EdgeInsets.zero,
                      plotAreaBorderWidth: 0,
                      zoomPanBehavior: _zoom,
                      trackballBehavior: _trackball,
                      primaryXAxis: DateTimeAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                        dateFormat: DateFormat.MMMd(),
                        intervalType: DateTimeIntervalType.auto,
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        majorTickLines: const MajorTickLines(size: 0),
                        majorGridLines: MajorGridLines(
                            width: 0.6,
                            color: Colors.grey.withOpacity(0.18)),
                        axisLabelFormatter: (a) => ChartAxisLabel(
                            formatRupees(a.value, compact: true), null),
                      ),
                      series: <CartesianSeries<_TrendPoint, DateTime>>[
                        SplineAreaSeries<_TrendPoint, DateTime>(
                          dataSource: data,
                          xValueMapper: (p, _) => p.date,
                          yValueMapper: (p, _) => p.value,
                          // Monotonic spline: never overshoots between points,
                          // so the curve can't imply spend on a zero day or dip
                          // below the real daily amounts.
                          splineType: SplineType.monotonic,
                          borderWidth: 2.5,
                          borderColor: color,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              color.withOpacity(0.35),
                              color.withOpacity(0.02),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build continuous daily series ──────────────────────────
  List<_TrendPoint> _series(List<Transaction> txns, int rangeDays, bool balance) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: rangeDays - 1));

    final net = <String, double>{};   // signed net per day
    final spend = <String, double>{}; // debit total per day
    double base = 0;                  // balance carried into the window
    for (final t in txns) {
      final k = _dayKey(t.timestamp);
      net[k] = (net[k] ?? 0) + t.signed;
      if (t.isDebit) spend[k] = (spend[k] ?? 0) + t.amount;
      if (t.timestamp.isBefore(start)) base += t.signed;
    }

    final pts = <_TrendPoint>[];
    double run = base;
    for (var d = 0; d < rangeDays; d++) {
      final day = start.add(Duration(days: d));
      final k = _dayKey(day);
      run += net[k] ?? 0;
      pts.add(_TrendPoint(day, balance ? run : (spend[k] ?? 0)));
    }
    return pts;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _TrendPoint {
  final DateTime date;
  final double value;
  const _TrendPoint(this.date, this.value);
}
