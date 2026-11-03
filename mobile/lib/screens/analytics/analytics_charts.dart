part of 'analytics_screen.dart';

// Charts tab: stat tiles, donut, trend, daily heat map, top merchants,
// income vs spending, daily / weekday bars.
//
// Data-viz rules (AERIS Design System §12): minimal axes, no heavy grid,
// labels on the data, the accent marks "now" and neutral marks the rest,
// 2 dp lines that end in a dot, bars with a 4 dp top radius.

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
    // Same for the salary lock: "Saved" and "Net saved" plus spending would
    // give the salary away, so they hide with it.
    ref.watch(incomeLockProvider);
    final analytics = ref.watch(analyticsProvider);
    final budgets = ref.watch(effectiveBudgetsProvider);

    return analytics.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: RisingLoader(width: 28)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Banner2(
          tone: Tone.bad,
          icon: PhFill.cloudX,
          title: "Couldn't load insights",
          body: '$e',
        ),
      ),
      data: (s) {
        final sel =
            (_selectedCat != null && s.byCategory.containsKey(_selectedCat))
                ? _selectedCat
                : null;
        final total = s.byCategory.values.fold(0.0, (a, b) => a + b);
        final txnCount = s.countByCategory.values.fold(0, (a, b) => a + b);
        final avgTxn = txnCount == 0 ? 0.0 : total / txnCount;
        final explicit = budgets
            .where((b) => b.categoryId == Budget.totalId)
            .fold<double>(0, (a, b) => a + b.monthlyCap);
        final catSum = budgets
            .where((b) => b.categoryId != Budget.totalId)
            .fold<double>(0, (a, b) => a + b.monthlyCap);
        final budget = explicit > 0 ? explicit : catSum;

        final cards = <Widget>[
          _InsightCard(
            title: 'Spending by category',
            child: _DonutSection(
              byCategory: s.byCategory,
              countByCategory: s.countByCategory,
              selectedCat: sel,
              monthLabel: s.label,
              onSelect: (id) => setState(() => _selectedCat = id),
              onClear: () => setState(() => _selectedCat = null),
              onView: (id) => Navigator.pushNamed(
                  context, AppRoutes.transactions,
                  arguments: id),
            ),
          ),
          _InsightCard(
            title: 'Spending trend',
            child: _TrendArea(snapshot: s),
          ),
          _HeatmapCal(daily: s.dailyExpenseSeries),
          _InsightCard(
            title: 'Top merchants',
            child: _TopMerchants(top: s.topMerchants),
          ),
          _InsightCard(
            title: 'Income vs spending',
            note: '6 months',
            child: _IncomeExpense(snapshot: s),
          ),
          _InsightCard(
            title: 'Last 14 days',
            child: _DailyBars(
                daily: s.dailyExpenseSeries, start: s.start, end: s.end),
          ),
          _InsightCard(
            title: 'By day of week',
            child: _DowBars(daily: s.dailyExpenseSeries),
          ),
        ];
        Widget column(Iterable<Widget> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in items) ...[c, const SizedBox(height: 16)],
              ],
            );

        return LayoutBuilder(builder: (context, box) {
          // Tablets / unfolded foldables: the cards in a 2-column grid.
          final wide = box.maxWidth >= 720;
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              const _Shortcuts(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MiniStats(
                      spent: total,
                      saved: s.monthNet,
                      income: s.monthIncome,
                      avgTxn: avgTxn,
                      txns: txnCount,
                      budget: budget,
                    ).animate().fadeIn(duration: Mo.standard),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: column([
                            for (var i = 0; i < cards.length; i += 2) cards[i]
                          ])),
                          const SizedBox(width: 16),
                          Expanded(
                              child: column([
                            for (var i = 1; i < cards.length; i += 2) cards[i]
                          ])),
                        ],
                      )
                    else
                      column(cards),
                  ],
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

// ─── Range pill (header) ───────────────────────────────────────────────────

class _RangePillBtn extends ConsumerWidget {
  const _RangePillBtn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final tk = context.tk;
    return Semantics(
      button: true,
      label: 'Date range: ${range.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _RangeSheet(ref: ref),
        ),
        child: Container(
          height: 40,
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tk.hair2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(range.label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: tk.t1)),
            const SizedBox(width: 6),
            Icon(PhBold.caretDown, size: 12, color: tk.t1),
          ]),
        ),
      ),
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
    final tk = context.tk;
    final current = widget.ref.read(analyticsRangeProvider);

    final options = <(String, AnalyticsRange)>[
      ('This month', AnalyticsRange.thisMonth()),
      ('Last month', AnalyticsRange.lastMonth()),
      ('Last 3 months', AnalyticsRange.lastDays(90, 'Last 3 months')),
      ('This year', AnalyticsRange.thisYear()),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Date range', style: Ts.title.copyWith(color: tk.t1)),
            const SizedBox(height: 12),
            ListGroup(inset: 16, children: [
              for (final opt in options)
                DsRow(
                  minHeight: 52,
                  title: opt.$1,
                  trailing: current.label == opt.$1
                      ? Icon(PhBold.check, size: 18, color: tk.acc)
                      : null,
                  onTap: () {
                    widget.ref.read(analyticsRangeProvider.notifier).state =
                        opt.$2;
                    Navigator.pop(context);
                  },
                ),
              DsRow(
                minHeight: 52,
                title: 'Custom range',
                leading: Icon(Ph.calendarBlank, size: 20, color: tk.t2),
                trailing: Icon(_customOpen ? Ph.caretUp : Ph.caretDown,
                    size: 16, color: tk.t3),
                onTap: () => setState(() => _customOpen = !_customOpen),
              ),
            ]),
            if (_customOpen) ...[
              const SizedBox(height: 12),
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
                const SizedBox(width: 8),
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
              FilledButton(
                onPressed: _custom != null
                    ? () {
                        widget.ref.read(analyticsRangeProvider.notifier).state =
                            AnalyticsRange.custom(_custom!);
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Apply'),
              ),
            ],
          ],
        ),
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
    final tk = context.tk;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: tk.t2)),
      const SizedBox(height: 6),
      InkWell(
        borderRadius: BorderRadius.circular(Rad.input),
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
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tk.field,
            borderRadius: BorderRadius.circular(Rad.input),
            border: Border.all(color: tk.hair),
          ),
          child: Row(children: [
            Icon(Ph.calendarBlank, size: 16, color: tk.t2),
            const SizedBox(width: 8),
            Text(
              value != null ? shortDate(value!) : 'Pick a date',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: value != null ? tk.t1 : tk.t3),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ─── Mini stats row ────────────────────────────────────────────────────────

class _MiniStats extends StatelessWidget {
  final double spent, saved, income, avgTxn, budget;
  final int txns;
  const _MiniStats({
    required this.spent,
    required this.saved,
    required this.income,
    required this.avgTxn,
    required this.txns,
    required this.budget,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StatCard(
          label: 'Spent',
          value: formatRupees(spent),
          sub: budget > 0
              ? 'of ${formatRupees(budget, compact: true)}'
              : 'this range',
          color: tk.t1,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Saved',
          value: kIncomeMasked
              ? formatIncome(0)
              : '${saved < 0 ? kMinus : ''}${formatRupees(saved.abs())}',
          sub: kIncomeMasked
              ? 'salary hidden'
              : income > 0
                  ? '${(saved / income * 100).round()}% of income'
                  : 'no income yet',
          color: saved >= 0 ? tk.ok : tk.bad,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Avg / txn',
          value: formatRupees(avgTxn),
          sub: '$txns txn${txns == 1 ? '' : 's'}',
          color: tk.t1,
        ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.sub,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AerisColors.cardDecoration(context, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(label),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: color)),
            ),
            const SizedBox(height: 4),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: tk.t2)),
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
  final String monthLabel;
  final ValueChanged<String?> onSelect;
  final VoidCallback onClear;
  final void Function(String) onView;

  const _DonutSection({
    required this.byCategory,
    required this.countByCategory,
    required this.selectedCat,
    required this.monthLabel,
    required this.onSelect,
    required this.onClear,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    if (byCategory.isEmpty) {
      return const EmptyState(
        icon: Ph.chartPieSlice,
        title: 'No spending yet',
        body: 'Spends in this range show up here by category.',
      );
    }

    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = byCategory.values.fold(0.0, (a, b) => a + b);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 184,
        child: _DonutChart(
          entries: entries,
          total: total,
          monthLabel: monthLabel,
          selectedCat: selectedCat,
          onSelect: onSelect,
        ),
      ),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: Mo.standard,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
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
                total: total,
                onTap: (id) => onSelect(id),
              ),
      ),
    ]);
  }
}

class _DonutChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final String monthLabel;
  final String? selectedCat;
  final ValueChanged<String?> onSelect;

  const _DonutChart({
    required this.entries,
    required this.total,
    required this.monthLabel,
    required this.selectedCat,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final centerLabel = selectedCat != null
        ? Categories.byId(selectedCat!).label
        : (monthLabel.toLowerCase() == 'this month'
            ? const [
                '',
                'January',
                'February',
                'March',
                'April',
                'May',
                'June',
                'July',
                'August',
                'September',
                'October',
                'November',
                'December'
              ][DateTime.now().month]
            : monthLabel);
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
            // A 20 dp ring; the selected slice steps out a little.
            innerRadius: '76%',
            radius: '100%',
            explode: true,
            explodeIndex: selectedCat == null
                ? null
                : entries.indexWhere((e) => e.key == selectedCat),
            explodeOffset: '4%',
            strokeColor: tk.surface,
            strokeWidth: 3,
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
      IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Overline(centerLabel),
            MoneyText(centerAmt,
                style: const TextStyle(
                    fontSize: 24,
                    height: 30 / 24,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ]);
  }
}

class _DonutLegend extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final ValueChanged<String> onTap;
  const _DonutLegend(
      {super.key,
      required this.entries,
      required this.total,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Column(children: [
      for (final e in entries)
        InkWell(
          onTap: () => onTap(e.key),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Categories.byId(e.key).color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(Categories.byId(e.key).label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tk.t1)),
              ),
              Text(total == 0 ? '0%' : '${(e.value / total * 100).round()}%',
                  style: TextStyle(
                      fontSize: 13,
                      color: tk.t2,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              SizedBox(
                width: 80,
                child: MoneyText(e.value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Icon(Ph.caretRight, size: 14, color: tk.t3),
            ]),
          ),
        ),
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
    final tk = context.tk;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          color: tk.sunken,
          borderRadius: BorderRadius.circular(16),
        ),
        child: DsRow(
          leading: CatTile.of(cat),
          title: cat.label,
          sub: '$count txn${count == 1 ? '' : 's'} · avg '
              '${formatRupees(avg, compact: true)}',
          onTap: () => onView(catId),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyText(amount),
              Text('${(pct * 100).toStringAsFixed(0)}% of spend',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: tk.t2)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => onView(catId),
        child: Text('See ${cat.label} transactions'),
      ),
      TextButton(
        onPressed: onClear,
        style: TextButton.styleFrom(foregroundColor: tk.t2),
        child: const Text('Show all categories'),
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
    final tk = context.tk;
    final now = DateTime.now();
    final last = s.end.isBefore(now) ? s.end : now;
    final startDay = DateTime(s.start.year, s.start.month, s.start.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    final endDay = DateTime(s.end.year, s.end.month, s.end.day);
    final count = (lastDay.difference(startDay).inDays + 1).clamp(1, 366);
    final span = (endDay.difference(startDay).inDays + 1).clamp(count, 366);

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child:
            Center(child: Text('No data yet.', style: TextStyle(color: tk.t2))),
      );
    }

    final total = spots.last.$3;
    final budgets = ref.watch(effectiveBudgetsProvider);
    final explicit = budgets
        .where((b) => b.categoryId == Budget.totalId)
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final catSum = budgets
        .where((b) => b.categoryId != Budget.totalId)
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final totalBudget = explicit > 0 ? explicit : catSum;
    final peak = math.max(total, totalBudget) * 1.1;
    final peakY = peak == 0 ? 100.0 : peak;
    final under = totalBudget > 0 ? totalBudget - total : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 140,
          child: RepaintBoundary(
              child: SfCartesianChart(
            margin: const EdgeInsets.only(right: 6, top: 6),
            plotAreaBorderWidth: 0,
            primaryXAxis: NumericAxis(
              minimum: 0,
              maximum: (span - 1).toDouble(),
              isVisible: false,
            ),
            primaryYAxis: NumericAxis(
              minimum: 0,
              maximum: peakY,
              isVisible: false,
              plotBands: [
                if (totalBudget > 0)
                  PlotBand(
                    start: totalBudget,
                    end: totalBudget,
                    borderWidth: 1,
                    borderColor: tk.bad.withValues(alpha: 0.7),
                    dashArray: const [2, 3],
                  ),
              ],
            ),
            trackballBehavior: TrackballBehavior(
              enable: true,
              activationMode: ActivationMode.singleTap,
              lineColor: tk.t3,
              lineDashArray: const [3, 4],
              builder: (context, details) {
                final y = details.point?.y?.toDouble() ?? 0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: tk.inv, borderRadius: BorderRadius.circular(8)),
                  child: Text(formatRupees(y, compact: true),
                      style: TextStyle(
                          color: tk.onInv,
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
                borderColor: tk.acc,
                borderWidth: 2,
                animationDuration: reduceMotion(context) ? 0 : 600,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tk.acc.withValues(alpha: 0.22),
                    tk.acc.withValues(alpha: 0),
                  ],
                ),
              ),
              // "Now": the line ends in the dot.
              ScatterSeries<(int, DateTime, double), int>(
                dataSource: [spots.last],
                xValueMapper: (p, _) => p.$1,
                yValueMapper: (p, _) => p.$3,
                color: tk.acc,
                borderColor: tk.surface,
                borderWidth: 2,
                markerSettings: const MarkerSettings(width: 9, height: 9),
                animationDuration: 0,
                enableTooltip: false,
              ),
            ],
          )),
        ),
        Container(height: 1, color: tk.hair),
        const SizedBox(height: 8),
        Row(children: [
          Text(shortDay(startDay),
              style: TextStyle(fontSize: 11, color: tk.t2)),
          Expanded(
            child: Text(
              'Today · ${formatRupees(total)}'
              '${under == null ? '' : under >= 0 ? ' · ${formatRupees(under, compact: true)} left' : ' · ${formatRupees(-under, compact: true)} over'}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: under != null && under < 0 ? tk.bad : tk.t1),
            ),
          ),
          Text(shortDay(endDay), style: TextStyle(fontSize: 11, color: tk.t2)),
        ]),
      ],
    );
  }
}

// ─── Income vs spending: six months of paired bars ─────────────────────────

class _IncomeExpense extends StatelessWidget {
  final AnalyticsSnapshot snapshot;
  const _IncomeExpense({required this.snapshot});

  static const _m = [
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
    final tk = context.tk;
    final now = DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1)
    ];
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final inc = [
      for (final m in months) snapshot.monthlyIncomeSeries[key(m)] ?? 0.0
    ];
    final out = [
      for (final m in months) snapshot.monthlyExpenseSeries[key(m)] ?? 0.0
    ];
    final maxV = [...inc, ...out].fold<double>(0, (a, b) => a > b ? a : b);
    final net = snapshot.monthIncome - snapshot.monthExpense;

    Widget legend(Color c, String l) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(l, style: TextStyle(fontSize: 12, color: tk.t2)),
        ]);

    Widget bar(double v, Color c, bool last) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: maxV == 0 ? 0 : v / maxV),
          duration: reduceMotion(context) ? Duration.zero : Mo.fill,
          curve: Mo.curve,
          builder: (_, f, __) => Container(
            width: 12,
            height: math.max(2, 112 * f),
            decoration: BoxDecoration(
              color: c.withValues(alpha: last ? 1 : 0.55),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        legend(tk.ok, 'Income'),
        const SizedBox(width: 14),
        legend(tk.acc, 'Spending'),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        // Grows with the font scale so labels never overflow at 1.3×.
        height: MediaQuery.textScalerOf(context).scale(132).clamp(132.0, 190.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 6; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (i == 5 && inc[i] > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                          '${((inc[i] - out[i]) / inc[i] * 100).round()}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: inc[i] >= out[i] ? tk.ok : tk.bad)),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bar(inc[i], tk.ok, i == 5),
                      const SizedBox(width: 3),
                      bar(out[i], tk.acc, i == 5),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < 6; i++)
          Expanded(
            child: Text(_m[months[i].month],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == 5 ? FontWeight.w700 : FontWeight.w400,
                    color: i == 5 ? tk.t1 : tk.t2)),
          ),
      ]),
      const SizedBox(height: 12),
      Container(height: 1, color: tk.hair),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Text('Net saved · ${snapshot.label}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: tk.t2)),
        ),
        IncomeText(net,
            credit: net >= 0,
            color: net >= 0 ? tk.ok : tk.bad,
            style: Ts.amountM),
      ]),
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
    final tk = context.tk;
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
                          color: tk.inv,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          formatRupees(days[i].value, compact: true),
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: tk.onInv),
                        ),
                      ),
                    AnimatedContainer(
                      duration: Mo.standard,
                      curve: Mo.curve,
                      height: maxV == 0
                          ? 2.0
                          : math.max(2.0, days[i].value / maxV * 96),
                      decoration: BoxDecoration(
                        // Accent marks "now" (today / the tapped day),
                        // neutral marks the rest.
                        color: _hover == i || i == days.length - 1
                            ? tk.acc
                            : tk.t3.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${days[i].key.day}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: tk.t2)),
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
    final tk = context.tk;
    final sums = List.filled(7, 0.0);
    for (final e in daily.entries) {
      final d = DateTime.tryParse(e.key);
      if (d != null) sums[d.weekday % 7] += e.value;
    }
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final maxV = sums.fold<double>(0, (a, b) => a > b ? a : b);
    final topIdx =
        maxV == 0 ? 0 : sums.indexOf(sums.reduce((a, b) => a > b ? a : b));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < 7; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          i == topIdx ? FontWeight.w700 : FontWeight.w600,
                      color: i == topIdx ? tk.t1 : tk.t2)),
            ),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                    color: tk.track, borderRadius: BorderRadius.circular(3)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: maxV == 0 ? 0 : sums[i] / maxV,
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          i == topIdx ? tk.acc : tk.t3.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(formatRupees(sums[i], compact: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == topIdx ? tk.t1 : tk.t2)),
            ),
          ]),
        ),
      if (maxV > 0)
        Text(
          'You spend most on ${labels[topIdx]}days',
          style: TextStyle(fontSize: 12, color: tk.t2),
        ),
    ]);
  }
}

// ─── Daily spending heat map ───────────────────────────────────────────────

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
  static const _dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    final firstDow = DateTime(year, month, 1).weekday - 1; // Monday-first
    final dim = DateTime(year, month + 1, 0).day;
    String key(int d) =>
        '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

    double maxV = 0;
    int? maxDay;
    for (var d = 1; d <= dim; d++) {
      final v = widget.daily[key(d)] ?? 0;
      if (v > maxV) {
        maxV = v;
        maxDay = d;
      }
    }
    final monthName = _months[month];
    final note = _selDay != null
        ? '$_selDay $monthName · ${formatRupees(widget.daily[key(_selDay!)] ?? 0)}'
        : maxDay != null
            ? 'Biggest: ${_dows[DateTime(year, month, maxDay).weekday - 1]} $maxDay $monthName'
            : null;
    // Five steps from the sunken well to the full accent.
    Color level(double t) =>
        Color.lerp(tk.sunken, tk.acc, t <= 0 ? 0 : 0.2 + 0.8 * t)!;

    return _InsightCard(
      title: 'Daily spending',
      note: note,
      child: Column(children: [
        Row(
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map((l) => Expanded(
                    child: Text(l,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tk.t3)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
          ),
          itemCount: firstDow + dim,
          itemBuilder: (ctx, i) {
            if (i < firstDow) return const SizedBox();
            final day = i - firstDow + 1;
            final v = widget.daily[key(day)] ?? 0.0;
            final t = maxV == 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
            final future = day > now.day;
            final isToday = day == now.day;
            final isSel = _selDay == day;
            final bg = future ? Colors.transparent : level(t);

            return GestureDetector(
              onTap: future
                  ? null
                  : () => setState(() => _selDay = isSel ? null : day),
              child: AnimatedContainer(
                duration: Mo.standard,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                  border: isSel
                      ? Border.all(color: tk.t1, width: 2)
                      : isToday
                          ? Border.all(color: tk.acc, width: 2)
                          : future
                              ? Border.all(color: tk.hair)
                              : null,
                ),
                child: Center(
                  child: Text('$day',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t > 0.55 ? tk.onAcc : tk.t2)),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: TextStyle(fontSize: 11, color: tk.t2)),
            const SizedBox(width: 4),
            for (final t in [0.0, 0.25, 0.5, 0.75, 1.0])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: level(t),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Text('More', style: TextStyle(fontSize: 11, color: tk.t2)),
          ],
        ),
      ]),
    );
  }
}

// ─── Top merchants ─────────────────────────────────────────────────────────

class _TopMerchants extends StatelessWidget {
  final Map<String, double> top;
  const _TopMerchants({required this.top});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    if (top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No merchant data yet.', style: TextStyle(color: tk.t2)),
      );
    }
    final entries = top.entries.toList();
    final maxV = entries.first.value;

    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i < entries.length - 1 ? 12 : 0),
          child: Row(children: [
            SizedBox(
              width: 16,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: tk.t2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entries[i].key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tk.t1)),
                  const SizedBox(height: 5),
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: tk.track,
                        borderRadius: BorderRadius.circular(3)),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: maxV == 0 ? 0 : entries[i].value / maxV,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == 0 ? tk.acc : tk.t3.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: MoneyText(entries[i].value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
  }
}
