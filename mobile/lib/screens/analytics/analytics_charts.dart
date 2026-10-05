part of 'analytics_screen.dart';

// Charts tab: stat tiles, donut, trend, income vs expense, daily/weekday
// bars, heatmap calendar and top merchants.

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
            Align(
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
        ? AerisColors.cardDark
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
        ? AerisColors.cardDark
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
                color: active ? AerisColors.accent(context) : scheme.outline,
                width: 2,
              ),
            ),
            child: active
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AerisColors.accent(context),
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
              : AerisColors.danger(context)),
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
        ? AerisColors.cardDark
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
              children: [
                Text(formatRupees(amount),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}% of spend',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AerisColors.ink(context)),
                ),
              ],
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onView(catId),
          icon: const Icon(Icons.arrow_forward, size: 17),
          label: Text('See ${cat.label} transactions'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AerisColors.accent(context),
            foregroundColor: AerisColors.onAccent(context),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
      TextButton(
        onPressed: onClear,
        child: Text('Clear selection',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
      ),
    ]);
  }
}

// ─── Spending trend ────────────────────────────────────────────────────────

class _TrendArea extends ConsumerWidget {
  final AnalyticsSnapshot snapshot;
  const _TrendArea({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = snapshot;
    final now = DateTime.now();
    final last = s.end.isBefore(now) ? s.end : now;
    final startDay = DateTime(s.start.year, s.start.month, s.start.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    final count = (lastDay.difference(startDay).inDays + 1).clamp(1, 366);

    double cum = 0;
    final spots = <(int, DateTime, double)>[];
    for (var i = 0; i < count; i++) {
      final d = startDay.add(Duration(days: i));
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      cum += s.dailyExpenseSeries[k] ?? 0;
      spots.add((i, d, cum));
    }

    if (spots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('No data yet.')),
      );
    }

    final total = spots.last.$3;
    final budgets = ref.watch(effectiveBudgetsProvider);
    final totalBudget = budgets
        .where((b) => b.categoryId != Budget.totalId)
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final peak = math.max(total, totalBudget) * 1.1;
    final peakY = peak == 0 ? 100.0 : peak;

    final labelEvery = (count / 5).ceil().clamp(1, 60);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(formatRupees(total),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(width: 8),
          Text('cumulative',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: RepaintBoundary(
              child: SfCartesianChart(
            margin: EdgeInsets.zero,
            plotAreaBorderWidth: 0,
            primaryXAxis: NumericAxis(
              minimum: 0,
              maximum: (count - 1).toDouble(),
              interval: labelEvery.toDouble(),
              majorGridLines: const MajorGridLines(width: 0),
              majorTickLines: const MajorTickLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle:
                  TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              axisLabelFormatter: (a) {
                final i = a.value.toInt();
                final text =
                    (i >= 0 && i < spots.length) ? '${spots[i].$2.day}' : '';
                return ChartAxisLabel(text, a.textStyle);
              },
            ),
            primaryYAxis: NumericAxis(
              minimum: 0,
              maximum: peakY,
              isVisible: true,
              labelPosition: ChartDataLabelPosition.inside,
              axisLabelFormatter: (a) => ChartAxisLabel('', a.textStyle),
              axisLine: const AxisLine(width: 0),
              majorTickLines: const MajorTickLines(width: 0),
              // Grid in the theme's outline colour — visible in light AND
              // dark (the old white-on-white lines vanished in light mode).
              majorGridLines: MajorGridLines(
                  width: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5)),
              plotBands: [
                if (totalBudget > 0)
                  PlotBand(
                    start: totalBudget,
                    end: totalBudget,
                    borderWidth: 1.5,
                    borderColor: AerisColors.warning.withValues(alpha: 0.7),
                    dashArray: const [4, 4],
                    text: 'Budget',
                    horizontalTextAlignment: TextAnchor.end,
                    verticalTextAlignment: TextAnchor.end,
                    textStyle: const TextStyle(
                        fontFamily: kFontFamily,
                        color: AerisColors.warning,
                        fontSize: 9,
                        fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            trackballBehavior: TrackballBehavior(
              enable: true,
              activationMode: ActivationMode.singleTap,
              lineColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              lineDashArray: const [4, 4],
              tooltipSettings: const InteractiveTooltip(
                  textStyle: TextStyle(
                      fontFamily: kFontFamily,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              builder: (context, details) {
                final y = details.point?.y?.toDouble() ?? 0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(formatRupees(y, compact: true),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                );
              },
            ),
            series: <CartesianSeries<(int, DateTime, double), int>>[
              SplineAreaSeries<(int, DateTime, double), int>(
                dataSource: spots,
                xValueMapper: (p, _) => p.$1,
                yValueMapper: (p, _) => p.$3,
                splineType: SplineType.monotonic, // no overshoot
                borderColor: AerisColors.accent(context),
                borderWidth: 2.5,
                animationDuration: reduceMotion(context) ? 0 : 600,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AerisColors.accent(context).withValues(alpha: 0.32),
                    AerisColors.accent(context).withValues(alpha: 0.02),
                  ],
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }
}

// ─── Income vs expense ─────────────────────────────────────────────────────

class _IncomeExpense extends StatelessWidget {
  final double income, expense;
  const _IncomeExpense({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final maxV = income > expense ? income : expense;
    final net = income - expense;
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      _IERow(
          label: 'Income',
          amt: income,
          max: maxV == 0 ? 1 : maxV,
          color: AerisColors.moneyIn(context),
          icon: Icons.north_east),
      const SizedBox(height: 10),
      _IERow(
          label: 'Expense',
          amt: expense,
          max: maxV == 0 ? 1 : maxV,
          color: AerisColors.moneyOut(context),
          icon: Icons.south_west),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Divider(
            height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Net saved',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          Text(
            '${net >= 0 ? '+' : ''}${formatRupees(net)}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: net >= 0
                    ? AerisColors.moneyIn(context)
                    : AerisColors.danger(context)),
          ),
        ],
      ),
    ]);
  }
}

class _IERow extends StatelessWidget {
  final String label;
  final double amt, max;
  final Color color;
  final IconData icon;
  const _IERow(
      {required this.label,
      required this.amt,
      required this.max,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    final pct = (amt / max).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
        const Spacer(),
        Text(formatRupees(amt),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: pct,
          minHeight: 12,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ),
    ]);
  }
}

// ─── Daily bars ────────────────────────────────────────────────────────────

class _DailyBars extends StatefulWidget {
  final Map<String, double> daily;
  final DateTime start, end;
  const _DailyBars(
      {required this.daily, required this.start, required this.end});

  @override
  State<_DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<_DailyBars> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = widget.end.isBefore(now) ? widget.end : now;
    final startDay =
        DateTime(widget.start.year, widget.start.month, widget.start.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    final count = (lastDay.difference(startDay).inDays + 1).clamp(1, 366);
    final take = count.clamp(1, 14);
    final days = <MapEntry<DateTime, double>>[];
    for (var i = count - take; i < count; i++) {
      final d = startDay.add(Duration(days: i));
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      days.add(MapEntry(d, widget.daily[k] ?? 0.0));
    }
    final maxV =
        days.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _hover = _hover == i ? null : i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_hover == i)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: AerisColors.accent(context)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          formatRupees(days[i].value, compact: true),
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: maxV == 0
                          ? 4.0
                          : math.max(4.0, days[i].value / maxV * 96),
                      decoration: BoxDecoration(
                        color: _hover == i
                            ? AerisColors.accent(context)
                            : AerisColors.accent(context)
                                .withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${days[i].key.day}',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Day of week bars ──────────────────────────────────────────────────────

class _DowBars extends StatelessWidget {
  final Map<String, double> daily;
  const _DowBars({required this.daily});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sums = List.filled(7, 0.0);
    for (final e in daily.entries) {
      final d = DateTime.tryParse(e.key);
      if (d != null) sums[d.weekday % 7] += e.value;
    }
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final maxV = sums.fold<double>(0, (a, b) => a > b ? a : b);
    final topIdx =
        maxV == 0 ? 0 : sums.indexOf(sums.reduce((a, b) => a > b ? a : b));

    return Column(children: [
      for (var i = 0; i < 7; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: 32,
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == topIdx
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: maxV == 0 ? 0 : sums[i] / maxV,
                  minHeight: 14,
                  color: i == topIdx
                      ? AerisColors.accent(context)
                      : AerisColors.accent(context).withValues(alpha: 0.35),
                  backgroundColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: Text(formatRupees(sums[i], compact: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
          ]),
        ),
      if (maxV > 0)
        Text(
          'You spend most on ${labels[topIdx]}days',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant),
        ),
    ]);
  }
}

// ─── Heatmap calendar ──────────────────────────────────────────────────────

class _HeatmapCal extends StatefulWidget {
  final Map<String, double> daily;
  const _HeatmapCal({required this.daily});

  @override
  State<_HeatmapCal> createState() => _HeatmapCalState();
}

class _HeatmapCalState extends State<_HeatmapCal> {
  int? _selDay;

  static const _months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    final firstDow = DateTime(year, month, 1).weekday % 7;
    final dim = DateTime(year, month + 1, 0).day;

    double maxV = 1;
    for (var d = 1; d <= dim; d++) {
      final k =
          '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final v = widget.daily[k] ?? 0;
      if (v > maxV) maxV = v;
    }

    final monthName = _months[month];
    final selKey = _selDay != null
        ? '$year-${month.toString().padLeft(2, '0')}-${_selDay.toString().padLeft(2, '0')}'
        : null;
    final selAmt = selKey != null ? (widget.daily[selKey] ?? 0.0) : 0.0;

    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$monthName $year',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant)),
          if (_selDay != null)
            Text(
              '$_selDay $monthName · ${formatRupees(selAmt)}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AerisColors.ink(context)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
            .map((l) => Expanded(
                  child: Text(l,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant)),
                ))
            .toList(),
      ),
      const SizedBox(height: 6),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
        ),
        itemCount: firstDow + dim,
        itemBuilder: (ctx, i) {
          if (i < firstDow) return const SizedBox();
          final day = i - firstDow + 1;
          final k =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final v = widget.daily[k] ?? 0.0;
          final t = (v / maxV).clamp(0.0, 1.0);
          final isToday =
              day == now.day && month == now.month && year == now.year;
          final isSel = _selDay == day;

          return GestureDetector(
            onTap: () => setState(() => _selDay = isSel ? null : day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: v == 0
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : AerisColors.accent(context)
                        .withValues(alpha: 0.2 + t * 0.8),
                borderRadius: BorderRadius.circular(8),
                border: isSel
                    ? Border.all(color: scheme.onSurface, width: 2)
                    : isToday
                        ? Border.all(
                            color: AerisColors.accent(context), width: 2)
                        : null,
              ),
              child: Center(
                child: Text('$day',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: t > 0.5
                            ? AerisColors.onAccent(context)
                            : scheme.onSurfaceVariant)),
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
                  color: AerisColors.accent(context).withValues(alpha: t),
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
                color: AerisColors.accent(context),
                backgroundColor:
                    AerisColors.accent(context).withValues(alpha: 0.12),
              ),
            ),
          ]),
        ),
    ]);
  }
}
