import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../providers/analytics_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/category_donut.dart';
import '../../widgets/chart_card.dart';
import '../../widgets/range_selector.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/spending_heatmap.dart';
import '../../widgets/trend_chart.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String? _selectedCat;

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(analyticsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analytics.when(
        loading: () => const AnalyticsSkeleton(),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          // Drop the selection if that category isn't in the current range.
          final sel = (_selectedCat != null &&
                  s.byCategory.containsKey(_selectedCat))
              ? _selectedCat
              : null;
          return ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
          // Build charts a screen ahead so fast scrolling doesn't reveal blank
          // gaps while the (heavy) chart widgets paint.
          cacheExtent: 1000,
          children: [
            Align(alignment: Alignment.centerRight, child: const RangeSelector()),
            const SizedBox(height: 8),
            ChartCard(
              title: 'Spending by category',
              subtitle: '${s.label} — ${formatRupees(_sum(s.byCategory))}',
              height: 260,
              child: CategoryDonut(
                byCategory: s.byCategory,
                // Tap a slice → reveal an animated detail card below (no longer
                // navigates straight to the transaction list).
                onCategorySelected: (id) => setState(
                    () => _selectedCat = _selectedCat == id ? null : id),
              ),
            ),
            _CategoryDetailReveal(
              snapshot: s,
              categoryId: sel,
              onClose: () => setState(() => _selectedCat = null),
              onView: (id) => Navigator.pushNamed(
                  context, AppRoutes.transactions, arguments: id),
            ),
            const SizedBox(height: 14),
            ChartCard(
              title: 'Daily spend',
              subtitle: '${s.label} · debits only',
              height: 220,
              child: _DailyBar(
                  daily: s.dailyExpenseSeries, start: s.start, end: s.end),
            ),
            const SizedBox(height: 14),
            const SpendingHeatmap(),
            const SizedBox(height: 14),
            const TrendChart(),
            const SizedBox(height: 14),
            ChartCard(
              title: 'Income vs expense',
              subtitle: s.label,
              height: 220,
              child: _IncomeVsExpense(
                income: s.monthIncome, expense: s.monthExpense),
            ),
            const SizedBox(height: 14),
            ChartCard(
              title: 'Top merchants',
              subtitle: 'Where the money went · ${s.label}',
              height: 250,
              child: _TopMerchants(top: s.topMerchants),
            ),
            const SizedBox(height: 14),
            ChartCard(
              title: 'Cumulative spend',
              subtitle: 'Spend accumulating over ${s.label}',
              height: 240,
              child: _CumulativeLine(
                  daily: s.dailyExpenseSeries, start: s.start, end: s.end),
            ),
            const SizedBox(height: 14),
            ChartCard(
              title: 'Category mix radar',
              subtitle: 'Spread across categories · ${s.label}',
              height: 280,
              child: _CategoryRadar(byCategory: s.byCategory),
            ),
          ],
          );
        },
      ),
    );
  }

  double _sum(Map<String, double> m) =>
      m.values.fold(0.0, (a, b) => a + b);
}

// ── Animated category detail (replaces tap-to-navigate) ────────
// A glassy card that flips/scales into view (3D-ish) with the selected
// category's amount, share, count and average — plus a button to drill in.
class _CategoryDetailReveal extends StatelessWidget {
  final AnalyticsSnapshot snapshot;
  final String? categoryId;
  final VoidCallback onClose;
  final void Function(String id) onView;
  const _CategoryDetailReveal({
    required this.snapshot,
    required this.categoryId,
    required this.onClose,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, anim) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: anim,
          child: AnimatedBuilder(
            animation: curved,
            builder: (_, c) {
              final v = curved.value;
              return Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016) // perspective
                  ..rotateX((1 - v) * 0.9) // tilt up into place
                  ..scale(0.92 + 0.08 * v),
                child: c,
              );
            },
            child: child,
          ),
        );
      },
      child: categoryId == null
          ? const SizedBox(width: double.infinity, key: ValueKey('none'))
          : _card(context, categoryId!),
    );
  }

  Widget _card(BuildContext context, String id) {
    final cat = Categories.byId(id);
    final amount = snapshot.byCategory[id] ?? 0;
    final count = snapshot.countByCategory[id] ?? 0;
    final total = snapshot.byCategory.values.fold<double>(0, (a, b) => a + b);
    final pct = total == 0 ? 0.0 : amount / total;
    final avg = count == 0 ? 0.0 : amount / count;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cat.color.withValues(alpha: 0.20), cat.color.withValues(alpha: 0.05)],
          ),
          border: Border.all(color: cat.color.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cat.color.withValues(alpha: 0.22),
              child: Icon(cat.icon, color: cat.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(cat.label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ]),
          const SizedBox(height: 6),
          Text(formatRupees(amount),
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900, color: cat.color)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              color: cat.color,
              backgroundColor: cat.color.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _stat(context, '${(pct * 100).toStringAsFixed(0)}%', 'of spend'),
            _stat(context, '$count', count == 1 ? 'transaction' : 'transactions'),
            _stat(context, formatRupees(avg, compact: true), 'avg / txn'),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onView(id),
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('View transactions'),
              style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

// (Category breakdown now rendered by the CategoryDonut widget with
//  external leader-line labels — see lib/widgets/category_donut.dart.)

// ── Daily bar ──────────────────────────────────────────────

class _DailyBar extends StatelessWidget {
  final Map<String, double> daily;
  final DateTime start, end;
  const _DailyBar({required this.daily, required this.start, required this.end});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = end.isBefore(now) ? end : now;
    final startDay = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    final count = (lastDay.difference(startDay).inDays + 1).clamp(1, 366);
    final days = List.generate(count, (i) {
      final d = startDay.add(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return MapEntry(d, daily[key] ?? 0.0);
    });
    final labelEvery = (count / 6).ceil().clamp(1, 60);
    final barW = count > 60 ? 3.0 : (count > 30 ? 5.0 : 7.0);
    final maxY = days.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(BarChartData(
      maxY: maxY == 0 ? 100 : maxY * 1.2,
      minY: 0,
      alignment: BarChartAlignment.spaceBetween,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          tooltipBgColor: AerisColors.seed.withValues(alpha: 0.92),
          tooltipRoundedRadius: 8,
          getTooltipItem: (group, _, rod, __) => BarTooltipItem(
            formatRupees(rod.toY, compact: true),
            const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < days.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: days[i].value,
              width: barW,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AerisColors.seed.withValues(alpha: 0.55),
                  AerisColors.seed,
                ],
              ),
            ),
          ]),
      ],
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 24, interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= days.length || i % labelEvery != 0) {
              return const SizedBox.shrink();
            }
            final d = days[i].key;
            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 6,
              child: Text('${d.day}/${d.month}',
                  style: const TextStyle(fontSize: 9)),
            );
          },
        )),
      ),
    ));
  }
}

// (Monthly trend replaced by the interactive TrendChart with zoom/pan/
//  crosshair — see lib/widgets/trend_chart.dart.)

// ── Income vs expense (horizontal bars) ────────────────────

class _IncomeVsExpense extends StatelessWidget {
  final double income, expense;
  const _IncomeVsExpense({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final maxV = (income > expense ? income : expense);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _row('Income', income, maxV == 0 ? 1 : maxV, AerisColors.credit),
        const SizedBox(height: 18),
        _row('Expense', expense, maxV == 0 ? 1 : maxV, AerisColors.debit),
        const SizedBox(height: 18),
        Text('Net: ${formatRupees(income - expense)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: (income - expense) >= 0 ? AerisColors.credit : AerisColors.debit,
            )),
      ],
    );
  }

  Widget _row(String label, double v, double maxV, Color c) {
    final pct = (v / maxV).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(formatRupees(v)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct, minHeight: 14,
            color: c, backgroundColor: c.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

// ── Top merchants ──────────────────────────────────────────

class _TopMerchants extends StatelessWidget {
  final Map<String, double> top;
  const _TopMerchants({required this.top});

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) return const Center(child: Text('No merchant data yet.'));
    final entries = top.entries.toList();
    final maxV = entries.first.value;
    // A Column (not a ListView) so this card doesn't capture the page's scroll
    // gesture — there are only ever ≤8 rows, which fit the card height.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 90,
                child: Text(entries[i].key,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: entries[i].value / maxV,
                    minHeight: 14,
                    color: AerisColors.categoryPalette[i % AerisColors.categoryPalette.length],
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                  width: 70,
                  child: Text(formatRupees(entries[i].value, compact: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ]),
          ),
      ],
    );
  }
}

// ── Cumulative line ────────────────────────────────────────

class _CumulativeLine extends StatelessWidget {
  final Map<String, double> daily;
  final DateTime start, end;
  const _CumulativeLine(
      {required this.daily, required this.start, required this.end});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = end.isBefore(now) ? end : now;
    final startDay = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    final count = (lastDay.difference(startDay).inDays + 1).clamp(1, 366);
    final labelEvery = (count / 6).ceil().clamp(1, 60);
    final dates = <DateTime>[];
    final spots = <FlSpot>[];
    double cum = 0;
    for (var i = 0; i < count; i++) {
      final d = startDay.add(Duration(days: i));
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      cum += daily[k] ?? 0;
      dates.add(d);
      spots.add(FlSpot(i.toDouble(), cum));
    }
    return LineChart(LineChartData(
      minY: 0,
      minX: 0,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 46,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            axisSide: meta.axisSide,
            space: 6,
            child: Text(formatRupees(v, compact: true),
                style: const TextStyle(fontSize: 9)),
          ),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, interval: 1, reservedSize: 22,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= dates.length || i % labelEvery != 0) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 6,
              child: Text('${dates[i].day}/${dates[i].month}',
                  style: const TextStyle(fontSize: 9)),
            );
          },
        )),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          barWidth: 3, color: AerisColors.seed,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: AerisColors.seed.withValues(alpha: 0.16)),
        ),
      ],
    ));
  }
}

// ── Category radar ─────────────────────────────────────────

class _CategoryRadar extends StatelessWidget {
  final Map<String, double> byCategory;
  const _CategoryRadar({required this.byCategory});

  @override
  Widget build(BuildContext context) {
    if (byCategory.isEmpty) {
      return const Center(child: Text('No category data yet.'));
    }
    // Take top-6 categories so the radar stays readable.
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    // fl_chart's RadarChart asserts at least 3 entries.
    if (top.length < 3) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Spend across at least 3 categories to see the radar.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return RadarChart(RadarChartData(
      radarShape: RadarShape.polygon,
      radarBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
      gridBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      tickCount: 4,
      ticksTextStyle: TextStyle(
          fontSize: 8, color: Theme.of(context).colorScheme.onSurfaceVariant),
      titleTextStyle: TextStyle(
          fontSize: 10, color: Theme.of(context).colorScheme.onSurface),
      getTitle: (i, _) => RadarChartTitle(
          text: Categories.byId(top[i].key).label.split(' ').first),
      dataSets: [
        RadarDataSet(
          fillColor: AerisColors.seed.withValues(alpha: 0.3),
          borderColor: AerisColors.seed,
          borderWidth: 2,
          entryRadius: 3,
          dataEntries: [for (final e in top) RadarEntry(value: e.value)],
        ),
      ],
    ));
  }
}
