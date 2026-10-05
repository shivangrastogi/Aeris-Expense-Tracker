import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/money_providers.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/mascot/aeris_mascot.dart';
import '../gamification/future_self_screen.dart';

part 'analytics_charts.dart';
part 'analytics_ai.dart';
// ─── Shell ─────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Insights',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  _SegPill(
                      value: _tab, onChange: (i) => setState(() => _tab = i)),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  _ChartsTab(),
                  _AITab(),
                  FutureSelfScreen(embed: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Segmented pill ────────────────────────────────────────────────────────

class _SegPill extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChange;
  const _SegPill({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pill(context, 0, Icons.bar_chart_rounded, 'Charts'),
        _pill(context, 1, Icons.psychology_outlined, 'AI'),
        _pill(context, 2, Icons.savings_outlined, 'Future'),
      ]),
    );
  }

  Widget _pill(BuildContext context, int idx, IconData icon, String label) {
    final active = value == idx;
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
<<<<<<< HEAD
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChange(idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: active
                ? AerisColors.cardDecoration(context, radius: 11)
                : const BoxDecoration(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
=======
      child: GestureDetector(
        onTap: () => onChange(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AerisColors.seed : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.white : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Charts tab ────────────────────────────────────────────────────────────

class _ChartsTab extends ConsumerStatefulWidget {
  const _ChartsTab();
  @override
  ConsumerState<_ChartsTab> createState() => _ChartsTabState();
}

class _ChartsTabState extends ConsumerState<_ChartsTab> {
  String? _selectedCat;

  @override
  Widget build(BuildContext context) {
    // Watch the privacy flag directly: the tab is held const inside the
    // IndexedStack, so without this it wouldn't rebuild when the mask toggles
    // (amounts would stay visible until the next analytics emit).
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(analyticsProvider);

    return analytics.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (s) {
        final sel =
            (_selectedCat != null && s.byCategory.containsKey(_selectedCat))
                ? _selectedCat
                : null;
        final total = s.byCategory.values.fold(0.0, (a, b) => a + b);
        final txnCount = s.countByCategory.values.fold(0, (a, b) => a + b);
        final avgTxn = txnCount == 0 ? 0.0 : total / txnCount;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: _RangePillBtn(),
            ),
            const SizedBox(height: 10),
            _MiniStats(spent: total, saved: s.monthNet, avgTxn: avgTxn)
                .animate()
                .fadeIn(duration: 280.ms)
                .slideY(begin: 0.08, end: 0),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Spending by category',
              child: _DonutSection(
                byCategory: s.byCategory,
                countByCategory: s.countByCategory,
                selectedCat: sel,
                onSelect: (id) => setState(() => _selectedCat = id),
                onClear: () => setState(() => _selectedCat = null),
                onView: (id) => Navigator.pushNamed(
                    context, AppRoutes.transactions,
                    arguments: id),
              ),
            ).animate().fadeIn(duration: 320.ms, delay: 60.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Spending trend',
              child: _TrendArea(snapshot: s),
            ).animate().fadeIn(duration: 320.ms, delay: 100.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Income vs expense',
              child: _IncomeExpense(
                  income: s.monthIncome, expense: s.monthExpense),
            ).animate().fadeIn(duration: 320.ms, delay: 140.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Daily spend',
              child: _DailyBars(
                  daily: s.dailyExpenseSeries, start: s.start, end: s.end),
            ).animate().fadeIn(duration: 320.ms, delay: 180.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'By day of week',
              child: _DowBars(daily: s.dailyExpenseSeries),
            ).animate().fadeIn(duration: 320.ms, delay: 210.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Activity calendar',
              child: _HeatmapCal(daily: s.dailyExpenseSeries),
            ).animate().fadeIn(duration: 320.ms, delay: 250.ms),
            const SizedBox(height: 12),
            _InsightCard(
              title: 'Top merchants',
              child: _TopMerchants(top: s.topMerchants),
            ).animate().fadeIn(duration: 320.ms, delay: 290.ms),
          ],
        );
      },
    );
  }
}

// ─── Shared card shell ─────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _InsightCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─── Range pill ────────────────────────────────────────────────────────────

class _RangePillBtn extends ConsumerWidget {
  const _RangePillBtn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _show(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(99),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(range.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RangeSheet(ref: ref),
    );
  }
}

class _RangeSheet extends StatefulWidget {
  final WidgetRef ref;
  const _RangeSheet({required this.ref});
  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  bool _customOpen = false;
  DateTimeRange? _custom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;
    final current = widget.ref.read(analyticsRangeProvider);

    final options = <(String, AnalyticsRange)>[
      ('This month', AnalyticsRange.thisMonth()),
      ('Last month', AnalyticsRange.lastMonth()),
      ('Last 3 months', AnalyticsRange.lastDays(90, 'Last 3 months')),
      ('This year', AnalyticsRange.thisYear()),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Date range',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final opt in options)
            _RadioRow(
              label: opt.$1,
              active: current.label == opt.$1,
              onTap: () {
                widget.ref.read(analyticsRangeProvider.notifier).state = opt.$2;
                Navigator.pop(context);
              },
            ),
          GestureDetector(
            onTap: () => setState(() => _customOpen = !_customOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Icon(Icons.tune, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Custom range',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600))),
                Icon(
                  _customOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: scheme.onSurfaceVariant,
                ),
              ]),
            ),
          ),
          if (_customOpen) ...[
            Row(children: [
              Expanded(
                  child: _DateField(
                label: 'From',
                value: _custom?.start,
                onPick: (d) => setState(() {
                  _custom = DateTimeRange(
                      start: d, end: _custom?.end ?? DateTime.now());
                }),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _DateField(
                label: 'To',
                value: _custom?.end,
                onPick: (d) => setState(() {
                  _custom = DateTimeRange(start: _custom?.start ?? d, end: d);
                }),
              )),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _custom != null
                    ? () {
                        widget.ref.read(analyticsRangeProvider.notifier).state =
                            AnalyticsRange.custom(_custom!);
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Apply'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _RadioRow(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? AerisColors.seed : scheme.outline,
                width: 2,
              ),
            ),
            child: active
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AerisColors.seed,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  const _DateField(
      {required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            value != null
                ? '${value!.day}/${value!.month}/${value!.year}'
                : label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    value != null ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

// ─── Mini stats row ────────────────────────────────────────────────────────

class _MiniStats extends StatelessWidget {
  final double spent, saved, avgTxn;
  const _MiniStats(
      {required this.spent, required this.saved, required this.avgTxn});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      _StatCard(
          label: 'Spent',
          value: formatRupees(spent, compact: true),
          color: AerisColors.moneyOut(context)),
      const SizedBox(width: 8),
      _StatCard(
          label: 'Saved',
          value: formatRupees(saved.abs(), compact: true),
          color: saved >= 0
              ? AerisColors.moneyIn(context)
              : AerisColors.moneyOut(context)),
      const SizedBox(width: 8),
      _StatCard(
          label: 'Avg/txn',
          value: formatRupees(avgTxn, compact: true),
          color: scheme.onSurface),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Donut section ─────────────────────────────────────────────────────────

class _DonutSection extends StatelessWidget {
  final Map<String, double> byCategory;
  final Map<String, int> countByCategory;
  final String? selectedCat;
  final ValueChanged<String?> onSelect;
  final VoidCallback onClear;
  final void Function(String) onView;

  const _DonutSection({
    required this.byCategory,
    required this.countByCategory,
    required this.selectedCat,
    required this.onSelect,
    required this.onClear,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    if (byCategory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No spend data in this range.')),
      );
    }

    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = byCategory.values.fold(0.0, (a, b) => a + b);

    return Column(children: [
      SizedBox(
        height: 230,
        child: _DonutChart(
          entries: entries,
          total: total,
          selectedCat: selectedCat,
          onSelect: onSelect,
        ),
      ),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: selectedCat != null
            ? _CatDetail(
                key: const ValueKey('detail'),
                catId: selectedCat!,
                amount: byCategory[selectedCat] ?? 0,
                count: countByCategory[selectedCat] ?? 0,
                total: total,
                onClear: onClear,
                onView: onView,
              )
            : _DonutLegend(
                key: const ValueKey('legend'),
                entries: entries,
                onTap: (id) => onSelect(id),
              ),
      ),
      const SizedBox(height: 8),
    ]);
  }
}

class _DonutChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final String? selectedCat;
  final ValueChanged<String?> onSelect;

  const _DonutChart({
    required this.entries,
    required this.total,
    required this.selectedCat,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final centerLabel = selectedCat != null
        ? Categories.byId(selectedCat!).label.split(' ').first
        : 'Total spend';
    final centerAmt = selectedCat != null
        ? (entries
            .firstWhere((e) => e.key == selectedCat,
                orElse: () => const MapEntry('', 0))
            .value)
        : total;

    // RepaintBoundary: taps and slice animations repaint only the chart.
    return Stack(alignment: Alignment.center, children: [
      RepaintBoundary(
          child: SfCircularChart(
        margin: EdgeInsets.zero,
        series: <CircularSeries<MapEntry<String, double>, String>>[
          DoughnutSeries<MapEntry<String, double>, String>(
            dataSource: entries,
            xValueMapper: (e, _) => e.key,
            yValueMapper: (e, _) => e.value,
            pointColorMapper: (e, _) => Categories.byId(e.key).color,
            // Same geometry as before: a 60px hole, 48px ring, selected
            // slice pops out a little.
            innerRadius: '56%',
            radius: '100%',
            explode: true,
            explodeIndex: selectedCat == null
                ? null
                : entries.indexWhere((e) => e.key == selectedCat),
            explodeOffset: '6%',
            strokeColor: scheme.surface,
            strokeWidth: 2,
            animationDuration: reduceMotion(context) ? 0 : 600,
            onPointTap: (details) {
              final idx = details.pointIndex;
              if (idx == null || idx < 0 || idx >= entries.length) return;
              final id = entries[idx].key;
              onSelect(selectedCat == id ? null : id);
            },
          ),
        ],
      )),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(centerLabel,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(formatRupees(centerAmt, compact: true),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
        ],
      ),
    ]);
  }
}

class _DonutLegend extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final ValueChanged<String> onTap;
  const _DonutLegend({super.key, required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Wrap(
        spacing: 14,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final e in entries.take(6))
            GestureDetector(
              onTap: () => onTap(e.key),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Categories.byId(e.key).color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    Categories.byId(e.key).label.split(' ').first,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Tap a slice to drill into that category',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant)),
    ]);
  }
}

class _CatDetail extends StatelessWidget {
  final String catId;
  final double amount, total;
  final int count;
  final VoidCallback onClear;
  final void Function(String) onView;

  const _CatDetail({
    super.key,
    required this.catId,
    required this.amount,
    required this.count,
    required this.total,
    required this.onClear,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(catId);
    final pct = total == 0 ? 0.0 : amount / total;
    final avg = count == 0 ? 0.0 : amount / count;
    final scheme = Theme.of(context).colorScheme;

    return Column(children: [
      GestureDetector(
        onTap: () => onView(catId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(cat.icon, color: cat.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(
                    '$count txn${count == 1 ? '' : 's'} · avg ${formatRupees(avg, compact: true)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684
              children: [
                Icon(icon,
                    size: 16, color: active ? AerisColors.accent(context) : fg),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
<<<<<<< HEAD
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: fg)),
=======
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color:
                            t > 0.5 ? Colors.white : scheme.onSurfaceVariant)),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Tap a day for detail',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          Row(children: [
            Text('Less',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(width: 5),
            for (final t in [0.2, 0.45, 0.7, 1.0])
              Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  color: AerisColors.seed.withValues(alpha: t),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 5),
            Text('More',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
          ]),
        ],
      ),
    ]);
  }
}

// ─── Top merchants ─────────────────────────────────────────────────────────

class _TopMerchants extends StatelessWidget {
  final Map<String, double> top;
  const _TopMerchants({required this.top});

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No merchant data yet.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final entries = top.entries.toList();
    final maxV = entries.first.value;

    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i < entries.length - 1 ? 12 : 0),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text(entries[i].key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Text(formatRupees(entries[i].value),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: entries[i].value / maxV,
                minHeight: 8,
                color: AerisColors.seed,
                backgroundColor: AerisColors.seed.withValues(alpha: 0.12),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AI TAB
// ═══════════════════════════════════════════════════════════════════════════

class _AITab extends ConsumerStatefulWidget {
  const _AITab();
  @override
  ConsumerState<_AITab> createState() => _AITabState();
}

class _AITabState extends ConsumerState<_AITab> {
  int _insightIdx = 0;
  int _reactKey = 0;

  static const _insights = [
    'Your food spend is tracking 18% below last month — nice work 🎉',
    'You\'ve had some great no-spend days this month!',
    'Review any unused subscriptions to save more each month.',
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider); // rebuild instantly on mask toggle
    final b = ref.watch(insightsProvider);
    return b.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (bundle) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _AerisSaysCard(
            insightIdx: _insightIdx,
            reactKey: _reactKey,
            onTap: () => setState(() {
              _insightIdx = (_insightIdx + 1) % _insights.length;
              _reactKey++;
            }),
          ).animate().fadeIn(duration: 280.ms),
          const SizedBox(height: 12),
          _PredictionBanner(estimate: bundle.monthEstimate)
              .animate()
              .fadeIn(duration: 280.ms, delay: 60.ms),
          const SizedBox(height: 20),
          if (bundle.budgetProjections.isNotEmpty) ...[
            const _SectionHead('Budget projections'),
            _BudgetProjectionsCard(projections: bundle.budgetProjections)
                .animate()
                .fadeIn(duration: 280.ms, delay: 100.ms),
            const SizedBox(height: 20),
          ],
          const _SectionHead('Recommendations'),
          if (bundle.recommendations.isEmpty)
            const _EmptyCard('Nothing to flag yet — keep using the app!'),
          for (final r in bundle.recommendations.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecoCard(r: r)
                  .animate()
                  .fadeIn(duration: 280.ms, delay: 140.ms),
            ),
          const SizedBox(height: 10),
          const _SectionHead('Anomalies'),
          if (bundle.anomalies.isEmpty)
            const _EmptyCard('Nothing anomalous in recent activity.'),
          for (final a in bundle.anomalies.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AnomalyCard(a: a)
                  .animate()
                  .fadeIn(duration: 280.ms, delay: 180.ms),
            ),
          const SizedBox(height: 10),
          const _AskAerisBtn().animate().fadeIn(duration: 280.ms, delay: 220.ms),
        ],
      ),
    );
  }
}

// ─── Aeris says card ───────────────────────────────────────────────────────

class _AerisSaysCard extends StatelessWidget {
  final int insightIdx, reactKey;
  final VoidCallback onTap;
  const _AerisSaysCard(
      {required this.insightIdx, required this.reactKey, required this.onTap});

  static const _insights = [
    'Your food spend is tracking 18% below last month — nice work 🎉',
    'You\'ve had some great no-spend days this month!',
    'Review any unused subscriptions to save more each month.',
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AerisColors.seed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AerisColors.seed.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AerisMascot(
                mood: MascotMood.celebrate, size: 50, reactKey: reactKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AERIS SAYS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.ink(context),
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _insights[insightIdx],
                      key: ValueKey(insightIdx),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45),
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
}

// ─── Prediction banner ─────────────────────────────────────────────────────

class _PredictionBanner extends StatelessWidget {
  final Prediction estimate;
  const _PredictionBanner({required this.estimate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: AerisColors.violetGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x4D6366F1), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(children: [
        const Positioned(
          right: -10,
          top: -10,
          child: Opacity(
            opacity: 0.2,
            child: Icon(Icons.online_prediction,
                size: 110, color: Colors.white),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Predicted month-end spend',
                style: TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatRupees(estimate.estimate),
                  maxLines: 1,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_down,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(estimate.basis,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

// ─── Section heading ───────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  final String title;
  const _SectionHead(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
}

// ─── Budget projections card ───────────────────────────────────────────────

class _BudgetProjectionsCard extends StatelessWidget {
  final List<BudgetProjection> projections;
  const _BudgetProjectionsCard({required this.projections});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        for (var i = 0; i < projections.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.2)),
          _BpRow(bp: projections[i], isLast: i == projections.length - 1),
        ],
      ]),
    );
  }
}

class _BpRow extends StatelessWidget {
  final BudgetProjection bp;
  final bool isLast;
  const _BpRow({required this.bp, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(bp.categoryId);
    final (Color color, IconData icon, String label) = bp.alreadyOver
        ? (AerisColors.moneyOut(context), Icons.error, 'Over budget')
        : bp.willExceed
            ? (AerisColors.warning, Icons.warning, 'At risk')
            : (AerisColors.moneyIn(context), Icons.check_circle, 'On track');
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, isLast ? 12 : 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(cat.icon, color: cat.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.label,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(
                '${formatRupees(bp.spentSoFar, compact: true)} of ${formatRupees(bp.cap, compact: true)}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ]),
      ]),
    );
  }
}

// ─── Recommendation card ───────────────────────────────────────────────────

class _RecoCard extends StatelessWidget {
  final Recommendation r;
  const _RecoCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final (Color c, Color tint, IconData fallback) = switch (r.severity) {
      InsightSeverity.warning => (
          AerisColors.warning,
          const Color(0x1AE08C00),
          Icons.restaurant
        ),
      InsightSeverity.info => (
          AerisColors.info,
          const Color(0x1A3B82F6),
          Icons.subscriptions
        ),
      InsightSeverity.positive => (
          AerisColors.moneyIn(context),
          const Color(0x1A15A24A),
          Icons.savings
        ),
      InsightSeverity.alert => (
          AerisColors.moneyOut(context),
          const Color(0x1AE5484D),
          Icons.priority_high
        ),
    };
    final icon =
        r.categoryId != null ? Categories.byId(r.categoryId!).icon : fallback;
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(r.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: scheme.onSurfaceVariant)),
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684
              ],
            ),
          ),
        ),
<<<<<<< HEAD
=======
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unusual: ${a.merchant ?? 'transaction'} ${formatRupees(a.amount, compact: true)}',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(a.reason,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Ask Aeris button ──────────────────────────────────────────────────────

class _AskAerisBtn extends StatelessWidget {
  const _AskAerisBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF122120)
        : Colors.white;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          const AerisMascot(mood: MascotMood.happy, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ask Aeris',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                Text('"How much on food last week?"',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const Icon(Icons.chat_bubble_outline,
              color: AerisColors.seed, size: 22),
        ]),
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684
      ),
    );
  }
}
